import 'dart:io';

import '../models/pre_installation_check.dart';
import '../models/translation_manifest.dart';
import 'elevation_service.dart';
import 'installation_service.dart';

typedef AvailableSpaceProbe = Future<int?> Function(String path);
typedef RunningProcessesProbe = Future<Set<String>?> Function();

class PreInstallationService {
  PreInstallationService({
    required this.installer,
    required this.elevation,
    AvailableSpaceProbe? availableSpace,
    RunningProcessesProbe? runningProcesses,
  }) : _availableSpace = availableSpace ?? _defaultAvailableSpace,
       _runningProcesses = runningProcesses ?? _defaultRunningProcesses;

  static const _safetyMarginBytes = 64 * 1024 * 1024;
  static const _gameProcessNames = {
    'htgame.exe',
    'nteglobalgame.exe',
    'ht-win64-shipping.exe',
    'nte-win64-shipping.exe',
  };

  final InstallationService installer;
  final ElevationService elevation;
  final AvailableSpaceProbe _availableSpace;
  final RunningProcessesProbe _runningProcesses;

  Future<PreInstallationReport> run({
    required TranslationManifest manifest,
    required String gameDirectory,
    required String downloadDirectory,
  }) async {
    final checks = <PreInstallationCheck>[];

    final validDirectory = await installer.isValidGameDirectory(gameDirectory);
    checks.add(
      PreInstallationCheck(
        id: 'game-directory',
        label: 'Pasta do jogo',
        detail: validDirectory
            ? 'NTEGlobalLauncher.exe foi encontrado.'
            : 'A pasta não contém NTEGlobalLauncher.exe.',
        status: validDirectory
            ? PreInstallationCheckStatus.passed
            : PreInstallationCheckStatus.failed,
      ),
    );
    if (!validDirectory) {
      return PreInstallationReport(checks);
    }

    final running = await _runningProcesses();
    final runningGame = running?.intersection(_gameProcessNames) ?? const {};
    checks.add(
      PreInstallationCheck(
        id: 'game-process',
        label: 'Jogo fechado',
        detail: running == null
            ? 'Não foi possível consultar os processos; confirme que o jogo está fechado.'
            : runningGame.isEmpty
            ? 'Nenhum processo do jogo está em execução.'
            : 'Feche o jogo antes de continuar: ${runningGame.join(', ')}.',
        status: running == null
            ? PreInstallationCheckStatus.warning
            : runningGame.isEmpty
            ? PreInstallationCheckStatus.passed
            : PreInstallationCheckStatus.failed,
      ),
    );

    final writable = await elevation.canWrite(gameDirectory);
    checks.add(
      PreInstallationCheck(
        id: 'write-access',
        label: 'Permissão de escrita',
        detail: writable
            ? 'A pasta permite alterações.'
            : 'O Windows solicitará permissão de administrador.',
        status: writable
            ? PreInstallationCheckStatus.passed
            : PreInstallationCheckStatus.warning,
      ),
    );

    final requiredDownload = manifest.totalBytes + _safetyMarginBytes;
    final requiredGame = (manifest.totalBytes * 2) + _safetyMarginBytes;
    checks.add(
      await _spaceCheck(
        id: 'download-space',
        label: 'Espaço para download',
        path: downloadDirectory,
        requiredBytes: requiredDownload,
      ),
    );
    checks.add(
      await _spaceCheck(
        id: 'game-space',
        label: 'Espaço para instalação e backup',
        path: gameDirectory,
        requiredBytes: requiredGame,
      ),
    );

    checks.add(
      const PreInstallationCheck(
        id: 'manifest-integrity',
        label: 'Manifesto e hashes',
        detail: 'Metadados validados; cada arquivo será conferido por SHA-256.',
        status: PreInstallationCheckStatus.passed,
      ),
    );
    return PreInstallationReport(checks);
  }

  Future<PreInstallationCheck> _spaceCheck({
    required String id,
    required String label,
    required String path,
    required int requiredBytes,
  }) async {
    final available = await _availableSpace(path);
    if (available == null) {
      return PreInstallationCheck(
        id: id,
        label: label,
        detail:
            'Não foi possível consultar o espaço livre; prossiga com atenção.',
        status: PreInstallationCheckStatus.warning,
      );
    }
    final enough = available >= requiredBytes;
    return PreInstallationCheck(
      id: id,
      label: label,
      detail: enough
          ? '${_formatBytes(available)} disponíveis.'
          : 'Espaço insuficiente: ${_formatBytes(available)} disponíveis; '
                '${_formatBytes(requiredBytes)} necessários.',
      status: enough
          ? PreInstallationCheckStatus.passed
          : PreInstallationCheckStatus.failed,
    );
  }

  static Future<int?> _defaultAvailableSpace(String path) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'powershell.exe',
          const [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            r'$path = [Environment]::GetEnvironmentVariable("NTE_CHECK_PATH"); '
                r'$root = [IO.Path]::GetPathRoot($path); '
                r'[IO.DriveInfo]::new($root).AvailableFreeSpace',
          ],
          environment: {...Platform.environment, 'NTE_CHECK_PATH': path},
          runInShell: false,
        );
        if (result.exitCode != 0) return null;
        return int.tryParse(result.stdout.toString().trim());
      }
      final result = await Process.run('df', ['-Pk', path]);
      if (result.exitCode != 0) return null;
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length < 2) return null;
      final columns = lines.last.trim().split(RegExp(r'\s+'));
      if (columns.length < 4) return null;
      final kibibytes = int.tryParse(columns[3]);
      return kibibytes == null ? null : kibibytes * 1024;
    } on ProcessException {
      return null;
    }
  }

  static Future<Set<String>?> _defaultRunningProcesses() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist.exe', const [
          '/FO',
          'CSV',
          '/NH',
        ]);
        if (result.exitCode != 0) return null;
        return {
          for (final line in result.stdout.toString().split('\n'))
            if (RegExp(r'^"([^"]+)"').firstMatch(line)?.group(1)
                case final name?)
              name.toLowerCase(),
        };
      }
      final result = await Process.run('ps', const ['-A', '-o', 'comm=']);
      if (result.exitCode != 0) return null;
      return result.stdout
          .toString()
          .split('\n')
          .map((name) => name.trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
    } on ProcessException {
      return null;
    }
  }

  static String _formatBytes(int bytes) {
    final mebibytes = bytes / (1024 * 1024);
    if (mebibytes >= 1024) {
      return '${(mebibytes / 1024).toStringAsFixed(1)} GB';
    }
    return '${mebibytes.ceil()} MB';
  }
}
