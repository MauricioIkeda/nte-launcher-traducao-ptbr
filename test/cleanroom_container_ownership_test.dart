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
  late Directory sandbox;
  late Directory game;
  late ReceiptRepository receipts;
  late InstallationService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-cleanroom-containers-');
    game = await createGame(sandbox, 'game');
    final paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    final log = LauncherLog(paths.logFile);
    final safePaths = SafePathService();
    receipts = ReceiptRepository(paths, log, safePaths);
    service = InstallationService(
      paths,
      log,
      safePaths: safePaths,
      receipts: receipts,
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('refuses an unmanaged native container before writing a receipt', () async {
    const nativeBytes = [9, 7, 5, 3, 1];
    const translatedBytes = [1, 2, 3];
    final manifest = _manifest('pakchunk999-Windows_999_P.pak', translatedBytes);
    final stage = await createStage(sandbox, manifest, const [translatedBytes]);
    final destination = _destination(game, manifest);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(nativeBytes, flush: true);

    await expectLater(
      service.install(manifest, stage, game.path),
      throwsA(isA<InstallationException>()),
    );

    expect(await destination.readAsBytes(), nativeBytes);
    expect((await receipts.read(game.path)).receipt, isNull);
  });

  test('installs a container into a path that did not exist', () async {
    const translatedBytes = [1, 2, 3];
    final manifest = _manifest(
      'pakchunk9001-Windows_NTEPTBR_P.pak',
      translatedBytes,
    );
    final stage = await createStage(sandbox, manifest, const [translatedBytes]);

    await service.install(manifest, stage, game.path);

    expect(await _destination(game, manifest).readAsBytes(), translatedBytes);
    final receipt = (await receipts.read(game.path)).receipt;
    expect(receipt, isNotNull);
    expect(receipt!.files.single.originalExisted, isFalse);
  });

  test('allows reinstall while translation-owned bytes are still intact', () async {
    const translatedBytes = [4, 5, 6, 7];
    final manifest = _manifest('pakchunk999-Windows_999_P.utoc', translatedBytes);
    final stage = await createStage(sandbox, manifest, const [translatedBytes]);

    await service.install(manifest, stage, game.path);
    await service.install(manifest, stage, game.path);

    expect(await _destination(game, manifest).readAsBytes(), translatedBytes);
  });

  test('allows reinstall when a translation-owned container was removed', () async {
    const translatedBytes = [8, 8, 2];
    final manifest = _manifest('pakchunk999-Windows_999_P.ucas', translatedBytes);
    final stage = await createStage(sandbox, manifest, const [translatedBytes]);

    await service.install(manifest, stage, game.path);
    final destination = _destination(game, manifest);
    await destination.delete();

    await service.install(manifest, stage, game.path);

    expect(await destination.readAsBytes(), translatedBytes);
  });

  test('refuses a path taken over by an NTE update after installation', () async {
    const translatedBytes = [1, 3, 3, 7];
    const nativeAfterUpdate = [4, 2, 4, 2, 9, 9];
    final manifest = _manifest('pakchunk999-Windows_999_P.pak', translatedBytes);
    final stage = await createStage(sandbox, manifest, const [translatedBytes]);

    await service.install(manifest, stage, game.path);
    final destination = _destination(game, manifest);
    await destination.writeAsBytes(nativeAfterUpdate, flush: true);

    await expectLater(
      service.install(manifest, stage, game.path),
      throwsA(isA<InstallationException>()),
    );

    expect(await destination.readAsBytes(), nativeAfterUpdate);
    final receipt = (await receipts.read(game.path)).receipt;
    expect(receipt, isNotNull);
    expect(receipt!.files.single.originalExisted, isFalse);
  });

  test('refuses reinstall over a container that existed before first install', () async {
    const nativeBytes = [0, 1, 0, 1];
    const translatedBytes = [7, 7, 7];
    final manifest = _manifest('pakchunk999-Windows_999_P.pak', translatedBytes);
    final stage = await createStage(sandbox, manifest, const [translatedBytes]);
    final destination = _destination(game, manifest);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(nativeBytes, flush: true);

    // O clean-room guard deve bloquear já na primeira tentativa. Este caso
    // também garante que nunca criamos um receipt que legitime a colisão.
    await expectLater(
      service.install(manifest, stage, game.path),
      throwsA(isA<InstallationException>()),
    );
    expect((await receipts.read(game.path)).receipt, isNull);
    expect(await destination.readAsBytes(), nativeBytes);
  });
}

File _destination(Directory game, TranslationManifest manifest) => File(
  p.join(game.path, manifest.files.single.relativeDestination),
);

TranslationManifest _manifest(String name, List<int> bytes) {
  const version = 'nte-auto-cleanroom-20260818';
  return TranslationManifest.fromJson({
    'schemaVersion': 1,
    'translationVersion': version,
    'publishedAt': DateTime.utc(2026, 8, 18).toIso8601String(),
    'files': [
      {
        'name': name,
        'relativeDestination': 'Client/WindowsNoEditor/HT/Content/Paks/$name',
        'url': 'https://github.com/example/releases/download/$version/$name',
        'size': bytes.length,
        'sha256': hashOf(bytes),
      },
    ],
  });
}