import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:nte_translation_launcher/services/receipt_repository.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:path/path.dart' as p;
import 'test_support.dart';

void main() {
  test(
    'content update preserves five owned files, rollback and original backup',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'nte-content-release-',
      );
      try {
        final game = await createGame(sandbox, 'game');
        final paths = AppPaths.forTesting(
          Directory(p.join(sandbox.path, 'app')),
        );
        final log = LauncherLog(paths.logFile);
        final receipts = ReceiptRepository(paths, log, SafePathService());
        final installer = InstallationService(paths, log, receipts: receipts);
        const names = [
          'UniversalSigBypasser.asi',
          'version.dll',
          'pakchunk999-Windows_999_P.pak',
          'pakchunk999-Windows_999_P.utoc',
          'pakchunk999-Windows_999_P.ucas',
        ];
        const oldTag = 'nte-auto-20260729-120100-0123456789ab';
        const newTag = 'nte-auto-20260729-121100-0123456789ab';
        final oldBytes = List.generate(5, (i) => [i + 10, i + 20]);
        final newBytes = List<List<int>>.from(oldBytes)..[2] = [99, 98, 97];
        TranslationManifest manifest(
          String tag,
          List<List<int>> bytes,
          bool reference,
        ) => TranslationManifest.fromJson({
          'schemaVersion': 1,
          'translationVersion': tag,
          'publishedAt': reference
              ? '2026-07-29T12:11:00Z'
              : '2026-07-29T12:01:00Z',
          'sourceHash': '0123456789ab${'c' * 52}',
          if (reference)
            'runtimeReference': {
              'version': 1,
              'tag': oldTag,
              'manifestSha256': 'a' * 64,
            },
          'files': [
            for (var i = 0; i < 5; i++)
              {
                'name': names[i],
                'relativeDestination':
                    'Client/WindowsNoEditor/HT/${i < 2 ? 'Binaries/Win64' : 'Content/Paks'}/${names[i]}',
                'url':
                    'https://github.com/MauricioIkeda/nte-ptbr-releases/releases/download/${reference && i != 2 ? oldTag : tag}/${names[i]}',
                'size': bytes[i].length,
                'sha256': hashOf(bytes[i]),
              },
          ],
        });
        final old = manifest(oldTag, oldBytes, false);
        final current = manifest(newTag, newBytes, true);
        final original = File(
          p.join(game.path, old.files[0].relativeDestination),
        );
        final pak = File(p.join(game.path, old.files[2].relativeDestination));
        await original.parent.create(recursive: true);
        await original.writeAsBytes([42]);
        await installer.install(
          old,
          await createStage(sandbox, old, oldBytes),
          game.path,
        );
        final stage = await createStage(sandbox, current, newBytes);
        final failing = InstallationService(
          paths,
          log,
          receipts: receipts,
          afterDestinationReplaced: (f) async {
            if (p.basename(f.path).toLowerCase() == names[2].toLowerCase()) {
              throw StateError('synthetic interruption');
            }
          },
        );
        await expectLater(
          failing.install(current, stage, game.path),
          throwsA(isA<InstallationException>()),
        );
        expect(await pak.readAsBytes(), oldBytes[2]);
        expect(
          (await receipts.read(game.path)).receipt!.translationVersion,
          oldTag,
        );
        await installer.install(current, stage, game.path);
        final receipt = (await receipts.read(game.path)).receipt!;
        expect(receipt.files, hasLength(5));
        expect(receipt.translationVersion, newTag);
        for (var i = 0; i < 5; i++) {
          expect(
            await File(
              p.join(game.path, current.files[i].relativeDestination),
            ).readAsBytes(),
            newBytes[i],
          );
        }
        expect((await installer.uninstall(game.path)).complete, isTrue);
        expect(await original.readAsBytes(), [42]);
        for (var i in [1, 2, 3, 4]) {
          expect(
            await File(
              p.join(game.path, current.files[i].relativeDestination),
            ).exists(),
            isFalse,
          );
        }
      } finally {
        await sandbox.delete(recursive: true);
      }
    },
  );
}
