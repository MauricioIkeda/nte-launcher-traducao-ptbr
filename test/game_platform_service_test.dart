import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/game_platform_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory gameDirectory;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-platform-test-');
    gameDirectory = Directory(p.join(sandbox.path, 'NTE'));
    await gameDirectory.create(recursive: true);
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('detects Epic and builds the current three-part launch URI', () async {
    final epicManifests = Directory(p.join(sandbox.path, 'epic-manifests'));
    await epicManifests.create();
    await File(p.join(epicManifests.path, 'nte.item')).writeAsString(
      jsonEncode({
        'InstallLocation': gameDirectory.path,
        'CatalogNamespace': 'nte-namespace',
        'CatalogItemId': 'catalog-id',
        'AppName': 'nte-artifact',
      }),
    );

    final service = GamePlatformService(
      epicManifestDirectory: epicManifests,
      steamRoots: const [],
    );
    final result = await service.detect(gameDirectory.path);

    expect(result.platform, GamePlatform.epicGames);
    expect(result.label, 'EPIC GAMES');
    expect(
      result.launchTarget,
      'com.epicgames.launcher://apps/'
      'nte-namespace%3Acatalog-id%3Ante-artifact'
      '?action=launch&silent=true',
    );
  });

  test('detects Steam through its local app manifest', () async {
    final emptyEpic = Directory(p.join(sandbox.path, 'epic-manifests'));
    await emptyEpic.create();
    final steamRoot = Directory(p.join(sandbox.path, 'Steam'));
    final steamApps = Directory(p.join(steamRoot.path, 'steamapps'));
    await Directory(p.join(steamApps.path, 'common')).create(recursive: true);
    final steamGame = Directory(
      p.join(steamApps.path, 'common', 'NevernessToEverness'),
    );
    await steamGame.create();
    await File(p.join(steamApps.path, 'appmanifest_123456.acf')).writeAsString(
      '''
"AppState"
{
  "appid" "123456"
  "name" "NTE: Neverness to Everness"
  "installdir" "NevernessToEverness"
}
''',
    );

    final service = GamePlatformService(
      epicManifestDirectory: emptyEpic,
      steamRoots: [steamRoot],
    );
    final result = await service.detect(steamGame.path);

    expect(result.platform, GamePlatform.steam);
    expect(result.label, 'STEAM');
    expect(result.launchTarget, 'steam://run/123456');
  });

  test('falls back to the official executable', () async {
    final emptyEpic = Directory(p.join(sandbox.path, 'epic-manifests'));
    await emptyEpic.create();
    final service = GamePlatformService(
      epicManifestDirectory: emptyEpic,
      steamRoots: const [],
    );

    final result = await service.detect(gameDirectory.path);

    expect(result.platform, GamePlatform.official);
    expect(result.label, 'LAUNCHER OFICIAL');
    expect(
      result.launchTarget,
      p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'),
    );
  });

  test('finds the official launcher inside NTEGlobal', () async {
    final emptyEpic = Directory(p.join(sandbox.path, 'epic-manifests'));
    await emptyEpic.create();
    final launcher = File(
      p.join(gameDirectory.path, 'NTEGlobal', 'NTEGlobalLauncher.exe'),
    );
    await launcher.parent.create(recursive: true);
    await launcher.create();
    final service = GamePlatformService(
      epicManifestDirectory: emptyEpic,
      steamRoots: const [],
    );

    final result = await service.detect(gameDirectory.path);

    expect(result.platform, GamePlatform.official);
    expect(result.launchTarget, launcher.path);
  });

  test('passes store protocols to the operating system URL handler', () async {
    final emptyEpic = Directory(p.join(sandbox.path, 'epic-manifests'));
    await emptyEpic.create();
    Uri? receivedUri;
    final service = GamePlatformService(
      epicManifestDirectory: emptyEpic,
      steamRoots: const [],
      externalUriLauncher: (uri) async {
        receivedUri = uri;
        return true;
      },
    );
    const info = GamePlatformInfo(
      platform: GamePlatform.epicGames,
      label: 'EPIC GAMES',
      launchTarget:
          'com.epicgames.launcher://apps/'
          'namespace%3Acatalog%3Aartifact?action=launch&silent=true',
    );

    await service.launch(info, gameDirectory.path);

    expect(receivedUri, Uri.parse(info.launchTarget));
  });

  test('ignores autoplay and opens the official launcher normally', () async {
    final launcher = File(p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'));
    await launcher.create();
    String? receivedExecutable;
    List<String>? receivedArguments;
    String? receivedWorkingDirectory;
    final service = GamePlatformService(
      epicManifestDirectory: Directory(p.join(sandbox.path, 'epic-manifests')),
      steamRoots: const [],
      gameExecutableLauncher: (executable, arguments, workingDirectory) async {
        receivedExecutable = executable;
        receivedArguments = arguments;
        receivedWorkingDirectory = workingDirectory;
      },
    );
    final info = GamePlatformInfo(
      platform: GamePlatform.official,
      label: 'LAUNCHER OFICIAL',
      launchTarget: launcher.path,
    );

    await service.launch(info, gameDirectory.path, officialAutoplay: true);

    expect(receivedExecutable, launcher.path);
    expect(receivedArguments, isEmpty);
    expect(receivedWorkingDirectory, gameDirectory.path);
  });

  test('opens the official launcher without autoplay when disabled', () async {
    final launcher = File(p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'));
    await launcher.create();
    List<String>? receivedArguments;
    final service = GamePlatformService(
      epicManifestDirectory: Directory(p.join(sandbox.path, 'epic-manifests')),
      steamRoots: const [],
      gameExecutableLauncher: (executable, arguments, workingDirectory) async {
        receivedArguments = arguments;
      },
    );
    final info = GamePlatformInfo(
      platform: GamePlatform.official,
      label: 'LAUNCHER OFICIAL',
      launchTarget: launcher.path,
    );

    await service.launch(info, gameDirectory.path, officialAutoplay: false);

    expect(receivedArguments, isEmpty);
  });
}
