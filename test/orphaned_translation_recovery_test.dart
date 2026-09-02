import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/translation_installation.dart';
import 'package:nte_translation_launcher/services/file_integrity_service.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:nte_translation_launcher/services/receipt_repository.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:nte_translation_launcher/services/translation_verification_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory sandbox;
  late Directory game;
  late AppPaths paths;
  late LauncherLog log;
  late SafePathService safePaths;
  late ReceiptRepository receipts;
  late TranslationVerificationService verifier;
  late InstallationService installer;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-orphan-recovery-');
    game = await createGame(sandbox, 'game');
    paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    log = LauncherLog(paths.logFile);
    safePaths = SafePathService();
    receipts = ReceiptRepository(paths, log, safePaths);
    verifier = TranslationVerificationService(
      integrity: FileIntegrityService(),
      receipts: receipts,
      safePaths: safePaths,
      log: log,
    );
    installer = InstallationService(
      paths,
      log,
      integrity: FileIntegrityService(),
      safePaths: safePaths,
      receipts: receipts,
    );
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('recovered receipt preserves and restores an existing original', () async {
    final manifest = testManifest(
      contents: const [
        [1, 2, 3],
      ],
    );
    final asset = manifest.files.single;
    final destination = File(p.join(game.path, asset.relativeDestination));
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes([1, 2, 3]);

    final storage = await receipts.storageFor(game.path);
    final original = await safePaths.resolveFile(
      storage.originals.path,
      asset.relativeDestination,
    );
    await original.parent.create(recursive: true);
    await original.writeAsBytes([9, 9, 9]);

    final result = await verifier.verify(
      loadedManifest: loaded(manifest),
      gameDirectory: game.path,
    );
    final receipt = (await receipts.read(game.path)).receipt;

    expect(result.status, TranslationInstallationStatus.installedCurrent);
    expect(receipt, isNotNull);
    expect(receipt!.files.single.originalExisted, isTrue);
    expect(receipt.files.single.originalSize, 3);
    expect(receipt.files.single.originalSha256, hashOf([9, 9, 9]));

    final removal = await installer.uninstall(game.path);

    expect(removal.complete, isTrue);
    expect(await destination.readAsBytes(), [9, 9, 9]);
    expect((await receipts.read(game.path)).receipt, isNull);
  });
}
