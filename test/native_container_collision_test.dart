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
  late AppPaths paths;
  late ReceiptRepository receipts;
  late InstallationService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-native-collision-');
    game = await createGame(sandbox, 'game');
    paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
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

  tearDown(() => sandbox.delete(recursive: true));

  test('blocks replacing an unmanaged native pak container', () async {
    const translated = [1, 2, 3];
    const original = [9, 8, 7, 6];
    final manifest = _containerManifest(
      'pakchunk999-Windows_999_P.pak',
      translated,
    );
    final stage = await createStage(sandbox, manifest, const [translated]);
    final destination = File(
      p.join(game.path, manifest.files.single.relativeDestination),
    );
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(original);

    await expectLater(
      service.install(manifest, stage, game.path),
      throwsA(
        isA<InstallationException>().having(
          (error) => error.message,
          'message',
          contains('proteger arquivos originais do jogo'),
        ),
      ),
    );

    expect(await destination.readAsBytes(), original);
    expect((await receipts.read(game.path)).receipt, isNull);
  });

  for (final extension in const ['pak', 'utoc', 'ucas']) {
    test(
      'blocks a managed $extension container replaced later by a game update',
      () async {
        const translated = [1, 2, 3];
        const nativeAfterUpdate = [9, 9, 8, 8, 7, 7];
        final manifest = _containerManifest(
          'pakchunk999-Windows_999_P.$extension',
          translated,
        );
        final stage = await createStage(sandbox, manifest, const [translated]);

        await service.install(manifest, stage, game.path);
        final destination = File(
          p.join(game.path, manifest.files.single.relativeDestination),
        );
        expect(await destination.readAsBytes(), translated);

        // Simula uma atualização do NTE escrevendo um container nativo no
        // mesmo caminho que antes pertencia somente à tradução.
        await destination.writeAsBytes(nativeAfterUpdate, flush: true);

        await expectLater(
          service.install(manifest, stage, game.path),
          throwsA(
            isA<InstallationException>().having(
              (error) => error.message,
              'message',
              contains('proteger arquivos originais do jogo'),
            ),
          ),
        );

        expect(await destination.readAsBytes(), nativeAfterUpdate);
        final receipt = (await receipts.read(game.path)).receipt;
        expect(receipt, isNotNull);
        expect(receipt!.files.single.originalExisted, isFalse);
      },
    );
  }

  test('allows a new translation-owned pak container', () async {
    const translated = [1, 2, 3];
    final manifest = _containerManifest(
      'pakchunk9999-Windows_NTEPTBR_P.pak',
      translated,
    );
    final stage = await createStage(sandbox, manifest, const [translated]);

    await service.install(manifest, stage, game.path);

    final destination = File(
      p.join(game.path, manifest.files.single.relativeDestination),
    );
    expect(await destination.readAsBytes(), translated);
    expect((await receipts.read(game.path)).receipt, isNotNull);
  });

  test('does not block a pak outside the NTE Paks directory', () async {
    const translated = [1, 2, 3];
    const original = [7, 7, 7, 7];
    const relative = 'Client/WindowsNoEditor/HT/Content/Other/example.pak';
    final manifest = _manifestForDestination(
      'example.pak',
      relative,
      translated,
    );
    final stage = await createStage(sandbox, manifest, const [translated]);
    final destination = File(p.join(game.path, relative));
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(original);

    await service.install(manifest, stage, game.path);

    expect(await destination.readAsBytes(), translated);
    final receipt = (await receipts.read(game.path)).receipt;
    expect(receipt, isNotNull);
    expect(receipt!.files.single.originalExisted, isTrue);
  });

  test('does not block a non-container file inside Paks', () async {
    const translated = [1, 2, 3];
    const original = [4, 2];
    const relative = 'Client/WindowsNoEditor/HT/Content/Paks/readme.txt';
    final manifest = _manifestForDestination(
      'readme.txt',
      relative,
      translated,
    );
    final stage = await createStage(sandbox, manifest, const [translated]);
    final destination = File(p.join(game.path, relative));
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(original);

    await service.install(manifest, stage, game.path);

    expect(await destination.readAsBytes(), translated);
    final receipt = (await receipts.read(game.path)).receipt;
    expect(receipt, isNotNull);
    expect(receipt!.files.single.originalExisted, isTrue);
  });
}

TranslationManifest _containerManifest(String name, List<int> contents) {
  return _manifestForDestination(
    name,
    'Client/WindowsNoEditor/HT/Content/Paks/$name',
    contents,
  );
}

TranslationManifest _manifestForDestination(
  String name,
  String relativeDestination,
  List<int> contents,
) {
  const version = 'nte-auto-20260818-container-test';
  return TranslationManifest.fromJson({
    'schemaVersion': 1,
    'translationVersion': version,
    'publishedAt': DateTime.utc(2026, 8, 18).toIso8601String(),
    'files': [
      {
        'name': name,
        'relativeDestination': relativeDestination,
        'url': 'https://github.com/example/releases/download/$version/$name',
        'size': contents.length,
        'sha256': hashOf(contents),
      },
    ],
  });
}
