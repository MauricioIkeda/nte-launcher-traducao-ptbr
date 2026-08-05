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

  Future<List<Map<String, Object>>> diagnosticExcerpts({
    int maxTotalBytes = 256 * 1024,
  }) async {
    await _pending;
    if (maxTotalBytes <= 0) return const [];

    var remaining = maxTotalBytes;
    final excerpts = <Map<String, Object>>[];
    for (var index = 0; index <= retainedFiles && remaining > 0; index++) {
      final source = File(index == 0 ? file.path : '${file.path}.$index');
      if (!await source.exists()) continue;

      try {
        final length = await source.length();
        final readLength = length < remaining ? length : remaining;
        final handle = await source.open();
        try {
          await handle.setPosition(length - readLength);
          final bytes = await handle.read(readLength);
          final content = redactSensitiveValues(
            utf8.decode(bytes, allowMalformed: true),
          );
          excerpts.insert(0, {
            'file': _fileName(source.path),
            'content': content,
            'truncated': readLength < length,
          });
          remaining -= readLength;
        } finally {
          await handle.close();
        }
      } catch (_) {
        // A partially unreadable log must not prevent diagnostics export.
      }
    }
    return excerpts;
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

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  static String redactSensitiveValues(String value) {
    var result = value.replaceAll(
      RegExp(r'AIza[0-9A-Za-z_-]{20,}'),
      '[REDACTED_API_KEY]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'''(\b(?:authorization|proxy-authorization)\b["']?\s*[:=]\s*["']?)(?:Bearer\s+)?([^"'\s,;}]+)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'''(\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|client[_-]?secret|session[_-]?(?:id|token)|cookie|set-cookie)\b["']?\s*[:=]\s*["']?)([^"'\s&,;}]+)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[REDACTED]',
    );
    return result;
  }
}
