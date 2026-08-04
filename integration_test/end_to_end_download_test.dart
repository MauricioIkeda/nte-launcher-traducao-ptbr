@TestOn('windows')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'validates, installs and restores a local translation fixture',
    (_) async {
      final sandbox = await Directory.systemTemp.createTemp('nte-e2e-');
      addTearDown(() async {
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      });

      const contents = <List<int>>[
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
        [10, 11, 12],
        [13, 14, 15],
      ];
      const names = [
        'UniversalSigBypasser.asi',
        'version.dll',
        'pakchunk999-Windows_999_P.pak',
        'pakchunk999-Windows_999_P.utoc',
        'pakchunk999-Windows_999_P.ucas',
      ];
      final manifest = TranslationManifest.fromJson({
        'schemaVersion': 1,
        'translationVersion': 'integration-fixture',
        'publishedAt': '2026-07-29T12:00:00Z',
        'files': [
          for (var index = 0; index < names.length; index++)
            {
              'name': names[index],
              'relativeDestination': index < 2
                  ? 'Client/WindowsNoEditor/HT/Binaries/Win64/${names[index]}'
                  : 'Client/WindowsNoEditor/HT/Content/Paks/${names[index]}',
              'url': 'https://example.invalid/${names[index]}',
              'size': contents[index].length,
              'sha256': sha256.convert(contents[index]).toString(),
            },
        ],
      });
      final paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
      await paths.root.create(recursive: true);
      final log = LauncherLog(paths.logFile);
      final installer = InstallationService(paths, log);

      final stage = Directory(p.join(sandbox.path, 'stage'));
      await stage.create();
      for (var index = 0; index < manifest.files.length; index++) {
        await File(
          p.join(stage.path, manifest.files[index].name),
        ).writeAsBytes(contents[index]);
      }

      final game = Directory(p.join(sandbox.path, 'game'));
      await game.create(recursive: true);
      await File(
        p.join(game.path, InstallationService.gameExecutable),
      ).writeAsBytes(const [77, 90]);
      final clientExecutable = File(
        p.join(
          game.path,
          'Client',
          'WindowsNoEditor',
          'HT',
          'Binaries',
          'Win64',
          'HTGame.exe',
        ),
      );
      await clientExecutable.parent.create(recursive: true);
      await clientExecutable.writeAsBytes(const [77, 90]);

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
