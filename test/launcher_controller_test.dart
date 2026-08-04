import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/launcher_controller.dart';
import 'package:nte_translation_launcher/models/app_update_manifest.dart';
import 'package:nte_translation_launcher/models/loaded_translation_manifest.dart';
import 'package:nte_translation_launcher/models/pre_installation_check.dart';
import 'package:nte_translation_launcher/models/translation_installation.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/app_update_service.dart';
import 'package:nte_translation_launcher/services/download_service.dart';
import 'package:nte_translation_launcher/services/elevation_service.dart';
import 'package:nte_translation_launcher/services/file_integrity_service.dart';
import 'package:nte_translation_launcher/services/game_platform_service.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:nte_translation_launcher/services/legacy_migration_service.dart';
import 'package:nte_translation_launcher/services/manifest_repository.dart';
import 'package:nte_translation_launcher/services/pre_installation_service.dart';
import 'package:nte_translation_launcher/services/receipt_repository.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:nte_translation_launcher/services/settings_service.dart';
import 'package:nte_translation_launcher/services/translation_verification_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory sandbox;
  late Directory game;
  late AppPaths paths;
  late LauncherLog log;
  late _Harness harness;
  const contents = [
    [1, 2, 3],
    [4, 5, 6, 7],
  ];

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-controller-');
    game = await createGame(sandbox, 'game');
    paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    log = LauncherLog(paths.logFile);
    harness = _Harness(paths, log);
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('persisted version alone is never proof of installation', () async {
    final settings = _FakeSettings(game.path)
      ..installedVersion = 'false-version';
    final controller = harness.controller(
      manifest: testManifest(contents: contents),
      contents: contents,
      settings: settings,
    );

    await controller.initialize();

    expect(
      controller.verification.status,
      TranslationInstallationStatus.notInstalled,
    );
    expect(controller.isInstalled, isFalse);
    expect(settings.installedVersion, isNull);
  });

  test('initialization verifies disk before exposing ready state', () async {
    final controller = harness.controller(
      manifest: testManifest(contents: contents),
      contents: contents,
      settings: _FakeSettings(game.path),
    );
    final statuses = <LauncherStatus>[];
    controller.addListener(() => statuses.add(controller.status));

    await controller.initialize();

    expect(statuses, contains(LauncherStatus.loadingManifest));
    expect(statuses, contains(LauncherStatus.verifying));
    expect(statuses.last, LauncherStatus.ready);
  });

  test('normalizes a previously saved nested launcher directory', () async {
    final nested = Directory(p.join(game.path, 'NTEGlobal'));
    await nested.create();
    await File(
      p.join(nested.path, 'NTEGlobalLauncher.exe'),
    ).writeAsBytes(const [77, 90]);
    final settings = _FakeSettings(nested.path);
    final controller = harness.controller(
      manifest: testManifest(contents: contents),
      contents: contents,
      settings: settings,
    );

    await controller.initialize();

    expect(controller.gameDirectory, p.normalize(p.absolute(game.path)));
    expect(settings.gameDirectory, p.normalize(p.absolute(game.path)));
  });

  test('exports diagnostics without secrets or remote writes', () async {
    final controller = harness.controller(
      manifest: testManifest(contents: contents),
      contents: contents,
      settings: _FakeSettings(game.path),
    );
    await controller.initialize();

    final file = await controller.exportDiagnostics(reveal: false);
    final diagnostics = await file.readAsString();
    final decoded = jsonDecode(diagnostics) as Map<String, dynamic>;

    expect(decoded['schemaVersion'], 2);
    expect(diagnostics, contains('verificationStatus'));
    expect(decoded['gameDirectory'], game.path);
    expect(decoded['verification'], isA<Map<String, dynamic>>());
    expect(decoded['recentLogs'], isA<List<dynamic>>());
    expect(
      (decoded['recentLogs'] as List<dynamic>).join('\n'),
      contains('Verifica'),
    );
    expect(diagnostics, isNot(contains('token')));
    expect(diagnostics, isNot(contains('api_key')));
  });

  test(
    'newer remote translation is automatically installed and reverified',
    () async {
      final oldContents = const [
        [8, 8, 8],
        [7, 7, 7, 7],
      ];
      final oldManifest = testManifest(
        version: 'old',
        publishedAt: DateTime.utc(2026, 7, 28),
        contents: oldContents,
      );
      final oldStage = await createStage(sandbox, oldManifest, oldContents);
      await harness.installer.install(oldManifest, oldStage, game.path);
      final latest = testManifest(contents: contents);
      final controller = harness.controller(
        manifest: latest,
        contents: contents,
        settings: _FakeSettings(game.path),
      );

      await controller.initialize();

      expect(controller.translationIsCurrent, isTrue);
      expect(controller.installedVersion, latest.translationVersion);
      expect(controller.status, LauncherStatus.completed);
    },
  );

  test(
    'changing directory triggers fresh verification for that directory',
    () async {
      final other = await createGame(sandbox, 'other');
      final manifest = testManifest(contents: contents);
      await _writeFiles(other, manifest, contents);
      final controller = harness.controller(
        manifest: manifest,
        contents: contents,
        settings: _FakeSettings(null),
      );
      await controller.initialize();

      await controller.selectGameDirectory(other.path);

      expect(controller.gameDirectory, other.path);
      expect(controller.translationIsCurrent, isTrue);
    },
  );

  test(
    'invalid directory preserves active game state and exposes local error',
    () async {
      final manifest = testManifest(contents: contents);
      final stage = await createStage(sandbox, manifest, contents);
      await harness.installer.install(manifest, stage, game.path);

      final settings = _FakeSettings(game.path);
      final controller = harness.controller(
        manifest: manifest,
        contents: contents,
        settings: settings,
      );
      await controller.initialize();

      final previousPlatform = controller.gamePlatform;
      final invalid = Directory(p.join(sandbox.path, 'downloads'));
      await invalid.create();

      await controller.selectGameDirectory(invalid.path);

      expect(controller.gameDirectory, game.path);
      expect(settings.gameDirectory, game.path);
      expect(controller.translationIsCurrent, isTrue);
      expect(controller.gamePlatform?.label, previousPlatform?.label);
      expect(controller.status, LauncherStatus.ready);
      expect(controller.errorMessage, isNull);
      expect(controller.rejectedGameDirectory, invalid.path);
      expect(
        controller.gameDirectorySelectionError,
        contains('instalação completa do NTE'),
      );
      expect(controller.validatingGameDirectory, isFalse);
    },
  );

  test('valid directory clears a previous directory selection error', () async {
    final other = await createGame(sandbox, 'other');
    final invalid = Directory(p.join(sandbox.path, 'invalid'));
    await invalid.create();

    final settings = _FakeSettings(game.path);
    final controller = harness.controller(
      manifest: testManifest(contents: contents),
      contents: contents,
      settings: settings,
    );
    await controller.initialize();

    await controller.selectGameDirectory(invalid.path);

    expect(controller.gameDirectorySelectionError, isNotNull);
    expect(controller.rejectedGameDirectory, invalid.path);
    expect(controller.gameDirectory, game.path);

    await controller.selectGameDirectory(other.path);

    expect(controller.gameDirectory, other.path);
    expect(settings.gameDirectory, other.path);
    expect(controller.gameDirectorySelectionError, isNull);
    expect(controller.rejectedGameDirectory, isNull);
    expect(controller.validatingGameDirectory, isFalse);
    expect(controller.status, LauncherStatus.ready);
  });

  test(
    'stale verification result cannot overwrite a newer directory',
    () async {
      final first = await createGame(sandbox, 'first');
      final second = await createGame(sandbox, 'second');
      final manifest = testManifest(contents: contents);
      await _writeFiles(second, manifest, contents);
      final delayed = _DelayedVerifier(
        integrity: harness.integrity,
        receipts: harness.receipts,
        safePaths: harness.safePaths,
        log: log,
        delayedDirectory: first.path,
      );
      final controller = harness.controller(
        manifest: manifest,
        contents: contents,
        settings: _FakeSettings(null),
        verifier: delayed,
      );
      await controller.initialize();

      final firstSelection = controller.selectGameDirectory(first.path);
      await delayed.started.future;
      await controller.selectGameDirectory(second.path);
      delayed.release.complete();
      await firstSelection;

      expect(controller.gameDirectory, second.path);
      expect(controller.translationIsCurrent, isTrue);
    },
  );

  test('manual installation finishes with a new real verification', () async {
    final manifest = testManifest(contents: contents);
    final controller = harness.controller(
      manifest: manifest,
      contents: contents,
      settings: _FakeSettings(game.path),
    );
    await controller.initialize();

    await controller.installOrUpdate();

    expect(controller.status, LauncherStatus.completed);
    expect(controller.translationIsCurrent, isTrue);
  });

  test('failed pre-installation check blocks the download', () async {
    final downloads = _FakeDownloadService(paths, log, contents);
    final controller = harness.controller(
      manifest: testManifest(contents: contents),
      contents: contents,
      settings: _FakeSettings(game.path),
      downloads: downloads,
      preInstallation: _BlockedPreInstallationService(harness.installer, log),
    );
    await controller.initialize();

    await controller.installOrUpdate();

    expect(controller.status, LauncherStatus.error);
    expect(controller.preInstallationReport?.canProceed, isFalse);
    expect(controller.errorMessage, contains('Feche o jogo'));
    expect(downloads.started.isCompleted, isFalse);
  });

  test('repair restores missing file and finishes verified', () async {
    final manifest = testManifest(contents: contents);
    final stage = await createStage(sandbox, manifest, contents);
    await harness.installer.install(manifest, stage, game.path);
    await File(
      p.join(game.path, manifest.files.first.relativeDestination),
    ).delete();
    final controller = harness.controller(
      manifest: manifest,
      contents: contents,
      settings: _FakeSettings(game.path),
    );
    await controller.initialize();
    expect(controller.translationNeedsRepair, isTrue);

    await controller.repairTranslation();

    expect(controller.translationIsCurrent, isTrue);
  });

  test('removal finishes with a fresh not-installed verification', () async {
    final manifest = testManifest(contents: contents);
    final stage = await createStage(sandbox, manifest, contents);
    await harness.installer.install(manifest, stage, game.path);
    final controller = harness.controller(
      manifest: manifest,
      contents: contents,
      settings: _FakeSettings(game.path),
    );
    await controller.initialize();

    await controller.removeTranslation();

    expect(
      controller.verification.status,
      TranslationInstallationStatus.notInstalled,
    );
  });

  test(
    'download blocks conflicting install, removal and launch clicks',
    () async {
      final downloads = _FakeDownloadService(paths, log, contents, pause: true);
      final platform = _FakeGamePlatformService();
      final controller = harness.controller(
        manifest: testManifest(contents: contents),
        contents: contents,
        settings: _FakeSettings(game.path),
        downloads: downloads,
        gamePlatforms: platform,
      );
      await controller.initialize();

      final installation = controller.installOrUpdate();
      await downloads.started.future;
      await controller.installOrUpdate();
      await controller.removeTranslation();
      await controller.launchGame();
      expect(platform.launchCount, 0);
      downloads.release.complete();
      await installation;
    },
  );

  test('UAC refusal is surfaced without recording a false install', () async {
    final controller = harness.controller(
      manifest: testManifest(contents: contents),
      contents: contents,
      settings: _FakeSettings(game.path),
      elevation: _FakeElevationService(log, refuse: true),
    );
    await controller.initialize();

    await controller.installOrUpdate();

    expect(controller.status, LauncherStatus.error);
    expect(controller.translationIsCurrent, isFalse);
    expect((await harness.receipts.read(game.path)).receipt, isNull);
  });

  test('--install mode revalidates disk before performing its write', () async {
    final settings = _FakeSettings(game.path)..installedVersion = 'stale';
    final controller = harness.controller(
      manifest: testManifest(contents: contents),
      contents: contents,
      settings: settings,
      autoInstall: true,
    );

    await controller.initialize();

    expect(controller.translationIsCurrent, isTrue);
    expect(controller.status, LauncherStatus.completed);
  });
}

class _Harness {
  _Harness(this.paths, this.log) {
    integrity = FileIntegrityService();
    safePaths = SafePathService();
    receipts = ReceiptRepository(paths, log, safePaths);
    installer = InstallationService(
      paths,
      log,
      integrity: integrity,
      safePaths: safePaths,
      receipts: receipts,
    );
  }

  final AppPaths paths;
  final LauncherLog log;
  late final FileIntegrityService integrity;
  late final SafePathService safePaths;
  late final ReceiptRepository receipts;
  late final InstallationService installer;

  LauncherController controller({
    required TranslationManifest manifest,
    required List<List<int>> contents,
    required _FakeSettings settings,
    TranslationVerificationService? verifier,
    DownloadService? downloads,
    ElevationService? elevation,
    GamePlatformService? gamePlatforms,
    PreInstallationService? preInstallation,
    bool autoInstall = false,
  }) {
    final actualVerifier =
        verifier ??
        TranslationVerificationService(
          integrity: integrity,
          receipts: receipts,
          safePaths: safePaths,
          log: log,
        );
    return LauncherController(
      paths: paths,
      log: log,
      appUpdates: _FakeAppUpdateService(paths, log),
      manifests: _FakeManifestRepository(paths, log, loaded(manifest)),
      downloads: downloads ?? _FakeDownloadService(paths, log, contents),
      elevation: elevation ?? _FakeElevationService(log),
      gamePlatforms: gamePlatforms ?? _FakeGamePlatformService(),
      installer: installer,
      settings: settings,
      verifier: actualVerifier,
      migration: LegacyMigrationService(
        paths: paths,
        log: log,
        integrity: integrity,
        receipts: receipts,
        safePaths: safePaths,
      ),
      preInstallation:
          preInstallation ?? _PassingPreInstallationService(installer, log),
      autoInstall: autoInstall,
    );
  }
}

class _FakeSettings implements LauncherSettings {
  _FakeSettings(this.gameDirectory);

  String? gameDirectory;
  String? installedVersion;

  @override
  Future<String?> getGameDirectory() async => gameDirectory;
  @override
  Future<void> setGameDirectory(String value) async => gameDirectory = value;
  @override
  Future<String?> getInstalledVersion() async => installedVersion;
  @override
  Future<void> setInstalledVersion(String value) async =>
      installedVersion = value;
  @override
  Future<void> clearInstalledVersion() async => installedVersion = null;
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
  _FakeManifestRepository(super.paths, super.log, this.value);
  final LoadedTranslationManifest value;
  @override
  Future<LoadedTranslationManifest?> load() async => value;
}

class _FakeDownloadService extends DownloadService {
  _FakeDownloadService(
    super.paths,
    super.log,
    this.contents, {
    this.pause = false,
  });

  final List<List<int>> contents;
  final bool pause;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Directory> download(
    TranslationManifest manifest, {
    required DownloadProgressCallback onProgress,
    required bool Function() isCancelled,
  }) async {
    if (!started.isCompleted) {
      started.complete();
    }
    if (pause) {
      await release.future;
    }
    if (isCancelled()) {
      throw const DownloadCancelledException();
    }
    final stage = Directory(
      p.join(paths.root.path, 'fake-stage-${manifest.translationVersion}'),
    );
    await stage.create(recursive: true);
    for (var index = 0; index < manifest.files.length; index++) {
      await File(
        p.join(stage.path, manifest.files[index].name),
      ).writeAsBytes(contents[index]);
    }
    onProgress(
      manifest.totalBytes,
      manifest.totalBytes,
      manifest.files.last.name,
    );
    return stage;
  }
}

class _FakeElevationService extends ElevationService {
  _FakeElevationService(super.log, {this.refuse = false});
  final bool refuse;
  @override
  Future<bool> ensureWritableOrRestart(
    String gameDirectory, {
    required bool allowRestart,
  }) async {
    if (refuse) {
      throw const ElevationException('UAC recusado.');
    }
    return true;
  }
}

class _FakeGamePlatformService extends GamePlatformService {
  int launchCount = 0;
  @override
  Future<GamePlatformInfo> detect(String gameDirectory) async =>
      GamePlatformInfo(
        platform: GamePlatform.official,
        label: 'LAUNCHER OFICIAL',
        launchTarget: p.join(gameDirectory, 'NTEGlobalLauncher.exe'),
      );
  @override
  Future<void> launch(
    GamePlatformInfo info,
    String gameDirectory, {
    bool officialAutoplay = true,
  }) async {
    launchCount++;
  }
}

class _BlockedPreInstallationService extends PreInstallationService {
  _BlockedPreInstallationService(InstallationService installer, LauncherLog log)
    : super(installer: installer, elevation: _FakeElevationService(log));

  @override
  Future<PreInstallationReport> run({
    required TranslationManifest manifest,
    required String gameDirectory,
    required String downloadDirectory,
  }) async => const PreInstallationReport([
    PreInstallationCheck(
      id: 'game-process',
      label: 'Jogo fechado',
      detail: 'Feche o jogo antes de continuar.',
      status: PreInstallationCheckStatus.failed,
    ),
  ]);
}

class _PassingPreInstallationService extends PreInstallationService {
  _PassingPreInstallationService(InstallationService installer, LauncherLog log)
    : super(installer: installer, elevation: _FakeElevationService(log));

  @override
  Future<PreInstallationReport> run({
    required TranslationManifest manifest,
    required String gameDirectory,
    required String downloadDirectory,
  }) async => const PreInstallationReport([
    PreInstallationCheck(
      id: 'test',
      label: 'Ambiente de teste',
      detail: 'Aprovado.',
      status: PreInstallationCheckStatus.passed,
    ),
  ]);
}

class _FakeAppUpdateService extends AppUpdateService {
  _FakeAppUpdateService(super.paths, super.log);
  @override
  Future<String> currentVersion() async => '1.0.4';
  @override
  Future<AppUpdateManifest?> check() async => null;
}

class _DelayedVerifier extends TranslationVerificationService {
  _DelayedVerifier({
    required super.integrity,
    required super.receipts,
    required super.safePaths,
    required super.log,
    required this.delayedDirectory,
  });

  final String delayedDirectory;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<TranslationVerificationResult> verify({
    required LoadedTranslationManifest loadedManifest,
    required String gameDirectory,
    VerificationProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (gameDirectory == delayedDirectory) {
      started.complete();
      await release.future;
    }
    return super.verify(
      loadedManifest: loadedManifest,
      gameDirectory: gameDirectory,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }
}

Future<void> _writeFiles(
  Directory game,
  TranslationManifest manifest,
  List<List<int>> contents,
) async {
  for (var index = 0; index < manifest.files.length; index++) {
    final file = File(
      p.join(game.path, manifest.files[index].relativeDestination),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(contents[index]);
  }
}
