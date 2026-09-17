import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/settings_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late File preferencesFile;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-settings-test-');
    preferencesFile = File(p.join(sandbox.path, 'shared_preferences.json'));
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  SettingsService service() => SettingsService(
    preferencesFile: preferencesFile,
    now: () => DateTime.utc(2026, 9, 17, 1, 2, 3),
  );

  test('reads the legacy shared_preferences JSON without migration', () async {
    await preferencesFile.writeAsString(
      jsonEncode({
        'game_directory': r'D:\Games\Neverness to Everness',
        'installed_version': 'nte-auto-test',
        'official_launch_automation_v2': true,
        'unknown_key': 7,
      }),
    );

    final settings = service();

    expect(
      await settings.getGameDirectory(),
      r'D:\Games\Neverness to Everness',
    );
    expect(await settings.getInstalledVersion(), 'nte-auto-test');
    expect(await settings.getOfficialLaunchAutomation(), isTrue);

    await settings.setAutomaticLauncherUpdates(true);
    final persisted =
        jsonDecode(await preferencesFile.readAsString()) as Map<String, dynamic>;
    expect(persisted['automatic_launcher_updates'], isTrue);
    expect(persisted['unknown_key'], 7);
  });

  test('quarantines corrupt preferences and starts with safe defaults', () async {
    await preferencesFile.writeAsBytes(List<int>.filled(32, 0), flush: true);
    final settings = service();

    expect(await settings.getGameDirectory(), isNull);
    expect(await settings.getAutomaticLauncherUpdates(), isFalse);

    final quarantined = sandbox
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).startsWith(
          'shared_preferences.corrupt-',
        ))
        .toList();
    expect(quarantined, hasLength(1));

    await settings.setGameDirectory(r'D:\Recovered\NTE');
    final persisted =
        jsonDecode(await preferencesFile.readAsString()) as Map<String, dynamic>;
    expect(persisted['game_directory'], r'D:\Recovered\NTE');
  });

  test('restores the backup left by an interrupted atomic write', () async {
    final backup = File('${preferencesFile.path}.bak');
    await backup.writeAsString(
      jsonEncode({'game_directory': r'E:\SteamLibrary\NTE'}),
    );

    final settings = service();

    expect(await settings.getGameDirectory(), r'E:\SteamLibrary\NTE');
    expect(await preferencesFile.exists(), isTrue);
    expect(await backup.exists(), isFalse);
  });

  test('uses a valid backup when the primary preferences are corrupt', () async {
    await preferencesFile.writeAsString('{broken-json');
    final backup = File('${preferencesFile.path}.bak');
    await backup.writeAsString(
      jsonEncode({'installed_version': 'nte-auto-recovered'}),
    );

    final settings = service();

    expect(await settings.getInstalledVersion(), 'nte-auto-recovered');
    expect(await backup.exists(), isFalse);
    final persisted =
        jsonDecode(await preferencesFile.readAsString()) as Map<String, dynamic>;
    expect(persisted['installed_version'], 'nte-auto-recovered');
  });

  test('serializes concurrent mutations without losing settings', () async {
    final settings = service();

    await Future.wait([
      settings.setGameDirectory(r'F:\Steam\NTE'),
      settings.setAutomaticLauncherUpdates(true),
      settings.setOfficialLaunchAutomation(true),
    ]);

    final persisted =
        jsonDecode(await preferencesFile.readAsString()) as Map<String, dynamic>;
    expect(persisted['game_directory'], r'F:\Steam\NTE');
    expect(persisted['automatic_launcher_updates'], isTrue);
    expect(persisted['official_launch_automation_v2'], isTrue);
  });
}
