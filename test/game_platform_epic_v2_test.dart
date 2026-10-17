import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/game_platform_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory game;
  late File journal;
  late GamePlatformService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-epic-v2-');
    game = await Directory(p.join(sandbox.path, 'chosen-game')).create();
    journal = File(p.join(sandbox.path, 'installations.jsonl'));
    service = GamePlatformService(
      epicInstallationsFile: journal,
      epicManifestDirectory: Directory(p.join(sandbox.path, 'missing-legacy')),
      steamRoots: const [],
    );
  });
  tearDown(() => sandbox.delete(recursive: true));

  Map<String, dynamic> record({String id = 'install-1', String? dir}) => {
    'installationId': id,
    'complete': true,
    'dir': dir ?? game.path,
    'platform': 'Windows',
    'namespace': 'synthetic-namespace',
    'itemId': 'synthetic-item',
    'artifactId': 'synthetic-artifact',
    'version': '1.2.3',
  };

  Future<void> write(List<Map<String, dynamic>> records, {int version = 1}) =>
      journal.writeAsString(
        [
          jsonEncode({'version': version, 'entries': records.length}),
          ...records.map(jsonEncode),
        ].join('\n'),
      );

  test(
    'detects v2 without ProgramData and builds the three-part URI',
    () async {
      await write([
        record(id: 'other', dir: p.join(sandbox.path, 'other')),
        record()..['complete'] = false,
        record(),
      ]);
      final result = await service.detect(game.path);
      expect(result.platform, GamePlatform.epicGames);
      expect(result.evidence['method'], 'epic_v2_installations_journal');
      expect(result.evidence['manifestPath'], journal.path);
      expect(
        result.launchTarget,
        'com.epicgames.launcher://apps/'
        'synthetic-namespace%3Asynthetic-item%3Asynthetic-artifact'
        '?action=launch&silent=true',
      );
    },
  );

  test('last record wins when an installation moved', () async {
    await write([record(), record(dir: p.join(sandbox.path, 'moved'))]);
    expect((await service.detect(game.path)).platform, GamePlatform.official);
  });

  test(
    'initial incomplete download cannot resurrect an older completion',
    () async {
      await write([
        record(),
        record()
          ..['complete'] = false
          ..remove('version'),
      ]);
      await expectLater(
        service.detect(game.path),
        throwsA(isA<GamePlatformException>()),
      );
    },
  );

  test(
    'update in progress retains the installed version and store route',
    () async {
      await write([
        record()
          ..['complete'] = false
          ..['pendingVersion'] = '1.2.4',
      ]);
      expect(
        (await service.detect(game.path)).platform,
        GamePlatform.epicGames,
      );
    },
  );

  for (final field in ['namespace', 'itemId', 'artifactId']) {
    test(
      'rejects missing or unsafe $field instead of launching official',
      () async {
        for (final value in ['', 'bad?argument=true']) {
          await write([record()..[field] = value]);
          await expectLater(
            service.detect(game.path),
            throwsA(isA<GamePlatformException>()),
          );
        }
      },
    );
  }

  test(
    'does not infer Epic from a parent path, game name or egstore alone',
    () async {
      await Directory(p.join(game.path, '.egstore')).create();
      await write([record(dir: sandbox.path)]);
      expect((await service.detect(game.path)).platform, GamePlatform.official);
    },
  );

  test('does not adopt an entry for another operating system', () async {
    await write([record()..['platform'] = 'Mac']);
    expect((await service.detect(game.path)).platform, GamePlatform.official);
  });

  test(
    'rejects unknown schema and torn journals without using stale lines',
    () async {
      await write([record()], version: 2);
      expect((await service.detect(game.path)).platform, GamePlatform.official);
      await write([record()]);
      await journal.writeAsString(
        '\n{"installationId":',
        mode: FileMode.append,
      );
      expect((await service.detect(game.path)).platform, GamePlatform.official);
      await journal.writeAsString('[]\n');
      expect((await service.detect(game.path)).platform, GamePlatform.official);
    },
  );

  test('legacy item detection remains available when v2 is absent', () async {
    final legacy = await Directory(p.join(sandbox.path, 'legacy')).create();
    await File(p.join(legacy.path, 'game.item')).writeAsString(
      jsonEncode({
        'InstallLocation': game.path,
        'CatalogNamespace': 'legacy-namespace',
        'CatalogItemId': 'legacy-item',
        'AppName': 'legacy-artifact',
      }),
    );
    final legacyService = GamePlatformService(
      epicInstallationsFile: journal,
      epicManifestDirectory: legacy,
      steamRoots: const [],
    );
    final result = await legacyService.detect(game.path);
    expect(result.platform, GamePlatform.epicGames);
    expect(result.evidence['method'], 'epic_item_manifest');
  });
}
