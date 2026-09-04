import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/app_update_manifest.dart';
import 'package:nte_translation_launcher/services/app_update_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late AppPaths paths;
  late AppUpdateService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-update-test-');
    paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    service = AppUpdateService(
      paths,
      LauncherLog(paths.logFile),
      currentVersion: '1.0.0',
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('accepts an installer with the expected size and SHA-256', () async {
    final installer = File(p.join(sandbox.path, 'Setup.exe'));
    await installer.writeAsBytes([1, 2, 3]);
    final manifest = updateManifest(
      size: 3,
      sha256:
          '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced528'
          '7d84a1a2011cfb81',
    );

    await expectLater(service.verifyInstaller(installer, manifest), completes);
  });

  test('rejects an installer with a different SHA-256', () async {
    final installer = File(p.join(sandbox.path, 'Setup.exe'));
    await installer.writeAsBytes([1, 2, 3]);
    final manifest = updateManifest(
      size: 3,
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
          'aaaaaaaaaaaaaaaa',
    );

    await expectLater(
      service.verifyInstaller(installer, manifest),
      throwsA(isA<AppUpdateException>()),
    );
  });

  test('uses the standardized installer filename', () {
    expect(
      p.basename(paths.updateInstaller.path),
      'NTE-Launcher-Traducao-PTBR-Setup.exe',
    );
  });

  test('release candidate accepts the same stable version as replacement', () {
    final candidate = AppUpdateService(
      paths,
      LauncherLog(paths.logFile),
      currentVersion: '1.4.7',
      releaseCandidate: true,
    );
    final stable = updateManifest(
      version: '1.4.7',
      size: 3,
      sha256:
          '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced528'
          '7d84a1a2011cfb81',
    );

    expect(candidate.isUpdateAvailable(stable, '1.4.7'), isTrue);
  });

  test('stable build does not reinstall the same stable version', () {
    final stableService = AppUpdateService(
      paths,
      LauncherLog(paths.logFile),
      currentVersion: '1.4.7',
      releaseCandidate: false,
    );
    final stable = updateManifest(
      version: '1.4.7',
      size: 3,
      sha256:
          '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced528'
          '7d84a1a2011cfb81',
    );

    expect(stableService.isUpdateAvailable(stable, '1.4.7'), isFalse);
  });

  test('release candidate still rejects an older stable version', () {
    final candidate = AppUpdateService(
      paths,
      LauncherLog(paths.logFile),
      currentVersion: '1.4.7',
      releaseCandidate: true,
    );
    final older = updateManifest(
      version: '1.4.6',
      size: 3,
      sha256:
          '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced528'
          '7d84a1a2011cfb81',
    );

    expect(candidate.isUpdateAvailable(older, '1.4.7'), isFalse);
  });
}

AppUpdateManifest updateManifest({
  String version = '1.1.0',
  required int size,
  required String sha256,
}) {
  return AppUpdateManifest(
    schemaVersion: 1,
    version: version,
    publishedAt: DateTime.utc(2026, 7, 27),
    installerUrl: Uri.parse(
      'https://github.com/owner/repository/releases/download/'
      'v$version/Setup.exe',
    ),
    installerSize: size,
    installerSha256: sha256,
    releaseNotes: '',
    mandatory: false,
  );
}
