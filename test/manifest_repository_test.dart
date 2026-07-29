import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/services/manifest_repository.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-manifest-test-');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('cache-busts the remote translation manifest request', () async {
    final paths = AppPaths.forTesting(sandbox);
    Uri? requestedUri;
    final source = jsonEncode({
      'schemaVersion': 1,
      'translationVersion': 'nte-auto-20260729-010203-test',
      'publishedAt': '2026-07-29T01:02:03Z',
      'files': [
        {
          'name': 'translation.pak',
          'relativeDestination': 'Client/Content/Paks/translation.pak',
          'url': 'https://github.com/example/releases/translation.pak',
          'size': 42,
          'sha256': 'a' * 64,
        },
      ],
    });
    final repository = ManifestRepository(
      paths,
      LauncherLog(paths.logFile),
      remoteManifestUrl:
          'https://raw.githubusercontent.com/example/project/main/'
          'translation_manifest.json?channel=stable',
      remoteManifestDownloader: (uri) async {
        requestedUri = uri;
        return source;
      },
    );

    final manifest = await repository.load();

    expect(
      manifest?.manifest.translationVersion,
      'nte-auto-20260729-010203-test',
    );
    expect(manifest?.source.name, 'remote');
    expect(requestedUri?.queryParameters['channel'], 'stable');
    expect(requestedUri?.queryParameters['_nte_cache_bust'], isNotEmpty);
    expect(await paths.cachedManifest.readAsString(), source);
  });

  test('reports cache as offline source when remote request fails', () async {
    final paths = AppPaths.forTesting(sandbox);
    await paths.cache.create(recursive: true);
    final source = jsonEncode({
      'schemaVersion': 1,
      'translationVersion': 'cached-version',
      'publishedAt': '2026-07-28T01:02:03Z',
      'files': [
        {
          'name': 'translation.pak',
          'relativeDestination': 'Client/Content/Paks/translation.pak',
          'url': 'https://github.com/example/releases/translation.pak',
          'size': 42,
          'sha256': 'a' * 64,
        },
      ],
    });
    await paths.cachedManifest.writeAsString(source);
    final repository = ManifestRepository(
      paths,
      LauncherLog(paths.logFile),
      remoteManifestUrl: 'https://example.com/manifest.json',
      remoteManifestDownloader: (_) async =>
          throw const SocketException('offline'),
    );

    final result = await repository.load();

    expect(result?.source.name, 'cache');
    expect(result?.isAuthoritative, isFalse);
    expect(result?.manifest.translationVersion, 'cached-version');
  });
}
