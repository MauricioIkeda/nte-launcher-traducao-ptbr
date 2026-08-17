import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/game_language_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Epic config is prepared as EN launcher + FR game and can restore', () async {
    final sandbox = await Directory.systemTemp.createTemp('nte-language-epic-');
    try {
      final config = Directory(
        p.join(
          sandbox.path,
          'HT',
          'Saved_GlobalEpic',
          'Config',
          'Windows',
        ),
      );
      await config.create(recursive: true);
      final ini = File(p.join(config.path, 'GameUserSettings.ini'));
      final service = GameLanguageService(localAppData: sandbox.path);

      const languageEn = 'zUs1iPOD6DH9WVA/j/WFQGymGOWDheFjSanKLCRlfZ4=';
      const languageFr = 'Lm88wdHSFnR2x5z6Z1s5umymGOWDheFjSanKLCRlfZ4=';
      const localeEn = 'de0DvvQ7z4UvvV6EWBKSQAl+l+fR2Cyd408uYnmPbXw=';
      const localeFr = 'NeXLYGL6ZN14QCC1BFkXxgl+l+fR2Cyd408uYnmPbXw=';
      const audioEn = '7aOPkDZRDTgBvUg9h7cDdipgWQ+H4PlLLgY7u24Ds2s=';

      await ini.writeAsString(
        [languageEn, localeEn, languageEn, audioEn, ''].join('\r\n'),
      );

      final prepared = await service.ensureCulture('fr');
      expect(prepared.changed, isTrue);
      expect(prepared.receipt?.key, 'NteHybridCulture');
      expect(
        p.normalize(prepared.receipt!.configPath),
        p.normalize(ini.path),
      );

      final current = await ini.readAsString();
      expect(RegExp(RegExp.escape(languageEn)).allMatches(current).length, 1);
      expect(RegExp(RegExp.escape(languageFr)).allMatches(current).length, 1);
      expect(RegExp(RegExp.escape(localeEn)).allMatches(current).length, 1);
      expect(current, isNot(contains(localeFr)));
      expect(current, contains(audioEn));

      final restored = await service.restore(prepared.receipt);
      expect(restored.restored, isTrue);
      final original = await ini.readAsString();
      expect(RegExp(RegExp.escape(languageEn)).allMatches(original).length, 2);
      expect(RegExp(RegExp.escape(localeEn)).allMatches(original).length, 1);
      expect(original, contains(audioEn));
    } finally {
      await sandbox.delete(recursive: true);
    }
  });
}
