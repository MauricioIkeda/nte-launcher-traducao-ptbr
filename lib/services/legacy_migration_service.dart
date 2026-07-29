import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/launcher_log.dart';
import '../models/install_receipt.dart';
import '../models/loaded_translation_manifest.dart';
import 'file_integrity_service.dart';
import 'receipt_repository.dart';
import 'safe_path_service.dart';

class LegacyMigrationService {
  LegacyMigrationService({
    required this.paths,
    required this.log,
    required this.integrity,
    required this.receipts,
    required this.safePaths,
  });

  final AppPaths paths;
  final LauncherLog log;
  final FileIntegrityService integrity;
  final ReceiptRepository receipts;
  final SafePathService safePaths;

  Future<bool> migrateWhenProvable({
    required String gameDirectory,
    required LoadedTranslationManifest loadedManifest,
  }) async {
    if (!await paths.installReceipt.exists()) {
      return false;
    }
    final current = await receipts.read(gameDirectory);
    if (current.receipt != null) {
      return false;
    }
    try {
      final decoded = jsonDecode(await paths.installReceipt.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Recibo legado inválido.');
      }
      final legacyDirectory = decoded['gameDirectory'];
      final version = decoded['version'];
      final installedFiles = decoded['installedFiles'];
      final originalsExisted = decoded['originalsExisted'];
      if (legacyDirectory is! String ||
          version is! String ||
          installedFiles is! List ||
          originalsExisted is! Map<String, dynamic> ||
          !safePaths.sameDirectory(legacyDirectory, gameDirectory)) {
        await log.info(
          'Recibo legado preservado: associação com a pasta atual '
          'não pôde ser comprovada.',
        );
        return false;
      }

      final manifest = loadedManifest.manifest;
      final entries = <InstalledFileReceipt>[];
      for (final asset in manifest.files) {
        final relative = safePaths.normalizeRelative(asset.relativeDestination);
        if (!installedFiles
            .map((value) => value.toString())
            .contains(relative)) {
          return false;
        }
        final destination = await safePaths.resolveFile(
          gameDirectory,
          relative,
        );
        if (!await destination.exists()) {
          await log.info(
            'Recibo legado preservado: a instalação está parcialmente '
            'restaurada ou incompleta.',
          );
          return false;
        }
        final installedSize = await destination.length();
        final installedHash = await integrity.calculateSha256(destination);

        final hadOriginal = originalsExisted[relative] == true;
        int? originalSize;
        String? originalHash;
        if (hadOriginal) {
          final legacyBackup = File(p.join(paths.originals.path, relative));
          if (!await legacyBackup.exists()) {
            return false;
          }
          originalSize = await legacyBackup.length();
          originalHash = await integrity.calculateSha256(legacyBackup);
        }
        entries.add(
          InstalledFileReceipt(
            relativePath: relative,
            installedSize: installedSize,
            installedSha256: installedHash,
            originalExisted: hadOriginal,
            originalSize: originalSize,
            originalSha256: originalHash,
          ),
        );
      }

      final storage = await receipts.storageFor(gameDirectory);
      await storage.originals.create(recursive: true);
      for (final entry in entries.where((entry) => entry.originalExisted)) {
        final source = File(p.join(paths.originals.path, entry.relativePath));
        final target = await safePaths.resolveFile(
          storage.originals.path,
          entry.relativePath,
        );
        await target.parent.create(recursive: true);
        await source.copy(target.path);
      }
      await receipts.write(
        gameDirectory,
        InstallReceipt(
          schemaVersion: InstallReceipt.currentSchemaVersion,
          translationVersion: version,
          installedAt: (await paths.installReceipt.lastModified()).toUtc(),
          gameDirectory: storage.gameDirectory,
          manifestPublishedAt: (await paths.installReceipt.lastModified())
              .toUtc(),
          gameBuildId: manifest.gameBuildId,
          sourceHash: manifest.sourceHash,
          files: entries,
        ),
      );
      await log.info(
        'Dados legados migrados conservadoramente para '
        '${storage.id.substring(0, 12)}; originais legados foram preservados.',
      );
      return true;
    } catch (error, stackTrace) {
      await log.error(
        'Não foi possível migrar os dados legados; eles foram preservados.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
