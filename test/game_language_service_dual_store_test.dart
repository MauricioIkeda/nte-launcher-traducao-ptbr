import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/game_language_service.dart';
import 'package:path/path.dart' as p;

const _languageEn = 'zUs1iPOD6DH9WVA/j/WFQGymGOWDheFjSanKLCRlfZ4=';
const _languageFr = 'Lm88wdHSFnR2x5z6Z1s5umymGOWDheFjSanKLCRlfZ4=';
const _localeEn = 'de0DvvQ7z4UvvV6EWBKSQAl+l+fR2Cyd408uYnmPbXw=';

Future<({Directory root, File settings})> _writeProfile(
  Directory sandbox,
  String name,
) async {
  final root = Directory(p.join(sandbox.path, 'HT', name));
  final settings = File(
    p.join(root.path, 'Config', 'Windows', 'GameUserSettings.ini'),
  );
  await settings.parent.create(recursive: true);
  await settings.writeAsString(
    '$_languageEn\r\n$_localeEn\r\n$_languageEn\r\n',
  );
  return (root: root, settings: settings);
}

Future<Directory> _writeGameDirectory(
  Directory sandbox,
  String name,
  Directory dataPath,
) async {
  final game = Directory(p.join(sandbox.path, name));
  final config = File(
    p.join(game.path, 'NTEGlobal', 'UserData', 'Config', 'Config.ini'),
  );
  await config.parent.create(recursive: true);
  await config.writeAsString('[Game]\ndataPath=${dataPath.path}\n');
  return game;
}

void main() {
  late Directory sandbox;
  late GameLanguageService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-dual-language-');
    service = GameLanguageService(localAppData: sandbox.path);
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('targets Steam dataPath when Epic and Steam profiles coexist', () async {
    final epic = await _writeProfile(sandbox, 'Saved_GlobalEpic');
    final steam = await _writeProfile(sandbox, 'Saved_GlobalSteam');
    final game = await _writeGameDirectory(sandbox, 'SteamGame', steam.root);

    final result = await service.ensureCulture(
      'fr',
      gameDirectory: game.path,
    );

    expect(result.changed, isTrue);
    expect(
      p.normalize(result.receipt!.configPath),
      p.normalize(steam.settings.path),
    );
    expect(
      await steam.settings.readAsString(),
      '$_languageEn\r\n$_localeEn\r\n$_languageFr\r\n',
    );
    expect(
      await epic.settings.readAsString(),
      '$_languageEn\r\n$_localeEn\r\n$_languageEn\r\n',
    );
  });

  test('targets Epic dataPath when Steam profile also exists', () async {
    final epic = await _writeProfile(sandbox, 'Saved_GlobalEpic');
    final steam = await _writeProfile(sandbox, 'Saved_GlobalSteam');
    final game = await _writeGameDirectory(sandbox, 'EpicGame', epic.root);

    final result = await service.ensureCulture(
      'fr',
      gameDirectory: game.path,
    );

    expect(result.changed, isTrue);
    expect(
      p.normalize(result.receipt!.configPath),
      p.normalize(epic.settings.path),
    );
    expect(
      await epic.settings.readAsString(),
      '$_languageEn\r\n$_localeEn\r\n$_languageFr\r\n',
    );
    expect(
      await steam.settings.readAsString(),
      '$_languageEn\r\n$_localeEn\r\n$_languageEn\r\n',
    );
  });

  test('legacy scan stays conservative without an installation hint', () async {
    final epic = await _writeProfile(sandbox, 'Saved_GlobalEpic');
    final steam = await _writeProfile(sandbox, 'Saved_GlobalSteam');

    final result = await service.ensureCulture('fr');

    expect(result.changed, isFalse);
    expect(result.receipt, isNull);
    expect(
      await epic.settings.readAsString(),
      '$_languageEn\r\n$_localeEn\r\n$_languageEn\r\n',
    );
    expect(
      await steam.settings.readAsString(),
      '$_languageEn\r\n$_localeEn\r\n$_languageEn\r\n',
    );
  });
}
