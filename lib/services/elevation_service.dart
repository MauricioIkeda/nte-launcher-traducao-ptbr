import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/launcher_log.dart';

class ElevationService {
  ElevationService(this.log);

  final LauncherLog log;

  Future<bool> ensureWritableOrRestart(
    String gameDirectory, {
    required bool allowRestart,
  }) async {
    if (await _canWrite(gameDirectory)) {
      return true;
    }
    if (!allowRestart) {
      throw const ElevationException(
        'Mesmo como administrador, a pasta do jogo não permite alterações.',
      );
    }

    await log.info(
      'A pasta do jogo exige elevação. Reiniciando para instalar.',
    );
    final result = await Process.run(
      'powershell.exe',
      const [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "Start-Process -FilePath \$env:NTE_LAUNCHER_EXE -ArgumentList '--install' -Verb RunAs",
      ],
      environment: {
        ...Platform.environment,
        'NTE_LAUNCHER_EXE': Platform.resolvedExecutable,
      },
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw const ElevationException(
        'A permissão de administrador foi cancelada ou recusada.',
      );
    }

    exit(0);
  }

  Future<bool> _canWrite(String gameDirectory) async {
    final probe = File(p.join(gameDirectory, '.nte-write-test-$pid'));
    try {
      await probe.writeAsString('test', flush: true);
      await probe.delete();
      return true;
    } on FileSystemException {
      if (await probe.exists()) {
        await probe.delete();
      }
      return false;
    }
  }
}

class ElevationException implements Exception {
  const ElevationException(this.message);

  final String message;

  @override
  String toString() => message;
}
