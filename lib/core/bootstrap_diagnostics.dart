import 'dart:convert';
import 'dart:io';

import 'launcher_log.dart';

class BootstrapDiagnostics {
  const BootstrapDiagnostics._();

  static const _maximumBytes = 384 * 1024;
  static const _maximumEvents = 250;
  static final String sessionId =
      '${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';

  static File get _file => File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'nte-translation-launcher-bootstrap.jsonl',
  );

  static void recordSync(
    String event, {
    Map<String, Object?> details = const {},
  }) {
    try {
      final file = _file;
      file.parent.createSync(recursive: true);
      _rotateIfNeededSync(file);
      final entry = jsonEncode({
        'at': DateTime.now().toUtc().toIso8601String(),
        'sessionId': sessionId,
        'processId': pid,
        'event': event,
        'details': _sanitize(details),
      });
      file.writeAsStringSync('$entry\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // The black box must never interfere with launcher startup or shutdown.
    }
  }

  static Future<void> record(
    String event, {
    Map<String, Object?> details = const {},
  }) async {
    recordSync(event, details: details);
  }

  static Future<List<Object?>> readRecent() async {
    final file = _file;
    if (!await file.exists()) return const [];
    try {
      final lines = await file.readAsLines();
      final selected = lines.reversed
          .where((line) => line.trim().isNotEmpty)
          .take(_maximumEvents)
          .toList()
          .reversed;
      final result = <Object?>[];
      for (final line in selected) {
        try {
          result.add(jsonDecode(line));
        } catch (_) {
          result.add({
            'malformed': LauncherLog.redactSensitiveValues(line),
          });
        }
      }
      return result;
    } catch (error) {
      return [
        {
          'readError': LauncherLog.redactSensitiveValues(error.toString()),
        },
      ];
    }
  }

  static void _rotateIfNeededSync(File file) {
    if (!file.existsSync() || file.lengthSync() <= _maximumBytes) return;
    try {
      final retained = file
          .readAsLinesSync()
          .reversed
          .where((line) => line.trim().isNotEmpty)
          .take(_maximumEvents ~/ 2)
          .toList()
          .reversed
          .join('\n');
      file.writeAsStringSync(
        retained.isEmpty ? '' : '$retained\n',
        flush: true,
      );
    } catch (_) {
      try {
        file.writeAsStringSync('', flush: true);
      } catch (_) {}
    }
  }

  static Object? _sanitize(Object? value) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) {
      return LauncherLog.redactSensitiveValues(value);
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _sanitize(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_sanitize).toList(growable: false);
    }
    return LauncherLog.redactSensitiveValues(value.toString());
  }
}
