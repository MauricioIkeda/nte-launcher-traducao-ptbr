import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/game_language_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory config;
  late File ini;
  late GameLanguageService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-language-');
    config = Directory(
      p.join(sandbox.path, 'HT', 'Saved_Global', 'Config', 'Windows'),
    );
    await config.create(recursive: true);
    ini = File(p.join(config.path, 'GameUserSettings.ini'));
    service = GameLanguageService(localAppData: sandbox.path);
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('switches text language without changing voice language', () async {
    await ini.writeAsString(
      '[User]\r\nTextLanguage=en\r\nVoiceLanguage=ja\r\n',
    );
    final result = await service.ensureCulture('fr');
    expect(result.changed, isTrue);
    expect(result.receipt?.previousValue, 'en');
    final current = await ini.readAsString();
    expect(current, contains('TextLanguage=fr'));
    expect(current, contains('VoiceLanguage=ja'));
  });

  test('restore changes only language and preserves later settings', () async {
    await ini.writeAsString('[User]\nTextLanguage=en\nQuality=2\n');
    final changed = await service.ensureCulture('fr');
    await ini.writeAsString(
      (await ini.readAsString()).replaceAll('Quality=2', 'Quality=4'),
    );
    final restored = await service.restore(changed.receipt);
    expect(restored.restored, isTrue);
    final current = await ini.readAsString();
    expect(current, contains('TextLanguage=en'));
    expect(current, contains('Quality=4'));
  });

  test('restore respects manual language change after install', () async {
    await ini.writeAsString('[User]\nTextLanguage=en\n');
    final changed = await service.ensureCulture('fr');
    await ini.writeAsString('[User]\nTextLanguage=de\n');
    final restored = await service.restore(changed.receipt);
    expect(restored.restored, isFalse);
    expect(restored.preservedUserChoice, isTrue);
    expect(await ini.readAsString(), contains('TextLanguage=de'));
  });

  test('voice-only config is never selected', () async {
    await ini.writeAsString('[User]\nVoiceLanguage=ja\n');
    final result = await service.ensureCulture('fr');
    expect(result.changed, isFalse);
    expect(result.receipt, isNull);
    expect(await ini.readAsString(), contains('VoiceLanguage=ja'));
  });

  test('ambiguous equal-priority text settings are not changed', () async {
    final second = Directory(
      p.join(sandbox.path, 'HT', 'Saved', 'Config', 'Windows'),
    );
    await second.create(recursive: true);
    await ini.writeAsString('[User]\nTextLanguage=en\n');
    await File(
      p.join(second.path, 'GameUserSettings.ini'),
    ).writeAsString('[User]\nTextLanguage=en\n');
    final result = await service.ensureCulture('fr');
    expect(result.changed, isFalse);
    expect(result.receipt, isNull);
    expect(await ini.readAsString(), contains('TextLanguage=en'));
  });

  test('reinstall preserves the original language baseline', () async {
    await ini.writeAsString('[User]\nTextLanguage=en\n');
    final first = await service.ensureCulture('fr');
    final second = await service.ensureCulture('fr', previous: first.receipt);
    expect(second.changed, isFalse);
    expect(second.receipt?.previousValue, 'en');
    final restored = await service.restore(second.receipt);
    expect(restored.restored, isTrue);
    expect(await ini.readAsString(), contains('TextLanguage=en'));
  });

  test('preserves UTF-8 BOM state', () async {
    await ini.writeAsBytes([
      0xef,
      0xbb,
      0xbf,
      ...'[User]\nTextLanguage=en\n'.codeUnits,
    ]);
    final changed = await service.ensureCulture('fr');
    expect(changed.changed, isTrue);
    final bytes = await ini.readAsBytes();
    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
  });
}
