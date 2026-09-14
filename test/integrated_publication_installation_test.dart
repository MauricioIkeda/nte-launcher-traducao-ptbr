import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/loaded_translation_manifest.dart';
import 'package:nte_translation_launcher/models/translation_installation.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/file_integrity_service.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:nte_translation_launcher/services/receipt_repository.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:nte_translation_launcher/services/translation_verification_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  test(
    'public contract installs, detects tampering, and repairs all five assets',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'nte-integrated-contract-',
      );
      try {
        final game = await createGame(sandbox, 'game');
        final paths = AppPaths.forTesting(
          Directory(p.join(sandbox.path, 'app')),
        );
        final log = LauncherLog(paths.logFile);
        final safePaths = SafePathService();
        final receipts = ReceiptRepository(paths, log, safePaths);
        final installer = InstallationService(
          paths,
          log,
          integrity: FileIntegrityService(),
          safePaths: safePaths,
          receipts: receipts,
        );
        final verifier = TranslationVerificationService(
          integrity: FileIntegrityService(),
          receipts: receipts,
          safePaths: safePaths,
          log: log,
        );
        const names = [
          'UniversalSigBypasser.asi',
          'version.dll',
          'pakchunk999-Windows_999_P.pak',
          'pakchunk999-Windows_999_P.utoc',
          'pakchunk999-Windows_999_P.ucas',
        ];
        const contents = [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
          [10, 11, 12],
          [13, 14, 15],
        ];
        const sourceHash =
            '0123456789abcdef0123456789abcdef'
            '0123456789abcdef0123456789abcdef';
        const version = 'nte-auto-20260729-120100-0123456789ab';
        final manifest = TranslationManifest.fromJson({
          'schemaVersion': 1,
          'translationVersion': version,
          'publishedAt': '2026-07-29T12:01:00.987Z',
          'gameBuildId': 'nte-build-integrated',
          'sourceHash': sourceHash,
          'files': [
            for (var index = 0; index < names.length; index++)
              {
                'name': names[index],
                'relativeDestination': index < 2
                    ? 'Client/WindowsNoEditor/HT/Binaries/Win64/'
                          '${names[index]}'
                    : 'Client/WindowsNoEditor/HT/Content/Paks/'
                          '${names[index]}',
                'url':
                    'https://github.com/MauricioIkeda/nte-ptbr-releases/'
                    'releases/download/$version/${names[index]}',
                'size': contents[index].length,
                'sha256': hashOf(contents[index]),
              },
          ],
        });
        final stage = await createStage(sandbox, manifest, contents);
        final loadedManifest = LoadedTranslationManifest(
          manifest: manifest,
          source: ManifestSource.remote,
        );

        await installer.install(manifest, stage, game.path);
        var verification = await verifier.verify(
          loadedManifest: loadedManifest,
          gameDirectory: game.path,
        );
        expect(
          verification.status,
          TranslationInstallationStatus.installedCurrent,
        );
        expect(verification.validFiles, hasLength(5));

        // Exercise ordinary repair with a non-container asset. PAK/UTOC/UCAS
        // are intentionally protected from blind overwrite because a game
        // update may have legitimately taken ownership of the same path.
        final tampered = File(
          p.join(game.path, manifest.files[1].relativeDestination),
        );
        await tampered.writeAsBytes([99, 99, 99]);
        verification = await verifier.verify(
          loadedManifest: loadedManifest,
          gameDirectory: game.path,
        );
        expect(verification.status, TranslationInstallationStatus.modified);

        await installer.install(manifest, stage, game.path);
        verification = await verifier.verify(
          loadedManifest: loadedManifest,
          gameDirectory: game.path,
        );
        expect(
          verification.status,
          TranslationInstallationStatus.installedCurrent,
        );
        expect(verification.validFiles, hasLength(5));
      } finally {
        await sandbox.delete(recursive: true);
      }
    },
  );
}
