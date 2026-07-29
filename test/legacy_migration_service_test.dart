import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/services/file_integrity_service.dart';
import 'package:nte_translation_launcher/services/legacy_migration_service.dart';
import 'package:nte_translation_launcher/services/receipt_repository.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory sandbox;
  late Directory game;
  late AppPaths paths;
  late ReceiptRepository receipts;
  late SafePathService safePaths;
  late LegacyMigrationService migration;
  final manifest = testManifest(
    contents: const [
      [1, 2, 3],
    ],
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-migration-');
    game = await createGame(sandbox, 'game');
    paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    final log = LauncherLog(paths.logFile);
    safePaths = SafePathService();
    receipts = ReceiptRepository(paths, log, safePaths);
    migration = LegacyMigrationService(
      paths: paths,
      log: log,
      integrity: FileIntegrityService(),
      receipts: receipts,
      safePaths: safePaths,
    );
  });

  tearDown(() => sandbox.delete(recursive: true));

  test(
    'migrates legacy receipt and originals only when association is proven',
    () async {
      final relative = safePaths.normalizeRelative(
        manifest.files.first.relativeDestination,
      );
      final destination = File(p.join(game.path, relative));
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes([1, 2, 3]);
      final original = File(p.join(paths.originals.path, relative));
      await original.parent.create(recursive: true);
      await original.writeAsBytes([9, 9, 9]);
      await paths.installReceipt.parent.create(recursive: true);
      await paths.installReceipt.writeAsString(
        jsonEncode({
          'version': manifest.translationVersion,
          'gameDirectory': game.path,
          'installedFiles': [relative],
          'originalsExisted': {relative: true},
        }),
      );

      final migrated = await migration.migrateWhenProvable(
        gameDirectory: game.path,
        loadedManifest: loaded(manifest),
      );

      expect(migrated, isTrue);
      final receipt = (await receipts.read(game.path)).receipt;
      expect(receipt?.files.single.originalSha256, hashOf([9, 9, 9]));
      expect(await paths.installReceipt.exists(), isTrue);
    },
  );

  test('preserves legacy data that points to another installation', () async {
    await paths.root.create(recursive: true);
    await paths.installReceipt.writeAsString(
      jsonEncode({
        'version': manifest.translationVersion,
        'gameDirectory': p.join(sandbox.path, 'old-game'),
        'installedFiles': const [],
        'originalsExisted': const {},
      }),
    );

    final migrated = await migration.migrateWhenProvable(
      gameDirectory: game.path,
      loadedManifest: loaded(manifest),
    );

    expect(migrated, isFalse);
    expect(await paths.installReceipt.exists(), isTrue);
  });

  test(
    'migrates a provable older installed version using its real hashes',
    () async {
      final relative = safePaths.normalizeRelative(
        manifest.files.first.relativeDestination,
      );
      final destination = File(p.join(game.path, relative));
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes([8, 8, 8]);
      await paths.root.create(recursive: true);
      await paths.installReceipt.writeAsString(
        jsonEncode({
          'version': 'nte-auto-older',
          'gameDirectory': game.path,
          'installedFiles': [relative],
          'originalsExisted': {relative: false},
        }),
      );

      final migrated = await migration.migrateWhenProvable(
        gameDirectory: game.path,
        loadedManifest: loaded(manifest),
      );

      final receipt = (await receipts.read(game.path)).receipt;
      expect(migrated, isTrue);
      expect(receipt?.translationVersion, 'nte-auto-older');
      expect(receipt?.files.single.installedSha256, hashOf([8, 8, 8]));
    },
  );

  test('does not migrate partially restored game files', () async {
    final relative = safePaths.normalizeRelative(
      manifest.files.first.relativeDestination,
    );
    await paths.root.create(recursive: true);
    await paths.installReceipt.writeAsString(
      jsonEncode({
        'version': manifest.translationVersion,
        'gameDirectory': game.path,
        'installedFiles': [relative],
        'originalsExisted': {relative: false},
      }),
    );
    final migrated = await migration.migrateWhenProvable(
      gameDirectory: game.path,
      loadedManifest: loaded(manifest),
    );
    expect(migrated, isFalse);
    expect((await receipts.read(game.path)).receipt, isNull);
  });

  test('invalid legacy JSON is preserved without deletion', () async {
    await paths.root.create(recursive: true);
    await paths.installReceipt.writeAsString('{');
    expect(
      await migration.migrateWhenProvable(
        gameDirectory: game.path,
        loadedManifest: loaded(manifest),
      ),
      isFalse,
    );
    expect(await paths.installReceipt.readAsString(), '{');
  });
}
