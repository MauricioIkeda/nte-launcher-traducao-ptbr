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
}

TranslationManifest _containerManifest(String name, List<int> contents) {
  const version = 'nte-auto-20260804-container-test';
  return TranslationManifest.fromJson({
    'schemaVersion': 1,
    'translationVersion': version,
    'publishedAt': DateTime.utc(2026, 8, 4).toIso8601String(),
    'files': [
      {
        'name': name,
        'relativeDestination':
            'Client/WindowsNoEditor/HT/Content/Paks/$name',
        'url': 'https://github.com/example/releases/download/$version/$name',
        'size': contents.length,
        'sha256': hashOf(contents),
      },
    ],
  });
}
