import 'package:shared_preferences/shared_preferences.dart';

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
}

class SettingsService implements LauncherSettings {
  static const _gameDirectoryKey = 'game_directory';
  static const _installedVersionKey = 'installed_version';
  static const _automaticLauncherUpdatesKey = 'automatic_launcher_updates';
  static const _officialAutoplayKey = 'official_autoplay';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> getGameDirectory() =>
      _preferences.getString(_gameDirectoryKey);

  @override
  Future<void> setGameDirectory(String value) =>
      _preferences.setString(_gameDirectoryKey, value);

  @override
  Future<String?> getInstalledVersion() =>
      _preferences.getString(_installedVersionKey);

  @override
  Future<void> setInstalledVersion(String value) =>
      _preferences.setString(_installedVersionKey, value);

  @override
  Future<void> clearInstalledVersion() =>
      _preferences.remove(_installedVersionKey);

  @override
  Future<bool> getAutomaticLauncherUpdates() async {
    return await _preferences.getBool(_automaticLauncherUpdatesKey) ?? false;
  }

  @override
  Future<void> setAutomaticLauncherUpdates(bool value) =>
      _preferences.setBool(_automaticLauncherUpdatesKey, value);

  @override
  Future<bool> getOfficialAutoplay() async {
    return await _preferences.getBool(_officialAutoplayKey) ?? true;
  }

  @override
  Future<void> setOfficialAutoplay(bool value) =>
      _preferences.setBool(_officialAutoplayKey, value);
}
