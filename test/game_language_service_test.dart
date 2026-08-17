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

  test(
    'prepares encrypted NTE with English launcher and French game text',
    () async {
      const languageEn = 'zUs1iPOD6DH9WVA/j/WFQGymGOWDheFjSanKLCRlfZ4=';
      const languageFr = 'Lm88wdHSFnR2x5z6Z1s5umymGOWDheFjSanKLCRlfZ4=';
      const localeEn = 'de0DvvQ7z4UvvV6EWBKSQAl+l+fR2Cyd408uYnmPbXw=';
      const localeFr = 'NeXLYGL6ZN14QCC1BFkXxgl+l+fR2Cyd408uYnmPbXw=';
      const audioEn = '7aOPkDZRDTgBvUg9h7cDdipgWQ+H4PlLLgY7u24Ds2s=';
      await ini.writeAsString(
        [
          'hgYm+rW2UfT0rvvTOSWS68+FUFKqAvf8xlSH/XFPSr0=',
          languageEn,
          localeEn,
          'TS6YLLzqMMV/QZlgo11R3Db+MAWx7QyjbmMpgf6+kFblbepFJkqnjlK9nhOxrb98',
          languageEn,
          audioEn,
          '',
        ].join('\r\n'),
      );

      final result = await service.ensureCulture('fr');
      expect(result.changed, isTrue);
      expect(result.receipt?.key, 'NteHybridCulture');
      expect(result.receipt?.previousValue, 'en');

      final current = await ini.readAsString();
      expect(RegExp(RegExp.escape(languageEn)).allMatches(current).length, 1);
      expect(RegExp(RegExp.escape(languageFr)).allMatches(current).length, 1);
      expect(RegExp(RegExp.escape(localeEn)).allMatches(current).length, 1);
      expect(current, isNot(contains(localeFr)));
      expect(current, contains(audioEn));

      final restored = await service.restore(result.receipt);
      expect(restored.restored, isTrue);
      final original = await ini.readAsString();
      expect(RegExp(RegExp.escape(languageEn)).allMatches(original).length, 2);
      expect(RegExp(RegExp.escape(localeEn)).allMatches(original).length, 1);
      expect(original, contains(audioEn));
    },
  );

  test('opening launcher repairs full French state back to hybrid', () async {
    const languageEn = 'zUs1iPOD6DH9WVA/j/WFQGymGOWDheFjSanKLCRlfZ4=';
    const languageFr = 'Lm88wdHSFnR2x5z6Z1s5umymGOWDheFjSanKLCRlfZ4=';
    const localeEn = 'de0DvvQ7z4UvvV6EWBKSQAl+l+fR2Cyd408uYnmPbXw=';
    const localeFr = 'NeXLYGL6ZN14QCC1BFkXxgl+l+fR2Cyd408uYnmPbXw=';

    await ini.writeAsString(
      '$languageEn\r\n$localeEn\r\n$languageEn\r\n',
    );
    final first = await service.ensureCulture('fr');

    await ini.writeAsString(
      '$languageFr\r\n$localeFr\r\n$languageFr\r\n',
    );
    final prepared = await service.ensureCulture(
      'fr',
      previous: first.receipt,
    );

    expect(prepared.changed, isTrue);
    expect(prepared.receipt?.previousValue, 'en');
    final current = await ini.readAsString();
    expect(RegExp(RegExp.escape(languageEn)).allMatches(current).length, 1);
    expect(RegExp(RegExp.escape(languageFr)).allMatches(current).length, 1);
    expect(RegExp(RegExp.escape(localeEn)).allMatches(current).length, 1);
    expect(current, isNot(contains(localeFr)));
  });

  test('hybrid restore accepts full French state written by the game', () async {
    const languageEn = 'zUs1iPOD6DH9WVA/j/WFQGymGOWDheFjSanKLCRlfZ4=';
    const localeEn = 'de0DvvQ7z4UvvV6EWBKSQAl+l+fR2Cyd408uYnmPbXw=';
    const languageFr = 'Lm88wdHSFnR2x5z6Z1s5umymGOWDheFjSanKLCRlfZ4=';
    const localeFr = 'NeXLYGL6ZN14QCC1BFkXxgl+l+fR2Cyd408uYnmPbXw=';

    await ini.writeAsString(
      '$languageEn\r\n$localeEn\r\n$languageEn\r\n',
    );
    final changed = await service.ensureCulture('fr');
    await ini.writeAsString(
      '$languageFr\r\n$localeFr\r\n$languageFr\r\n',
    );

    final restored = await service.restore(changed.receipt);
    expect(restored.restored, isTrue);
    final current = await ini.readAsString();
    expect(RegExp(RegExp.escape(languageEn)).allMatches(current).length, 2);
    expect(RegExp(RegExp.escape(localeEn)).allMatches(current).length, 1);
  });

  test('encrypted restore preserves a manual language change', () async {
    const languageEn = 'zUs1iPOD6DH9WVA/j/WFQGymGOWDheFjSanKLCRlfZ4=';
    const localeEn = 'de0DvvQ7z4UvvV6EWBKSQAl+l+fR2Cyd408uYnmPbXw=';
    const languageDe = 'kInAsIbW2RO39jtDoqxgRWymGOWDheFjSanKLCRlfZ4=';
    const localeDe = 'kAx51uJGW9PhnQsypySd8gl+l+fR2Cyd408uYnmPbXw=';

    await ini.writeAsString(
      '$languageEn\r\n$localeEn\r\n$languageEn\r\n',
    );
    final changed = await service.ensureCulture('fr');
    await ini.writeAsString(
      '$languageDe\r\n$localeDe\r\n$languageDe\r\n',
    );

    final restored = await service.restore(changed.receipt);
    expect(restored.restored, isFalse);
    expect(restored.preservedUserChoice, isTrue);
    final preserved = await ini.readAsString();
    expect(preserved, contains(languageDe));
    expect(preserved, contains(localeDe));
  });
}
