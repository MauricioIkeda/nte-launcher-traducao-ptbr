import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/launcher_log.dart';
import '../models/install_receipt.dart';
import '../models/translation_manifest.dart';
import 'file_integrity_service.dart';
import 'game_language_service.dart';
import 'receipt_repository.dart';
import 'safe_path_service.dart';

class InstallationService {
  InstallationService(
    this.paths,
    this.log, {
    FileIntegrityService? integrity,
    SafePathService? safePaths,
    ReceiptRepository? receipts,
    GameLanguageService? gameLanguage,
    this.afterDestinationReplaced,
  }) : integrity = integrity ?? FileIntegrityService(),
       safePaths = safePaths ?? SafePathService(),
       gameLanguage = gameLanguage ?? GameLanguageService(),
       receipts =
           receipts ??
           ReceiptRepository(paths, log, safePaths ?? SafePathService());

  static const gameExecutable = 'NTEGlobalLauncher.exe';
  static const alternateGameExecutable = 'NTE Global Launcher.exe';
  static const _launcherDirectories = ['', 'NTEGlobal', 'NTE Global'];
  static const _clientExecutableSegments = [
    'Client',
    'WindowsNoEditor',
    'HT',
    'Binaries',
    'Win64',
    'HTGame.exe',
  ];

  final AppPaths paths;
  final LauncherLog log;
  final FileIntegrityService integrity;
  final SafePathService safePaths;
  final ReceiptRepository receipts;
  final GameLanguageService gameLanguage;
  final Future<void> Function(File destination)? afterDestinationReplaced;

  Future<bool> hasReceipt(String gameDirectory) async =>
      (await receipts.read(gameDirectory)).receipt != null;

  Future<bool> isValidGameDirectory(String path) async =>
      await resolveGameDirectory(path) != null;

  Future<GameDirectoryResolution?> resolveGameDirectory(String path) async {
    final selected = path.trim();
    if (selected.isEmpty) {
      return null;
    }

    final selectedDirectory = p.normalize(p.absolute(selected));
    final candidates = <String>[selectedDirectory];
    final compactName = p
        .basename(selectedDirectory)
        .replaceAll(RegExp(r'[\s_-]+'), '')
        .toLowerCase();
    if (compactName == 'nteglobal') {
      candidates.add(p.dirname(selectedDirectory));
    }

    for (final candidate in candidates.toSet()) {
      final clientExecutable = File(
        p.joinAll([candidate, ..._clientExecutableSegments]),
      );
      if (!await clientExecutable.exists()) {
        continue;
      }
      final launcher = await findGameLauncher(candidate);
      if (launcher != null) {
        return GameDirectoryResolution(
          gameDirectory: candidate,
          launcherExecutable: launcher.path,
          selectedDirectory: selectedDirectory,
        );
      }
    }
    return null;
  }

  static Future<File?> findGameLauncher(String gameDirectory) async {
    for (final directory in _launcherDirectories) {
      for (final executable in const [
        gameExecutable,
        alternateGameExecutable,
      ]) {
        final candidate = File(
          p.joinAll([
            gameDirectory,
            if (directory.isNotEmpty) directory,
            executable,
          ]),
        );
        if (await candidate.exists()) {
          return candidate;
        }
      }
    }
    return null;
  }

  Future<void> install(
    TranslationManifest manifest,
    Directory stage,
    String gameDirectory,
  ) async {
    final resolved = await resolveGameDirectory(gameDirectory);
    if (resolved == null) {
      throw const InstallationException(
        'A instalação completa do NTE não foi encontrada na pasta selecionada.',
      );
    }
    gameDirectory = resolved.gameDirectory;
    final storage = await receipts.storageFor(gameDirectory);
    final operationLock = await _acquireOperationLock(storage);
    try {
      final receiptRead = await receipts.read(gameDirectory);
      if (receiptRead.isInvalid) {
        throw InstallationException(
          'O recibo existente é inválido; a instalação foi bloqueada.',
          cause: receiptRead.error,
        );
      }
      final previousReceipt = receiptRead.receipt;
      await storage.transactions.create(recursive: true);
      final transaction = Directory(
        p.join(
          storage.transactions.path,
          DateTime.now().microsecondsSinceEpoch.toString(),
        ),
      );
      await transaction.create(recursive: true);
      final journal = _TransactionJournal(
        gameDirectory: storage.gameDirectory,
        state: 'prepared',
        entries: [],
      );
      await _writeJournal(transaction, journal);

      Object? originalError;
      StackTrace? originalStack;
      LanguageSwitchResult? languageSwitch;
      try {
        final stageOperation = integrity.startOperation();
        for (final asset in manifest.files) {
          final source = File(p.join(stage.path, asset.name));
          final verified = await stageOperation.verify(
            file: source,
            expectedSize: asset.size,
            expectedSha256: asset.sha256,
          );
          if (!verified.isValid) {
            throw InstallationException(
              'Arquivo de download inválido: ${asset.name} '
              '(${verified.status.name}).',
            );
          }
        }

        final previousByPath = {
          for (final entry
              in previousReceipt?.files ?? const <InstalledFileReceipt>[])
            entry.relativePath.toLowerCase(): entry,
        };
        final receiptEntries = <InstalledFileReceipt>[];
        for (final asset in manifest.files) {
          final relative = safePaths.normalizeRelative(
            asset.relativeDestination,
          );
          final source = File(p.join(stage.path, asset.name));
          final destination = await safePaths.resolveFile(
            gameDirectory,
            relative,
          );
          final transactionBackup = await safePaths.resolveFile(
            p.join(transaction.path, 'previous'),
            relative,
          );
          final destinationExisted = await destination.exists();
          if (destinationExisted) {
            await transactionBackup.parent.create(recursive: true);
            await destination.copy(transactionBackup.path);
          }
          journal.entries.add(
            _TransactionEntry(
              relativePath: relative,
              destinationExisted: destinationExisted,
            ),
          );
          journal.state = 'backups-made';
          await _writeJournal(transaction, journal);

          var original = previousByPath[relative.toLowerCase()];
          if (original == null) {
            if (destinationExisted) {
              final originalSize = await destination.length();
              final originalHash = await integrity.calculateSha256(destination);
              final permanentBackup = await safePaths.resolveFile(
                storage.originals.path,
                relative,
              );
              await permanentBackup.parent.create(recursive: true);
              await destination.copy(permanentBackup.path);
              final backupCheck = await integrity.startOperation().verify(
                file: permanentBackup,
                expectedSize: originalSize,
                expectedSha256: originalHash,
              );
              if (!backupCheck.isValid) {
                throw InstallationException(
                  'Não foi possível validar o backup original de $relative.',
                );
              }
              original = InstalledFileReceipt(
                relativePath: relative,
                installedSize: asset.size,
                installedSha256: asset.sha256,
                originalExisted: true,
                originalSize: originalSize,
                originalSha256: originalHash,
              );
            } else {
              original = InstalledFileReceipt(
                relativePath: relative,
                installedSize: asset.size,
                installedSha256: asset.sha256,
                originalExisted: false,
              );
            }
          }

          await destination.parent.create(recursive: true);
          final temporary = File('${destination.path}.nte-new');
          if (await temporary.exists()) {
            await temporary.delete();
          }
          await source.copy(temporary.path);
          final temporaryCheck = await integrity.startOperation().verify(
            file: temporary,
            expectedSize: asset.size,
            expectedSha256: asset.sha256,
          );
          if (!temporaryCheck.isValid) {
            throw InstallationException(
              'O temporário de $relative falhou na validação.',
            );
          }
          if (await destination.exists()) {
            await destination.delete();
          }
          await temporary.rename(destination.path);
          await afterDestinationReplaced?.call(destination);
          final finalCheck = await integrity.startOperation().verify(
            file: destination,
            expectedSize: asset.size,
            expectedSha256: asset.sha256,
          );
          if (!finalCheck.isValid) {
            throw InstallationException(
              'O destino final de $relative falhou na validação.',
            );
          }
          receiptEntries.add(
            InstalledFileReceipt(
              relativePath: relative,
              installedSize: asset.size,
              installedSha256: asset.sha256,
              originalExisted: original.originalExisted,
              originalSize: original.originalSize,
              originalSha256: original.originalSha256,
            ),
          );
          journal.state = 'files-replaced';
          await _writeJournal(transaction, journal);
        }

        for (final asset in manifest.files) {
          final destination = await safePaths.resolveFile(
            gameDirectory,
            asset.relativeDestination,
          );
          final finalCheck = await integrity.startOperation().verify(
            file: destination,
            expectedSize: asset.size,
            expectedSha256: asset.sha256,
          );
          if (!finalCheck.isValid) {
            throw InstallationException(
              'A validação final falhou para ${asset.name}.',
            );
          }
        }
        journal.state = 'destinations-validated';
        await _writeJournal(transaction, journal);

        final installationCulture = manifest.localization?.installationCulture;
        if (installationCulture != null) {
          languageSwitch = await gameLanguage.ensureCulture(
            installationCulture,
            previous: previousReceipt?.textLanguage,
          );
          if (languageSwitch.changed) {
            await log.info(
              'Idioma textual do NTE alterado automaticamente para '
              '$installationCulture.',
            );
          } else if (languageSwitch.reason != null) {
            await log.info(
              'Idioma textual não foi alterado automaticamente: '
              '${languageSwitch.reason}',
            );
          }
        }

        await receipts.write(
          gameDirectory,
          InstallReceipt(
            schemaVersion: InstallReceipt.currentSchemaVersion,
            translationVersion: manifest.translationVersion,
            installedAt: DateTime.now().toUtc(),
            gameDirectory: storage.gameDirectory,
            manifestPublishedAt: manifest.publishedAt,
            gameBuildId: manifest.gameBuildId,
            sourceHash: manifest.sourceHash,
            textLanguage:
                languageSwitch?.receipt ?? previousReceipt?.textLanguage,
            files: receiptEntries,
          ),
        );
        journal.state = 'receipt-confirmed';
        await _writeJournal(transaction, journal);
        await transaction.delete(recursive: true);
        await log.info(
          'Tradução ${manifest.translationVersion} instalada e verificada '
          'em ${storage.id.substring(0, 12)}.',
        );
      } catch (error, stackTrace) {
        originalError = error;
        originalStack = stackTrace;
        await log.error(
          'Instalação falhou; iniciando rollback.',
          error: error,
          stackTrace: stackTrace,
        );
        Object? rollbackError;
        if (languageSwitch?.changed == true) {
          final languageRollback = await gameLanguage.restore(
            languageSwitch?.receipt,
          );
          if (!languageRollback.restored) {
            rollbackError = InstallationException(
              'A restauração do idioma textual ficou incompleta: '
              '${languageRollback.reason ?? 'motivo desconhecido'}.',
            );
          }
        }
        try {
          journal.state = 'rollback-started';
          await _writeJournal(transaction, journal);
          await _rollback(transaction, journal);
          journal.state = 'rollback-completed';
          await _writeJournal(transaction, journal);
          await transaction.delete(recursive: true);
        } catch (error, stackTrace) {
          rollbackError ??= error;
          await log.error(
            'O rollback da instalação ficou incompleto.',
            error: error,
            stackTrace: stackTrace,
          );
        }
        throw InstallationException(
          'A instalação falhou: $originalError'
          '${rollbackError == null ? '' : ' Rollback incompleto: $rollbackError'}',
          cause: originalError,
          rollbackError: rollbackError,
          stackTrace: originalStack,
        );
      }
    } finally {
      await _releaseOperationLock(operationLock);
    }
  }

  Future<RemovalResult> uninstall(String gameDirectory) async {
    final storage = await receipts.storageFor(gameDirectory);
    final receiptRead = await receipts.read(gameDirectory);
    final receipt = receiptRead.receipt;
    if (receipt == null) {
      throw InstallationException(
        receiptRead.isInvalid
            ? 'O recibo desta instalação é inválido.'
            : 'Não existe instalação registrada nesta pasta.',
        cause: receiptRead.error,
      );
    }

    final operationLock = await _acquireOperationLock(storage);
    try {
      final restored = <String>[];
      final preserved = <String>[];
      final failed = <String>[];
      for (final entry in receipt.files.reversed) {
        try {
          final destination = await safePaths.resolveFile(
            gameDirectory,
            entry.relativePath,
          );
          final current = await integrity.startOperation().verify(
            file: destination,
            expectedSize: entry.installedSize,
            expectedSha256: entry.installedSha256,
          );
          if (current.status != FileIntegrityStatus.valid &&
              current.status != FileIntegrityStatus.missing) {
            preserved.add(entry.relativePath);
            await log.info(
              'Remoção preservou ${entry.relativePath}: arquivo alterado '
              'depois da instalação.',
            );
            continue;
          }

          if (entry.originalExisted) {
            final original = await safePaths.resolveFile(
              storage.originals.path,
              entry.relativePath,
            );
            final backup = await integrity.startOperation().verify(
              file: original,
              expectedSize: entry.originalSize!,
              expectedSha256: entry.originalSha256!,
            );
            if (!backup.isValid) {
              failed.add(entry.relativePath);
              continue;
            }
            await destination.parent.create(recursive: true);
            final temporary = File('${destination.path}.nte-restore');
            if (await temporary.exists()) {
              await temporary.delete();
            }
            await original.copy(temporary.path);
            final temporaryCheck = await integrity.startOperation().verify(
              file: temporary,
              expectedSize: entry.originalSize!,
              expectedSha256: entry.originalSha256!,
            );
            if (!temporaryCheck.isValid) {
              failed.add(entry.relativePath);
              continue;
            }
            if (await destination.exists()) {
              await destination.delete();
            }
            await temporary.rename(destination.path);
            final finalCheck = await integrity.startOperation().verify(
              file: destination,
              expectedSize: entry.originalSize!,
              expectedSha256: entry.originalSha256!,
            );
            if (!finalCheck.isValid) {
              failed.add(entry.relativePath);
              continue;
            }
          } else if (await destination.exists()) {
            await destination.delete();
          }
          restored.add(entry.relativePath);
        } catch (error, stackTrace) {
          failed.add(entry.relativePath);
          await log.error(
            'Falha ao remover ${entry.relativePath}.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      final complete = preserved.isEmpty && failed.isEmpty;
      if (complete) {
        final languageRestore = await gameLanguage.restore(
          receipt.textLanguage,
        );
        if (languageRestore.restored) {
          await log.info('Idioma textual anterior do NTE restaurado.');
        } else if (languageRestore.preservedUserChoice) {
          await log.info(
            'Idioma textual atual foi preservado porque o usuário o alterou '
            'depois da instalação.',
          );
        } else if (receipt.textLanguage != null) {
          await log.info(
            'Não foi possível restaurar automaticamente o idioma textual: '
            '${languageRestore.reason ?? 'motivo desconhecido'}.',
          );
        }
        await receipts.deleteCurrent(gameDirectory);
        if (await storage.originals.exists()) {
          await storage.originals.delete(recursive: true);
        }
        if (await storage.transactions.exists()) {
          await storage.transactions.delete(recursive: true);
        }
        if (await storage.root.exists()) {
          final remaining = await storage.root.list().isEmpty;
          if (remaining) {
            await storage.root.delete();
          }
        }
        await log.info(
          'Tradução removida e originais restaurados em '
          '${storage.id.substring(0, 12)}.',
        );
      } else {
        final unresolved = {...preserved, ...failed};
        await receipts.write(
          gameDirectory,
          InstallReceipt(
            schemaVersion: receipt.schemaVersion,
            translationVersion: receipt.translationVersion,
            installedAt: receipt.installedAt,
            gameDirectory: receipt.gameDirectory,
            manifestSha256: receipt.manifestSha256,
            manifestPublishedAt: receipt.manifestPublishedAt,
            gameBuildId: receipt.gameBuildId,
            sourceHash: receipt.sourceHash,
            textLanguage: receipt.textLanguage,
            files: receipt.files
                .where((entry) => unresolved.contains(entry.relativePath))
                .toList(growable: false),
          ),
        );
        await log.info(
          'Remoção parcial: ${preserved.length} preservados e '
          '${failed.length} falhas. Recibo e backups foram mantidos.',
        );
      }
      return RemovalResult(
        complete: complete,
        restoredFiles: restored,
        preservedModifiedFiles: preserved,
        failedFiles: failed,
      );
    } finally {
      await _releaseOperationLock(operationLock);
    }
  }

  Future<RecoveryResult> recoverAbandoned(
    String gameDirectory,
    TranslationManifest manifest,
  ) async {
    final storage = await receipts.storageFor(gameDirectory);
    final unresolved = <String>[];
    final lockFile = File(p.join(storage.root.path, 'operation.lock'));
    if (await lockFile.exists()) {
      try {
        final lockData = jsonDecode(await lockFile.readAsString());
        final lockPid = lockData is Map<String, dynamic>
            ? lockData['pid']
            : null;
        if (lockPid is! int || await _processExists(lockPid)) {
          unresolved.add(lockFile.path);
          await log.info(
            'Uma operação de outra instância ainda está ativa; '
            'a recuperação foi adiada.',
          );
          return RecoveryResult(complete: false, unresolvedPaths: unresolved);
        }
        await lockFile.delete();
        await log.info('Lock abandonado de operação foi removido.');
      } catch (error, stackTrace) {
        unresolved.add(lockFile.path);
        await log.error(
          'Lock abandonado inválido foi preservado.',
          error: error,
          stackTrace: stackTrace,
        );
        return RecoveryResult(complete: false, unresolvedPaths: unresolved);
      }
    }
    if (await storage.transactions.exists()) {
      await for (final entity in storage.transactions.list()) {
        if (entity is! Directory) {
          continue;
        }
        try {
          final journal = await _readJournal(entity);
          if (!safePaths.sameDirectory(
            journal.gameDirectory,
            storage.gameDirectory,
          )) {
            throw const FormatException(
              'Transação pertence a outro diretório.',
            );
          }
          if (journal.state == 'receipt-confirmed' ||
              journal.state == 'rollback-completed') {
            await entity.delete(recursive: true);
          } else {
            await _rollback(entity, journal);
            await entity.delete(recursive: true);
            await log.info('Transação abandonada recuperada por rollback.');
          }
        } catch (error, stackTrace) {
          unresolved.add(entity.path);
          await log.error(
            'Transação abandonada não pôde ser recuperada.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    for (final asset in manifest.files) {
      final destination = await safePaths.resolveFile(
        gameDirectory,
        asset.relativeDestination,
      );
      for (final suffix in const ['.nte-new', '.nte-restore']) {
        final temporary = File('${destination.path}$suffix');
        if (!await temporary.exists()) {
          continue;
        }
        final destinationValid = (await integrity.startOperation().verify(
          file: destination,
          expectedSize: asset.size,
          expectedSha256: asset.sha256,
        )).isValid;
        if (destinationValid) {
          await temporary.delete();
        } else {
          unresolved.add(temporary.path);
        }
      }
    }
    return RecoveryResult(
      complete: unresolved.isEmpty,
      unresolvedPaths: unresolved,
    );
  }

  Future<void> _rollback(
    Directory transaction,
    _TransactionJournal journal,
  ) async {
    for (final entry in journal.entries.reversed) {
      final destination = await safePaths.resolveFile(
        journal.gameDirectory,
        entry.relativePath,
      );
      final backup = await safePaths.resolveFile(
        p.join(transaction.path, 'previous'),
        entry.relativePath,
      );
      if (entry.destinationExisted) {
        if (!await backup.exists()) {
          throw InstallationException(
            'Backup transacional ausente: ${entry.relativePath}.',
          );
        }
        await destination.parent.create(recursive: true);
        final temporary = File('${destination.path}.nte-restore');
        await backup.copy(temporary.path);
        if (await destination.exists()) {
          await destination.delete();
        }
        await temporary.rename(destination.path);
      } else if (await destination.exists()) {
        await destination.delete();
      }
    }
  }

  Future<_OperationLock> _acquireOperationLock(
    InstallationStorage storage,
  ) async {
    await storage.root.create(recursive: true);
    final file = File(p.join(storage.root.path, 'operation.lock'));
    var created = false;
    try {
      await file.create(exclusive: true);
      created = true;
      final handle = await file.open(mode: FileMode.write);
      await handle.writeString(
        jsonEncode({
          'pid': pid,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      await handle.flush();
      return _OperationLock(file, handle);
    } on FileSystemException catch (error) {
      if (created && await file.exists()) {
        await file.delete();
      }
      throw InstallationException(
        'Outra operação já está modificando esta instalação.',
        cause: error,
      );
    }
  }

  Future<void> _releaseOperationLock(_OperationLock lock) async {
    try {
      await lock.handle.close();
      if (await lock.file.exists()) {
        await lock.file.delete();
      }
    } catch (error, stackTrace) {
      await log.error(
        'Não foi possível limpar o lock da operação.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _processExists(int processId) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist.exe', [
          '/FI',
          'PID eq $processId',
          '/NH',
        ]);
        return result.exitCode == 0 &&
            RegExp(
              '\\b${RegExp.escape(processId.toString())}\\b',
            ).hasMatch(result.stdout.toString());
      }
      final result = await Process.run('kill', ['-0', '$processId']);
      return result.exitCode == 0;
    } on ProcessException {
      return true;
    }
  }

  Future<void> _writeJournal(
    Directory transaction,
    _TransactionJournal journal,
  ) async {
    final file = File(p.join(transaction.path, 'transaction.json'));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(journal.toJson())}\n',
      flush: true,
    );
    final previous = File('${file.path}.previous');
    if (await previous.exists()) {
      await previous.delete();
    }
    if (await file.exists()) {
      await file.rename(previous.path);
    }
    try {
      await temporary.rename(file.path);
      if (await previous.exists()) {
        await previous.delete();
      }
    } catch (_) {
      if (!await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      }
      rethrow;
    }
  }

  Future<_TransactionJournal> _readJournal(Directory transaction) async {
    final file = File(p.join(transaction.path, 'transaction.json'));
    final previous = File('${file.path}.previous');
    if (!await file.exists() && await previous.exists()) {
      await previous.rename(file.path);
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Diário de transação inválido.');
    }
    return _TransactionJournal.fromJson(decoded);
  }
}

class RemovalResult {
  const RemovalResult({
    required this.complete,
    required this.restoredFiles,
    required this.preservedModifiedFiles,
    required this.failedFiles,
  });

  final bool complete;
  final List<String> restoredFiles;
  final List<String> preservedModifiedFiles;
  final List<String> failedFiles;
}

class RecoveryResult {
  const RecoveryResult({required this.complete, required this.unresolvedPaths});

  final bool complete;
  final List<String> unresolvedPaths;
}

class _TransactionJournal {
  _TransactionJournal({
    required this.gameDirectory,
    required this.state,
    required this.entries,
  });

  final String gameDirectory;
  String state;
  final List<_TransactionEntry> entries;

  factory _TransactionJournal.fromJson(Map<String, dynamic> json) {
    final gameDirectory = json['gameDirectory'];
    final state = json['state'];
    final entries = json['entries'];
    if (gameDirectory is! String || state is! String || entries is! List) {
      throw const FormatException('Diário de transação incompleto.');
    }
    return _TransactionJournal(
      gameDirectory: gameDirectory,
      state: state,
      entries: entries.map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Entrada de transação inválida.');
        }
        return _TransactionEntry.fromJson(value);
      }).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'gameDirectory': gameDirectory,
    'state': state,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };
}

class _OperationLock {
  const _OperationLock(this.file, this.handle);

  final File file;
  final RandomAccessFile handle;
}

class _TransactionEntry {
  const _TransactionEntry({
    required this.relativePath,
    required this.destinationExisted,
  });

  final String relativePath;
  final bool destinationExisted;

  factory _TransactionEntry.fromJson(Map<String, dynamic> json) {
    final relativePath = json['relativePath'];
    final destinationExisted = json['destinationExisted'];
    if (relativePath is! String || destinationExisted is! bool) {
      throw const FormatException('Entrada de transação incompleta.');
    }
    return _TransactionEntry(
      relativePath: relativePath,
      destinationExisted: destinationExisted,
    );
  }

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'destinationExisted': destinationExisted,
  };
}

class GameDirectoryResolution {
  const GameDirectoryResolution({
    required this.gameDirectory,
    required this.launcherExecutable,
    required this.selectedDirectory,
  });

  final String gameDirectory;
  final String launcherExecutable;
  final String selectedDirectory;

  bool get wasAdjusted => !p.equals(gameDirectory, selectedDirectory);
}

class InstallationException implements Exception {
  const InstallationException(
    this.message, {
    this.cause,
    this.rollbackError,
    this.stackTrace,
  });

  final String message;
  final Object? cause;
  final Object? rollbackError;
  final StackTrace? stackTrace;

  @override
  String toString() => message;
}
