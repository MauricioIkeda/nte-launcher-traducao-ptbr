import 'dart:convert';
import 'dart:io';

class LauncherLog {
  LauncherLog(
    this.file, {
    this.maxBytes = 2 * 1024 * 1024,
    this.retainedFiles = 5,
  });

  final File file;
  final int maxBytes;
  final int retainedFiles;
  Future<void> _pending = Future<void>.value();

  Future<void> info(String message) => _write('INFO', message);

  Future<void> error(String message, {Object? error, StackTrace? stackTrace}) {
    final details = StringBuffer(message);
    if (error != null) {
      details.write(' | ${error.runtimeType}: $error');
    }
    if (stackTrace != null) {
      details.write('\n$stackTrace');
    }
    return _write('ERROR', details.toString());
  }

  Future<void> _write(String level, String message) {
    _pending = _pending.then((_) async {
      try {
        await file.parent.create(recursive: true);
        final entry =
            '[${DateTime.now().toIso8601String()}] [$level] $message\r\n';
        if (await file.exists() &&
            await file.length() + utf8.encode(entry).length > maxBytes) {
          await _rotate();
        }
        await file.writeAsString(entry, mode: FileMode.append, flush: true);
      } catch (_) {
        // Logging must not prevent the launcher from working.
      }
    });
    return _pending;
  }

  Future<void> _rotate() async {
    if (retainedFiles <= 0) {
      await file.delete();
      return;
    }
    for (var index = retainedFiles; index >= 1; index--) {
      final source = File(index == 1 ? file.path : '${file.path}.${index - 1}');
      if (!await source.exists()) continue;
      final destination = File('${file.path}.$index');
      if (await destination.exists()) await destination.delete();
      await source.rename(destination.path);
    }
  }
}
