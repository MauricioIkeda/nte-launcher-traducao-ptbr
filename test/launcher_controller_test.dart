import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/launcher_controller.dart';
import 'package:nte_translation_launcher/models/app_update_manifest.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/app_update_service.dart';
import 'package:nte_translation_launcher/services/download_service.dart';
import 'package:nte_translation_launcher/services/elevation_service.dart';
import 'package:nte_translation_launcher/services/game_platform_service.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:nte_translation_launcher/services/manifest_repository.dart';
import 'package:nte_translation_launcher/services/settings_service.dart';

void main() {
  late Directory sandbox;
  late AppPaths paths;
  late LauncherLog log;
  late TranslationManifest latestManifest;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-controller-test-');
    paths = AppPaths.forTesting(sandbox);
    log = LauncherLog(paths.logFile);
    latestManifest = TranslationManifest.fromJson({
      'schemaVersion': 1,
      'translationVersion': 'nte-auto-20260729-new',
      'publishedAt': '2026-07-29T06:25:21Z',
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
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('automatically installs a newer translation during startup', () async {
    final settings = _FakeSettingsService(sandbox.path);
    final installer = _FakeInstallationService(paths, log);
    final downloads = _FakeDownloadService(paths, log);
    final controller = _controller(
      paths: paths,
      log: log,
      manifest: latestManifest,
      settings: settings,
      installer: installer,
      downloads: downloads,
    );
    final statuses = <LauncherStatus>[];
    controller.addListener(() => statuses.add(controller.status));

    await controller.initialize();

    expect(installer.installedVersion, latestManifest.translationVersion);
    expect(settings.installedVersion, latestManifest.translationVersion);
    expect(controller.installedVersion, latestManifest.translationVersion);
    expect(controller.translationIsCurrent, isTrue);
    expect(controller.status, LauncherStatus.completed);
    expect(statuses, contains(LauncherStatus.downloading));
    expect(statuses, contains(LauncherStatus.installing));
  });

  test(
    'blocks play and removal while an automatic update is downloading',
    () async {
      final settings = _FakeSettingsService(sandbox.path);
      final installer = _FakeInstallationService(paths, log);
      final downloads = _FakeDownloadService(paths, log, pauseDownload: true);
      final gamePlatforms = _FakeGamePlatformService();
      final controller = _controller(
        paths: paths,
        log: log,
        manifest: latestManifest,
        settings: settings,
        installer: installer,
        downloads: downloads,
        gamePlatforms: gamePlatforms,
      );

      final initialization = controller.initialize();
      await downloads.started.future;

      expect(controller.status, LauncherStatus.downloading);
      expect(controller.isBusy, isTrue);
      await controller.launchGame();
      await controller.removeTranslation();
      expect(gamePlatforms.launchCount, 0);
      expect(installer.uninstallCount, 0);

      downloads.release();
      await initialization;
    },
  );
}

LauncherController _controller({
  required AppPaths paths,
  required LauncherLog log,
  required TranslationManifest manifest,
  required _FakeSettingsService settings,
  required _FakeInstallationService installer,
  required _FakeDownloadService downloads,
  _FakeGamePlatformService? gamePlatforms,
}) {
  return LauncherController(
    paths: paths,
    log: log,
    appUpdates: _FakeAppUpdateService(paths, log),
    manifests: _FakeManifestRepository(paths, log, manifest),
    downloads: downloads,
    elevation: _FakeElevationService(log),
    gamePlatforms: gamePlatforms ?? _FakeGamePlatformService(),
    installer: installer,
    settings: settings,
  );
}

class _FakeSettingsService implements LauncherSettings {
  _FakeSettingsService(this.gameDirectory);

  final String gameDirectory;
  String? installedVersion = 'nte-auto-20260728-old';

  @override
  Future<String?> getGameDirectory() async => gameDirectory;

  @override
  Future<String?> getInstalledVersion() async => installedVersion;

  @override
  Future<void> setInstalledVersion(String value) async {
    installedVersion = value;
  }

  @override
  Future<void> setGameDirectory(String value) async {}

  @override
  Future<void> clearInstalledVersion() async {
    installedVersion = null;
  }

  @override
  Future<bool> getAutomaticLauncherUpdates() async => false;

  @override
  Future<void> setAutomaticLauncherUpdates(bool value) async {}

  @override
  Future<bool> getOfficialAutoplay() async => true;

  @override
  Future<void> setOfficialAutoplay(bool value) async {}
}

class _FakeManifestRepository extends ManifestRepository {
  _FakeManifestRepository(super.paths, super.log, this.manifest);

  final TranslationManifest manifest;

  @override
  Future<TranslationManifest?> load() async => manifest;
}

class _FakeDownloadService extends DownloadService {
  _FakeDownloadService(super.paths, super.log, {this.pauseDownload = false});

  final bool pauseDownload;
  final Completer<void> started = Completer<void>();
  final Completer<void> _continue = Completer<void>();

  @override
  Future<Directory> download(
    TranslationManifest manifest, {
    required DownloadProgressCallback onProgress,
    required bool Function() isCancelled,
  }) async {
    if (!started.isCompleted) {
      started.complete();
    }
    if (pauseDownload) {
      await _continue.future;
    }
    final stage = Directory('${paths.root.path}/stage');
    await stage.create(recursive: true);
    onProgress(manifest.totalBytes, manifest.totalBytes, 'translation.pak');
    return stage;
  }

  void release() {
    if (!_continue.isCompleted) {
      _continue.complete();
    }
  }
}

class _FakeInstallationService extends InstallationService {
  _FakeInstallationService(super.paths, super.log);

  String? installedVersion;
  int uninstallCount = 0;

  @override
  Future<bool> isValidGameDirectory(String path) async => true;

  @override
  Future<void> install(
    TranslationManifest manifest,
    Directory stage,
    String gameDirectory,
  ) async {
    installedVersion = manifest.translationVersion;
  }

  @override
  Future<void> uninstall() async {
    uninstallCount++;
  }
}

class _FakeElevationService extends ElevationService {
  _FakeElevationService(super.log);

  @override
  Future<bool> ensureWritableOrRestart(
    String gameDirectory, {
    required bool allowRestart,
  }) async => true;
}

class _FakeGamePlatformService extends GamePlatformService {
  int launchCount = 0;

  @override
  Future<GamePlatformInfo> detect(String gameDirectory) async {
    return GamePlatformInfo(
      platform: GamePlatform.official,
      label: 'LAUNCHER OFICIAL',
      launchTarget: '$gameDirectory/NTEGlobalLauncher.exe',
    );
  }

  @override
  Future<void> launch(
    GamePlatformInfo info,
    String gameDirectory, {
    bool officialAutoplay = true,
  }) async {
    launchCount++;
  }
}

class _FakeAppUpdateService extends AppUpdateService {
  _FakeAppUpdateService(super.paths, super.log);

  @override
  Future<String> currentVersion() async => '1.0.3';

  @override
  Future<AppUpdateManifest?> check() async => null;
}
