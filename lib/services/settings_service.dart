import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _gameDirectoryKey = 'game_directory';
  static const _installedVersionKey = 'installed_version';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<String?> getGameDirectory() =>
      _preferences.getString(_gameDirectoryKey);

  Future<void> setGameDirectory(String value) =>
      _preferences.setString(_gameDirectoryKey, value);

  Future<String?> getInstalledVersion() =>
      _preferences.getString(_installedVersionKey);

  Future<void> setInstalledVersion(String value) =>
      _preferences.setString(_installedVersionKey, value);

  Future<void> clearInstalledVersion() =>
      _preferences.remove(_installedVersionKey);
}
