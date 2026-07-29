import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/launcher_log.dart';
import '../models/install_receipt.dart';
import 'safe_path_service.dart';

class InstallationStorage {
  const InstallationStorage({
    required this.id,
    required this.gameDirectory,
    required this.root,
  });

  final String id;
  final String gameDirectory;
  final Directory root;

  File get receipt => File(p.join(root.path, 'receipt.json'));
  Directory get originals => Directory(p.join(root.path, 'originals'));
  Directory get transactions => Directory(p.join(root.path, 'transactions'));
}

class ReceiptReadResult {
  const ReceiptReadResult({
    this.receipt,
    this.error,
    this.temporaryReceiptFound = false,
  });

  final InstallReceipt? receipt;
  final Object? error;
  final bool temporaryReceiptFound;

  bool get isInvalid => error != null;
}

class ReceiptRepository {
  ReceiptRepository(this.paths, this.log, this.safePaths);

  final AppPaths paths;
  final LauncherLog log;
  final SafePathService safePaths;

  Future<InstallationStorage> storageFor(String gameDirectory) async {
    final canonical = await safePaths.canonicalDirectory(gameDirectory);
    final id = sha256.convert(utf8.encode(canonical)).toString();
    return InstallationStorage(
      id: id,
      gameDirectory: canonical,
      root: Directory(p.join(paths.installations.path, id)),
    );
  }

  Future<ReceiptReadResult> read(String gameDirectory) async {
    final storage = await storageFor(gameDirectory);
    final temporary = File('${storage.receipt.path}.tmp');
    final previous = File('${storage.receipt.path}.previous');
    if (!await storage.receipt.exists()) {
      if (await previous.exists()) {
        try {
          await previous.rename(storage.receipt.path);
          await log.info(
            'Último recibo válido restaurado após escrita interrompida.',
          );
        } on FileSystemException catch (error, stackTrace) {
          await log.error(
            'Não foi possível restaurar o recibo anterior.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
    if (!await storage.receipt.exists()) {
      return ReceiptReadResult(temporaryReceiptFound: await temporary.exists());
    }
    try {
      final source = await storage.receipt.readAsString();
      if (source.trim().isEmpty) {
        throw const ReceiptFormatException('O recibo está vazio.');
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const ReceiptFormatException('O recibo não contém um objeto.');
      }
      final receipt = InstallReceipt.fromJson(decoded);
      if (!safePaths.sameDirectory(
        receipt.gameDirectory,
        storage.gameDirectory,
      )) {
        throw const ReceiptFormatException(
          'O recibo pertence a outro diretório.',
        );
      }
      for (final file in receipt.files) {
        safePaths.normalizeRelative(file.relativePath);
      }
      await log.info(
        'Recibo encontrado para ${storage.id.substring(0, 12)}: '
        '${receipt.translationVersion}.',
      );
      if (await previous.exists()) {
        await previous.delete();
      }
      return ReceiptReadResult(
        receipt: receipt,
        temporaryReceiptFound: await temporary.exists(),
      );
    } catch (error, stackTrace) {
      await log.error(
        'Recibo inválido para ${storage.id.substring(0, 12)}.',
        error: error,
        stackTrace: stackTrace,
      );
      return ReceiptReadResult(
        error: error,
        temporaryReceiptFound: await temporary.exists(),
      );
    }
  }

  Future<void> write(String gameDirectory, InstallReceipt receipt) async {
    final storage = await storageFor(gameDirectory);
    if (!safePaths.sameDirectory(
      storage.gameDirectory,
      receipt.gameDirectory,
    )) {
      throw const ReceiptFormatException(
        'Tentativa de escrever recibo para outro diretório.',
      );
    }
    await storage.root.create(recursive: true);
    final temporary = File('${storage.receipt.path}.tmp');
    final serialized =
        '${const JsonEncoder.withIndent('  ').convert(receipt.toJson())}\n';
    final sink = temporary.openWrite(mode: FileMode.write);
    sink.write(serialized);
    await sink.flush();
    await sink.close();

    final reread = jsonDecode(await temporary.readAsString());
    if (reread is! Map<String, dynamic>) {
      throw const ReceiptFormatException('Recibo temporário inválido.');
    }
    final validated = InstallReceipt.fromJson(reread);
    if (!safePaths.sameDirectory(
      validated.gameDirectory,
      storage.gameDirectory,
    )) {
      throw const ReceiptFormatException(
        'Recibo temporário pertence a outro diretório.',
      );
    }

    final previous = File('${storage.receipt.path}.previous');
    if (await previous.exists()) {
      await previous.delete();
    }
    if (await storage.receipt.exists()) {
      await storage.receipt.rename(previous.path);
    }
    try {
      await temporary.rename(storage.receipt.path);
      if (await previous.exists()) {
        await previous.delete();
      }
    } catch (_) {
      if (!await storage.receipt.exists() && await previous.exists()) {
        await previous.rename(storage.receipt.path);
      }
      rethrow;
    }
  }

  Future<void> deleteCurrent(String gameDirectory) async {
    final storage = await storageFor(gameDirectory);
    if (await storage.receipt.exists()) {
      await storage.receipt.delete();
    }
  }

  Future<List<InstallReceipt>> readOtherReceipts(String gameDirectory) async {
    final selected = await storageFor(gameDirectory);
    if (!await paths.installations.exists()) {
      return const [];
    }
    final results = <InstallReceipt>[];
    await for (final entity in paths.installations.list()) {
      if (entity is! Directory || p.basename(entity.path) == selected.id) {
        continue;
      }
      final file = File(p.join(entity.path, 'receipt.json'));
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          results.add(InstallReceipt.fromJson(decoded));
        }
      } catch (_) {
        // Invalid receipts are logged when their own installation is selected.
      }
    }
    return results;
  }
}
