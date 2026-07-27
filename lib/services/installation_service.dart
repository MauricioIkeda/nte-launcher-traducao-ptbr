import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/launcher_log.dart';
import '../models/translation_manifest.dart';

class InstallationService {
  InstallationService(this.paths, this.log);

  static const gameExecutable = 'NTEGlobalLauncher.exe';

  final AppPaths paths;
  final LauncherLog log;

  Future<bool> isValidGameDirectory(String path) async {
    return File(p.join(path, gameExecutable)).exists();
  }

  Future<void> install(
    TranslationManifest manifest,
    Directory stage,
    String gameDirectory,
  ) async {
    if (!await isValidGameDirectory(gameDirectory)) {
      throw const InstallationException(
        'NTEGlobalLauncher.exe não foi encontrado na pasta selecionada.',
      );
    }

    final previousReceipt = await _readReceipt();
    final originals = <String, bool>{...?previousReceipt?.originalsExisted};
    final transaction = Directory(
      p.join(
        paths.transactions.path,
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
    await transaction.create(recursive: true);
    final touched = <String>[];

    try {
      for (final asset in manifest.files) {
        final relative = _normalizedRelativePath(asset.relativeDestination);
        final source = File(p.join(stage.path, asset.name));
        if (!await source.exists()) {
          throw InstallationException(
            'Arquivo validado não encontrado: ${asset.name}.',
          );
        }

        final destination = File(p.join(gameDirectory, relative));
        final transactionBackup = File(p.join(transaction.path, relative));
        await transactionBackup.parent.create(recursive: true);
        if (await destination.exists()) {
          await destination.copy(transactionBackup.path);
        }

        if (!originals.containsKey(relative)) {
          final hadOriginal = await destination.exists();
          originals[relative] = hadOriginal;
          if (hadOriginal) {
            final originalBackup = File(p.join(paths.originals.path, relative));
            await originalBackup.parent.create(recursive: true);
            await destination.copy(originalBackup.path);
          }
        }

        touched.add(relative);
        await destination.parent.create(recursive: true);
        final temporary = File('${destination.path}.nte-new');
        if (await temporary.exists()) {
          await temporary.delete();
        }
        await source.copy(temporary.path);
        if (await destination.exists()) {
          await destination.delete();
        }
        await temporary.rename(destination.path);
      }

      final receipt = InstallReceipt(
        version: manifest.translationVersion,
        gameDirectory: gameDirectory,
        installedFiles: manifest.files
            .map((asset) => _normalizedRelativePath(asset.relativeDestination))
            .toList(growable: false),
        originalsExisted: originals,
      );
      await _writeReceipt(receipt);
      await log.info('Tradução ${manifest.translationVersion} instalada.');
    } catch (error, stackTrace) {
      await log.error(
        'Instalação falhou; iniciando rollback.',
        error: error,
        stackTrace: stackTrace,
      );
      await _rollback(gameDirectory, transaction, touched);
      rethrow;
    } finally {
      if (await transaction.exists()) {
        await transaction.delete(recursive: true);
      }
    }
  }

  Future<void> uninstall() async {
    final receipt = await _readReceipt();
    if (receipt == null) {
      throw const InstallationException(
        'Não existe instalação registrada para remover.',
      );
    }

    for (final relative in receipt.installedFiles.reversed) {
      final destination = File(p.join(receipt.gameDirectory, relative));
      final original = File(p.join(paths.originals.path, relative));
      if (receipt.originalsExisted[relative] == true &&
          await original.exists()) {
        await destination.parent.create(recursive: true);
        final temporary = File('${destination.path}.nte-restore');
        await original.copy(temporary.path);
        if (await destination.exists()) {
          await destination.delete();
        }
        await temporary.rename(destination.path);
      } else if (await destination.exists()) {
        await destination.delete();
      }
    }

    if (await paths.installReceipt.exists()) {
      await paths.installReceipt.delete();
    }
    if (await paths.originals.exists()) {
      await paths.originals.delete(recursive: true);
    }
    await log.info('Tradução removida e arquivos originais restaurados.');
  }

  Future<void> _rollback(
    String gameDirectory,
    Directory transaction,
    List<String> touched,
  ) async {
    for (final relative in touched.reversed) {
      final destination = File(p.join(gameDirectory, relative));
      final backup = File(p.join(transaction.path, relative));
      if (await backup.exists()) {
        await destination.parent.create(recursive: true);
        if (await destination.exists()) {
          await destination.delete();
        }
        await backup.copy(destination.path);
      } else if (await destination.exists()) {
        await destination.delete();
      }
    }
  }

  String _normalizedRelativePath(String value) {
    final segments = value.replaceAll('\\', '/').split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw const InstallationException('Caminho inseguro no manifesto.');
    }
    return p.joinAll(segments);
  }

  Future<InstallReceipt?> _readReceipt() async {
    if (!await paths.installReceipt.exists()) {
      return null;
    }
    return InstallReceipt.fromJson(
      jsonDecode(await paths.installReceipt.readAsString())
          as Map<String, dynamic>,
    );
  }

  Future<void> _writeReceipt(InstallReceipt receipt) async {
    final temporary = File('${paths.installReceipt.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt.toJson()),
      flush: true,
    );
    if (await paths.installReceipt.exists()) {
      await paths.installReceipt.delete();
    }
    await temporary.rename(paths.installReceipt.path);
  }
}

class InstallReceipt {
  const InstallReceipt({
    required this.version,
    required this.gameDirectory,
    required this.installedFiles,
    required this.originalsExisted,
  });

  final String version;
  final String gameDirectory;
  final List<String> installedFiles;
  final Map<String, bool> originalsExisted;

  factory InstallReceipt.fromJson(Map<String, dynamic> json) {
    return InstallReceipt(
      version: json['version'] as String,
      gameDirectory: json['gameDirectory'] as String,
      installedFiles: (json['installedFiles'] as List<dynamic>).cast<String>(),
      originalsExisted: (json['originalsExisted'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as bool),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'gameDirectory': gameDirectory,
    'installedFiles': installedFiles,
    'originalsExisted': originalsExisted,
  };
}

class InstallationException implements Exception {
  const InstallationException(this.message);

  final String message;

  @override
  String toString() => message;
}
