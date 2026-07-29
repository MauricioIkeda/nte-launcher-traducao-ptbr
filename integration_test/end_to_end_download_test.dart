@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/core/trusted_http_client.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/download_service.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'downloads, validates, installs and restores the translation',
    (_) async {
      final sandbox = await Directory.systemTemp.createTemp('nte-e2e-');
      addTearDown(() async {
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      });

      await TrustedHttpClientFactory.initialize();
      final manifest = TranslationManifest.fromJson(
        jsonDecode(
              await rootBundle.loadString(
                'assets/manifest/translation_manifest.json',
              ),
            )
            as Map<String, dynamic>,
      );
      final paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
      await paths.root.create(recursive: true);
      final log = LauncherLog(paths.logFile);
      final downloads = DownloadService(paths, log);
      final installer = InstallationService(paths, log);

      final stage = await downloads.download(
        manifest,
        onProgress: (_, _, _) {},
        isCancelled: () => false,
      );

      final game = Directory(p.join(sandbox.path, 'game'));
      await game.create(recursive: true);
      await File(
        p.join(game.path, InstallationService.gameExecutable),
      ).writeAsBytes(const [77, 90]);

      final versionDll = File(
        p.join(
          game.path,
          'Client',
          'WindowsNoEditor',
          'HT',
          'Binaries',
          'Win64',
          'version.dll',
        ),
      );
      await versionDll.parent.create(recursive: true);
      const originalContents = [1, 2, 3, 4];
      await versionDll.writeAsBytes(originalContents);

      await installer.install(manifest, stage, game.path);
      final versionAsset = manifest.files.singleWhere(
        (file) => file.name == 'version.dll',
      );
      expect(await versionDll.length(), versionAsset.size);

      await installer.uninstall(game.path);
      expect(await versionDll.readAsBytes(), originalContents);

      for (final asset in manifest.files.where(
        (file) => file.name != 'version.dll',
      )) {
        final installed = File(
          p.joinAll([
            game.path,
            ...asset.relativeDestination.replaceAll('\\', '/').split('/'),
          ]),
        );
        expect(await installed.exists(), isFalse);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
