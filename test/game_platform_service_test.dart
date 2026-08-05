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

  test('opens the official launcher manually by default', () async {
    final launcher = File(p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'));
    await launcher.create();
    String? receivedExecutable;
    String? receivedWorkingDirectory;
    var automationCalls = 0;
    final service = GamePlatformService(
      epicManifestDirectory: Directory(p.join(sandbox.path, 'epic-manifests')),
      steamRoots: const [],
      officialLauncherOpener: (executable, workingDirectory) async {
        receivedExecutable = executable;
        receivedWorkingDirectory = workingDirectory;
      },
      officialLauncherAutomation: (executable, workingDirectory) async {
        automationCalls++;
      },
    );
    final info = GamePlatformInfo(
      platform: GamePlatform.official,
      label: 'LAUNCHER OFICIAL',
      launchTarget: launcher.path,
    );

    await service.launch(info, gameDirectory.path);

    expect(receivedExecutable, launcher.path);
    expect(receivedWorkingDirectory, gameDirectory.path);
    expect(automationCalls, 0);
  });

  test('uses ready-state automation only when explicitly enabled', () async {
    final launcher = File(p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'));
    await launcher.create();
    String? receivedExecutable;
    String? receivedWorkingDirectory;
    final service = GamePlatformService(
      epicManifestDirectory: Directory(p.join(sandbox.path, 'epic-manifests')),
      steamRoots: const [],
      officialLauncherAutomation: (executable, workingDirectory) async {
        receivedExecutable = executable;
        receivedWorkingDirectory = workingDirectory;
      },
    );
    final info = GamePlatformInfo(
      platform: GamePlatform.official,
      label: 'LAUNCHER OFICIAL',
      launchTarget: launcher.path,
    );

    await service.launch(info, gameDirectory.path, automateOfficialPlay: true);

    expect(receivedExecutable, launcher.path);
    expect(receivedWorkingDirectory, gameDirectory.path);
  });

  test('starts the automation helper directly under Wine', () async {
    final launcher = File(p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'));
    final internal = File(
      p.join(gameDirectory.path, 'NTEGlobal', 'NTEGlobalGame.exe'),
    );
    await launcher.create();
    await internal.parent.create(recursive: true);
    await internal.create();
    final resultFile = File(p.join(sandbox.path, 'wine-result.json'));
    var directCalls = 0;
    var elevatedCalls = 0;
    late List<String> receivedArguments;
    final automation = OfficialLauncherAutomationService(
      wineRuntimeDetector: () => true,
      resultFile: resultFile,
      helperExecutable: r'C:\launcher\NTE-Launcher.exe',
      directHelperStarter: (executable, arguments, workingDirectory) async {
        directCalls++;
        receivedArguments = arguments;
        final attemptId = arguments
            .singleWhere((argument) => argument.startsWith('--automation-id='))
            .substring('--automation-id='.length);
        await resultFile.writeAsString(
          jsonEncode({
            'attemptId': attemptId,
            'exitCode': -1,
            'stage': 'started',
          }),
        );
      },
      elevatedHelperStarter: (environment) async {
        elevatedCalls++;
        return 0;
      },
    );

    await automation.launch(launcher.path, gameDirectory.path);

    expect(directCalls, 1);
    expect(elevatedCalls, 0);
    expect(receivedArguments, contains('--official-ready-play'));
    expect(
      receivedArguments,
      anyElement(startsWith('--official-launcher-hex=')),
    );
  });

  test('keeps elevation on native Windows and confirms the helper', () async {
    final launcher = File(p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'));
    final internal = File(
      p.join(gameDirectory.path, 'NTEGlobal', 'NTEGlobalGame.exe'),
    );
    await launcher.create();
    await internal.parent.create(recursive: true);
    await internal.create();
    final resultFile = File(p.join(sandbox.path, 'windows-result.json'));
    var directCalls = 0;
    var elevatedCalls = 0;
    final automation = OfficialLauncherAutomationService(
      wineRuntimeDetector: () => false,
      resultFile: resultFile,
      directHelperStarter: (executable, arguments, workingDirectory) async {
        directCalls++;
      },
      elevatedHelperStarter: (environment) async {
        elevatedCalls++;
        expect(environment['NTE_TRANSLATION_LAUNCHER'], isNotEmpty);
        await resultFile.writeAsString(
          jsonEncode({
            'attemptId': environment['NTE_AUTOMATION_ID'],
            'exitCode': -1,
            'stage': 'paths_validated',
          }),
        );
        return 0;
      },
    );

    await automation.launch(launcher.path, gameDirectory.path);

    expect(directCalls, 0);
    expect(elevatedCalls, 1);
  });

  test('does not report success when the helper never starts', () async {
    final launcher = File(p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'));
    final internal = File(
      p.join(gameDirectory.path, 'NTEGlobal', 'NTEGlobalGame.exe'),
    );
    await launcher.create();
    await internal.parent.create(recursive: true);
    await internal.create();
    final automation = OfficialLauncherAutomationService(
      wineRuntimeDetector: () => true,
      resultFile: File(p.join(sandbox.path, 'missing-result.json')),
      directHelperStarter: (executable, arguments, workingDirectory) async {},
      confirmationTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      automation.launch(launcher.path, gameDirectory.path),
      throwsA(
        isA<GamePlatformException>().having(
          (error) => error.message,
          'message',
          contains('não confirmou'),
        ),
      ),
    );
  });

  test('does not accept a result left by another automation attempt', () async {
    final launcher = File(p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'));
    final internal = File(
      p.join(gameDirectory.path, 'NTEGlobal', 'NTEGlobalGame.exe'),
    );
    await launcher.create();
    await internal.parent.create(recursive: true);
    await internal.create();
    final resultFile = File(p.join(sandbox.path, 'stale-result.json'));
    final automation = OfficialLauncherAutomationService(
      wineRuntimeDetector: () => true,
      resultFile: resultFile,
      directHelperStarter: (executable, arguments, workingDirectory) async {
        await resultFile.writeAsString(
          jsonEncode({
            'attemptId': 'different-attempt',
            'exitCode': -1,
            'stage': 'started',
          }),
        );
      },
      confirmationTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      automation.launch(launcher.path, gameDirectory.path),
      throwsA(isA<GamePlatformException>()),
    );
  });

  test('surfaces an immediate native helper failure', () async {
    final launcher = File(p.join(gameDirectory.path, 'NTEGlobalLauncher.exe'));
    final internal = File(
      p.join(gameDirectory.path, 'NTEGlobal', 'NTEGlobalGame.exe'),
    );
    await launcher.create();
    await internal.parent.create(recursive: true);
    await internal.create();
    final resultFile = File(p.join(sandbox.path, 'failure-result.json'));
    final automation = OfficialLauncherAutomationService(
      wineRuntimeDetector: () => true,
      resultFile: resultFile,
      directHelperStarter: (executable, arguments, workingDirectory) async {
        final attemptId = arguments
            .singleWhere((argument) => argument.startsWith('--automation-id='))
            .substring('--automation-id='.length);
        await resultFile.writeAsString(
          jsonEncode({
            'attemptId': attemptId,
            'exitCode': 11,
            'stage': 'official_launcher_start_failed',
          }),
        );
      },
    );

    await expectLater(
      automation.launch(launcher.path, gameDirectory.path),
      throwsA(
        isA<GamePlatformException>().having(
          (error) => error.message,
          'message',
          contains('launcher oficial não pôde ser iniciado'),
        ),
      ),
    );
  });
}
