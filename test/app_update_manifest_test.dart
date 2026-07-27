import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/models/app_update_manifest.dart';

const installerHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> manifestJson({String version = '1.2.3'}) => {
  'schemaVersion': 1,
  'version': version,
  'publishedAt': '2026-07-27T12:00:00Z',
  'installer': {
    'url':
        'https://github.com/owner/repository/releases/download/'
        'v$version/Launcher-Setup.exe',
    'size': 1024,
    'sha256': installerHash,
  },
  'releaseNotes': 'Correções e melhorias.',
  'mandatory': false,
};

void main() {
  test('accepts a valid launcher update manifest', () {
    final manifest = AppUpdateManifest.fromJson(manifestJson());

    expect(manifest.version, '1.2.3');
    expect(manifest.installerSize, 1024);
    expect(manifest.isNewerThan('1.2.2'), isTrue);
  });

  test('does not report the installed version as an update', () {
    final manifest = AppUpdateManifest.fromJson(manifestJson());

    expect(manifest.isNewerThan('1.2.3'), isFalse);
    expect(manifest.isNewerThan('2.0.0'), isFalse);
  });

  test('rejects installer URLs outside GitHub HTTPS', () {
    final json = manifestJson();
    (json['installer'] as Map<String, dynamic>)['url'] =
        'http://example.com/Launcher-Setup.exe';

    expect(() => AppUpdateManifest.fromJson(json), throwsFormatException);
  });

  test('rejects malformed SHA-256', () {
    final json = manifestJson();
    (json['installer'] as Map<String, dynamic>)['sha256'] = 'not-a-hash';

    expect(() => AppUpdateManifest.fromJson(json), throwsFormatException);
  });
}
