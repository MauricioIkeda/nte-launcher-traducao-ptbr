import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/pre_installation_check.dart';
import 'package:nte_translation_launcher/services/elevation_service.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:nte_translation_launcher/services/pre_installation_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory sandbox;
  late Directory game;
  late InstallationService installer;
  late LauncherLog log;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-preflight-');
    game = await createGame(sandbox, 'game');
    final paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    log = LauncherLog(paths.logFile);
    installer = InstallationService(paths, log);
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('approves a valid environment before installation', () async {
    final service = PreInstallationService(
      installer: installer,
      elevation: _FakeElevation(log, writable: true),
      availableSpace: (_) async => 2 * 1024 * 1024 * 1024,
      runningProcesses: () async => const {},
    );

    final report = await service.run(
      manifest: testManifest(),
      gameDirectory: game.path,
      downloadDirectory: sandbox.path,
    );

    expect(report.canProceed, isTrue);
    expect(report.warningCount, 0);
    expect(report.failures, isEmpty);
    expect(report.checks, hasLength(6));
  });

  test(
    'Windows probes resolve real write access and drive space',
    () async {
      final service = PreInstallationService(
        installer: installer,
        elevation: ElevationService(log),
      );

      final report = await service.run(
        manifest: testManifest(),
        gameDirectory: game.path,
        downloadDirectory: sandbox.path,
      );

      for (final id in const [
        'game-directory',
        'write-access',
        'download-space',
        'game-space',
      ]) {
        expect(
          report.checks.singleWhere((check) => check.id == id).status,
          PreInstallationCheckStatus.passed,
          reason: id,
        );
      }
    },
    skip: !Platform.isWindows,
  );

  test('blocks installation while the game process is running', () async {
    final service = PreInstallationService(
      installer: installer,
      elevation: _FakeElevation(log, writable: true),
      availableSpace: (_) async => 2 * 1024 * 1024 * 1024,
      runningProcesses: () async => {'htgame.exe'},
    );

    final report = await service.run(
      manifest: testManifest(),
      gameDirectory: game.path,
      downloadDirectory: sandbox.path,
    );

    expect(report.canProceed, isFalse);
    expect(report.failureSummary, contains('Feche o jogo'));
  });

  test('blocks installation when a drive has insufficient space', () async {
    final service = PreInstallationService(
      installer: installer,
      elevation: _FakeElevation(log, writable: true),
      availableSpace: (_) async => 1,
      runningProcesses: () async => const {},
    );

    final report = await service.run(
      manifest: testManifest(),
      gameDirectory: game.path,
      downloadDirectory: sandbox.path,
    );

    expect(report.canProceed, isFalse);
    expect(
      report.failures.where((check) => check.id.endsWith('space')),
      hasLength(2),
    );
  });

  test(
    'warns instead of blocking when elevation can solve write access',
    () async {
      final service = PreInstallationService(
        installer: installer,
        elevation: _FakeElevation(log, writable: false),
        availableSpace: (_) async => 2 * 1024 * 1024 * 1024,
        runningProcesses: () async => const {},
      );

      final report = await service.run(
        manifest: testManifest(),
        gameDirectory: game.path,
        downloadDirectory: sandbox.path,
      );

      expect(report.canProceed, isTrue);
      expect(report.warningCount, 1);
      expect(
        report.checks.singleWhere((check) => check.id == 'write-access').status,
        PreInstallationCheckStatus.warning,
      );
    },
  );
}

class _FakeElevation extends ElevationService {
  _FakeElevation(super.log, {required this.writable});

  final bool writable;

  @override
  Future<bool> canWrite(String gameDirectory) async => writable;
}
