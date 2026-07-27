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
}
