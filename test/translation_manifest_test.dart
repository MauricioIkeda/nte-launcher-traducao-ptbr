import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';

const validHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('accepts a valid manifest', () {
    final manifest = TranslationManifest.fromJson({
      'schemaVersion': 1,
      'translationVersion': '1.0.0',
      'publishedAt': '2026-07-27T00:00:00Z',
      'files': [
        {
          'name': 'translation.pak',
          'relativeDestination': 'Client/Content/Paks/translation.pak',
          'url': 'https://example.com/translation.pak',
          'size': 42,
          'sha256': validHash,
        },
      ],
    });

    expect(manifest.translationVersion, '1.0.0');
    expect(manifest.totalBytes, 42);
  });

  test('rejects path traversal', () {
    expect(
      () => TranslationManifest.fromJson({
        'schemaVersion': 1,
        'translationVersion': '1.0.0',
        'publishedAt': '2026-07-27T00:00:00Z',
        'files': [
          {
            'name': 'malicious.dll',
            'relativeDestination': '../malicious.dll',
            'url': 'https://example.com/malicious.dll',
            'size': 42,
            'sha256': validHash,
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('rejects non-HTTPS downloads', () {
    expect(
      () => TranslationManifest.fromJson({
        'schemaVersion': 1,
        'translationVersion': '1.0.0',
        'publishedAt': '2026-07-27T00:00:00Z',
        'files': [
          {
            'name': 'translation.pak',
            'relativeDestination': 'Client/Content/Paks/translation.pak',
            'url': 'http://example.com/translation.pak',
            'size': 42,
            'sha256': validHash,
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('accepts optional future game-build metadata', () {
    final manifest = TranslationManifest.fromJson({
      'schemaVersion': 1,
      'translationVersion': '1.0.0',
      'publishedAt': '2026-07-27T00:00:00Z',
      'gameBuildId': 'nte-build-42',
      'sourceHash': validHash,
      'files': [
        {
          'name': 'translation.pak',
          'relativeDestination': 'Client/Content/Paks/translation.pak',
          'url': 'https://example.com/translation.pak',
          'size': 42,
          'sha256': validHash,
        },
      ],
    });
    expect(manifest.gameBuildId, 'nte-build-42');
    expect(manifest.sourceHash, validHash);
  });

  test('rejects unsafe or oversized game-build metadata', () {
    for (final gameBuildId in [
      'build\nunsafe',
      ' spaced ',
      List.filled(201, 'x').join(),
      42,
    ]) {
      expect(
        () => TranslationManifest.fromJson({
          'schemaVersion': 1,
          'translationVersion': '1.0.0',
          'publishedAt': '2026-07-27T00:00:00.123Z',
          'gameBuildId': gameBuildId,
          'files': [
            {
              'name': 'translation.pak',
              'relativeDestination': 'Client/Content/Paks/translation.pak',
              'url': 'https://example.com/translation.pak',
              'size': 42,
              'sha256': validHash,
            },
          ],
        }),
        throwsFormatException,
      );
    }
  });

  test('requires a UTC Z publication date and accepts fractions', () {
    Map<String, dynamic> manifestWithDate(String publishedAt) => {
      'schemaVersion': 1,
      'translationVersion': '1.0.0',
      'publishedAt': publishedAt,
      'files': [
        {
          'name': 'translation.pak',
          'relativeDestination': 'Client/Content/Paks/translation.pak',
          'url': 'https://example.com/translation.pak',
          'size': 42,
          'sha256': validHash,
        },
      ],
    };

    expect(
      TranslationManifest.fromJson(
        manifestWithDate('2026-07-27T00:00:00.123Z'),
      ).publishedAt,
      DateTime.utc(2026, 7, 27, 0, 0, 0, 123),
    );
    for (final invalid in [
      '2026-07-27T00:00:00+00:00',
      '2026-07-27',
      'invalid',
    ]) {
      expect(
        () => TranslationManifest.fromJson(manifestWithDate(invalid)),
        throwsFormatException,
      );
    }
  });

  test('accepts French host-culture metadata', () {
    final json = _hostManifestJson();
    json['localization'] = {
      'sourceCulture': 'en',
      'installationCulture': 'fr',
      'targetLanguage': 'pt-BR',
      'hostCompatible': true,
      'hostLocresSha256': 'e' * 64,
    };
    final manifest = TranslationManifest.fromJson(json);
    expect(manifest.localization?.installationCulture, 'fr');
    expect(manifest.localization?.targetLanguage, 'pt-BR');
  });

  test('rejects unsupported host-culture metadata', () {
    final json = _hostManifestJson();
    json['localization'] = {
      'sourceCulture': 'en',
      'installationCulture': 'de',
      'targetLanguage': 'pt-BR',
      'hostCompatible': true,
      'hostLocresSha256': 'e' * 64,
    };
    expect(() => TranslationManifest.fromJson(json), throwsFormatException);
  });

  test('rejects duplicate file names case-insensitively', () {
    expect(
      () => TranslationManifest.fromJson({
        'schemaVersion': 1,
        'translationVersion': '1.0.0',
        'publishedAt': '2026-07-27T00:00:00Z',
        'files': [
          {
            'name': 'translation.pak',
            'relativeDestination': 'Client/Content/Paks/one.pak',
            'url': 'https://example.com/one.pak',
            'size': 42,
            'sha256': validHash,
          },
          {
            'name': 'TRANSLATION.PAK',
            'relativeDestination': 'Client/Content/Paks/two.pak',
            'url': 'https://example.com/two.pak',
            'size': 42,
            'sha256': validHash,
          },
        ],
      }),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _hostManifestJson() => {
  'schemaVersion': 1,
  'translationVersion': '1.0.0',
  'publishedAt': '2026-07-27T00:00:00Z',
  'files': [
    {
      'name': 'translation.pak',
      'relativeDestination': 'Client/Content/Paks/translation.pak',
      'url': 'https://example.com/translation.pak',
      'size': 42,
      'sha256': validHash,
    },
  ],
};
