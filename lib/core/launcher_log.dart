import 'dart:io';

class LauncherLog {
  LauncherLog(this.file);

  final File file;
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
        await file.writeAsString(
          '[${DateTime.now().toIso8601String()}] [$level] $message\r\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Logging must not prevent the launcher from working.
      }
    });
    return _pending;
  }
}
