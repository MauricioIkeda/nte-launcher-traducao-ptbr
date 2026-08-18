import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/install_receipt.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:nte_translation_launcher/services/receipt_repository.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  test('receipt saying originalExisted keeps native ownership authoritative', () async {
    final sandbox = await Directory.systemTemp.createTemp('nte-cleanroom-receipt-');
    try {
      final game = await createGame(sandbox, 'game');
      final paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
      final log = LauncherLog(paths.logFile);
      final safePaths = SafePathService();
      final receipts = ReceiptRepository(paths, log, safePaths);
      final service = InstallationService(
        paths,
        log,
        safePaths: safePaths,
        receipts: receipts,
      );
      const translated = [1, 2, 3, 4];
      const original = [8, 6, 4, 2];
      const name = 'pakchunk999-Windows_999_P.pak';
      const relative = 'Client/WindowsNoEditor/HT/Content/Paks/$name';
      final manifest = TranslationManifest.fromJson({
        'schemaVersion': 1,
        'translationVersion': 'nte-auto-cleanroom-receipt',
        'publishedAt': DateTime.utc(2026, 8, 18).toIso8601String(),
        'files': [
          {
            'name': name,
            'relativeDestination': relative,
            'url': 'https://github.com/example/releases/download/test/$name',
            'size': translated.length,
            'sha256': hashOf(translated),
          },
        ],
      });
      final stage = await createStage(sandbox, manifest, const [translated]);
      final destination = File(p.join(game.path, relative));
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(translated, flush: true);

      await receipts.write(
        game.path,
        InstallReceipt(
          schemaVersion: InstallReceipt.currentSchemaVersion,
          translationVersion: 'previous',
          installedAt: DateTime.utc(2026, 8, 18),
          gameDirectory: game.path,
          manifestPublishedAt: DateTime.utc(2026, 8, 18),
          files: [
            InstalledFileReceipt(
              relativePath: relative,
              installedSize: translated.length,
              installedSha256: hashOf(translated),
              originalExisted: true,
              originalSize: original.length,
              originalSha256: hashOf(original),
            ),
          ],
        ),
      );

      await expectLater(
        service.install(manifest, stage, game.path),
        throwsA(isA<InstallationException>()),
      );
      expect(await destination.readAsBytes(), translated);
      final retained = (await receipts.read(game.path)).receipt;
      expect(retained, isNotNull);
      expect(retained!.files.single.originalExisted, isTrue);
    } finally {
      await sandbox.delete(recursive: true);
    }
  });
}
