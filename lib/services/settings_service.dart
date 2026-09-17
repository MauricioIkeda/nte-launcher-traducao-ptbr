import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/launcher_log.dart';

abstract interface class LauncherSettings {
  Future<String?> getGameDirectory();

  Future<void> setGameDirectory(String value);

  Future<String?> getInstalledVersion();

  Future<void> setInstalledVersion(String value);

  Future<void> clearInstalledVersion();

  Future<bool> getAutomaticLauncherUpdates();

  Future<void> setAutomaticLauncherUpdates(bool value);

  Future<bool> getOfficialAutoplay();

  Future<void> setOfficialAutoplay(bool value);

  Future<bool> getOfficialLaunchAutomation();

  Future<void> setOfficialLaunchAutomation(bool value);
}

class SettingsService implements LauncherSettings {
  SettingsService({
    this.log,
    File? preferencesFile,
    DateTime Function()? now,
  }) : _fixedPreferencesFile = preferencesFile,
       _now = now ?? DateTime.now;

  static const _gameDirectoryKey = 'game_directory';
  static const _installedVersionKey = 'installed_version';
  static const _automaticLauncherUpdatesKey = 'automatic_launcher_updates';
  static const _officialAutoplayKey = 'official_autoplay';
  static const _officialLaunchAutomationKey = 'official_launch_automation_v2';
  static const _preferencesFileName = 'shared_preferences.json';

  final LauncherLog? log;
  final File? _fixedPreferencesFile;
  final DateTime Function() _now;

  File? _resolvedPreferencesFile;
  Map<String, Object?>? _cache;
  Future<void> _mutationQueue = Future<void>.value();

  @override
  Future<String?> getGameDirectory() => _getString(_gameDirectoryKey);

  @override
  Future<void> setGameDirectory(String value) =>
      _setValue(_gameDirectoryKey, value);

  @override
  Future<String?> getInstalledVersion() => _getString(_installedVersionKey);

  @override
  Future<void> setInstalledVersion(String value) =>
      _setValue(_installedVersionKey, value);

  @override
  Future<void> clearInstalledVersion() => _remove(_installedVersionKey);

  @override
  Future<bool> getAutomaticLauncherUpdates() async =>
      await _getBool(_automaticLauncherUpdatesKey) ?? false;

  @override
  Future<void> setAutomaticLauncherUpdates(bool value) =>
      _setValue(_automaticLauncherUpdatesKey, value);

  @override
  Future<bool> getOfficialAutoplay() async =>
      await _getBool(_officialAutoplayKey) ?? false;

  @override
  Future<void> setOfficialAutoplay(bool value) =>
      _setValue(_officialAutoplayKey, value);

  @override
  Future<bool> getOfficialLaunchAutomation() async =>
      await _getBool(_officialLaunchAutomationKey) ?? false;

  @override
  Future<void> setOfficialLaunchAutomation(bool value) =>
      _setValue(_officialLaunchAutomationKey, value);

  Future<String?> _getString(String key) async {
    final value = (await _readPreferences())[key];
    return value is String ? value : null;
  }

  Future<bool?> _getBool(String key) async {
    final value = (await _readPreferences())[key];
    return value is bool ? value : null;
  }

  Future<void> _setValue(String key, Object value) {
    return _mutate((preferences) => preferences[key] = value);
  }

  Future<void> _remove(String key) {
    return _mutate((preferences) => preferences.remove(key));
  }

  Future<void> _mutate(
    void Function(Map<String, Object?> preferences) mutation,
  ) {
    final operation = _mutationQueue.then((_) async {
      final preferences = Map<String, Object?>.from(await _readPreferences());
      mutation(preferences);
      await _writePreferences(preferences);
      _cache = preferences;
    });
    _mutationQueue = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<Map<String, Object?>> _readPreferences() async {
    final cached = _cache;
    if (cached != null) return cached;

    final file = await _preferencesFile();
    final backup = File('${file.path}.bak');

    if (!await file.exists() && await backup.exists()) {
      try {
        await backup.rename(file.path);
        await log?.info(
          'Preferências locais restauradas após escrita interrompida.',
        );
      } catch (_) {
        // The normal read below will surface a real filesystem failure if the
        // preference file still cannot be recovered.
      }
    }

    if (!await file.exists()) {
      return _cache = <String, Object?>{};
    }

    try {
      final preferences = await _decodePreferences(file);
      if (await backup.exists()) {
        await backup.delete();
      }
      return _cache = preferences;
    } on FormatException catch (error, stackTrace) {
      if (await backup.exists()) {
        try {
          final recovered = await _decodePreferences(backup);
          await _quarantine(file, 'corrupt');
          await backup.rename(file.path);
          await log?.error(
            'Preferências locais corrompidas; backup íntegro restaurado.',
            error: error,
            stackTrace: stackTrace,
          );
          return _cache = recovered;
        } on FormatException {
          await _quarantine(backup, 'corrupt-backup');
        }
      }

      await _quarantine(file, 'corrupt');
      await log?.error(
        'Preferências locais corrompidas; configurações foram reiniciadas.',
        error: error,
        stackTrace: stackTrace,
      );
      return _cache = <String, Object?>{};
    }
  }

  Future<Map<String, Object?>> _decodePreferences(File file) async {
    final source = await file.readAsString();
    if (source.trim().isEmpty) return <String, Object?>{};

    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'O arquivo de preferências não contém um objeto JSON.',
      );
    }

    final preferences = <String, Object?>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException(
          'O arquivo de preferências contém uma chave inválida.',
        );
      }
      preferences[key] = entry.value;
    }
    return preferences;
  }

  Future<void> _writePreferences(Map<String, Object?> preferences) async {
    final file = await _preferencesFile();
    await file.parent.create(recursive: true);

    final suffix = '$pid.${_now().toUtc().microsecondsSinceEpoch}';
    final temporary = File('${file.path}.tmp.$suffix');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(jsonEncode(preferences), flush: true);

    var previousMoved = false;
    try {
      if (await backup.exists()) {
        await backup.delete();
      }
      if (await file.exists()) {
        await file.rename(backup.path);
        previousMoved = true;
      }
      await temporary.rename(file.path);
      if (previousMoved && await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      if (!await file.exists() && previousMoved && await backup.exists()) {
        try {
          await backup.rename(file.path);
        } catch (_) {
          // Preserve the original exception; the .bak file remains available
          // for recovery on the next launcher start.
        }
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {
          // A stale temporary file is harmless and uniquely named.
        }
      }
    }
  }

  Future<File> _preferencesFile() async {
    final fixed = _fixedPreferencesFile;
    if (fixed != null) return fixed;

    final resolved = _resolvedPreferencesFile;
    if (resolved != null) return resolved;

    final support = await getApplicationSupportDirectory();
    return _resolvedPreferencesFile = File(
      p.join(support.path, _preferencesFileName),
    );
  }

  Future<void> _quarantine(File file, String label) async {
    if (!await file.exists()) return;
    final timestamp = _now().toUtc().microsecondsSinceEpoch;
    final directory = file.parent.path;
    final extension = p.extension(file.path);
    final baseName = p.basenameWithoutExtension(file.path);
    final destination = File(
      p.join(directory, '$baseName.$label-$timestamp$extension'),
    );
    try {
      await file.rename(destination.path);
    } catch (_) {
      // If quarantine itself is blocked, remove the invalid file so the
      // launcher can still recover instead of remaining permanently bricked.
      await file.delete();
    }
  }
}
