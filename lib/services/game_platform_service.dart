import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'installation_service.dart';

typedef ExternalUriLauncher = Future<bool> Function(Uri uri);

enum GamePlatform { epicGames, steam, official }

class GamePlatformInfo {
  const GamePlatformInfo({
    required this.platform,
    required this.label,
    required this.launchTarget,
  });

  final GamePlatform platform;
  final String label;
  final String launchTarget;
}

class GamePlatformService {
  GamePlatformService({
    Directory? epicManifestDirectory,
    List<Directory>? steamRoots,
    ExternalUriLauncher? externalUriLauncher,
  }) : _epicManifestDirectory =
           epicManifestDirectory ?? _defaultEpicManifestDirectory(),
       _steamRootsOverride = steamRoots,
       _externalUriLauncher = externalUriLauncher ?? _launchExternalUri;

  final Directory _epicManifestDirectory;
  final List<Directory>? _steamRootsOverride;
  final ExternalUriLauncher _externalUriLauncher;

  Future<GamePlatformInfo> detect(String gameDirectory) async {
    final epic = await _detectEpic(gameDirectory);
    if (epic != null) {
      return epic;
    }

    final steam = await _detectSteam(gameDirectory);
    if (steam != null) {
      return steam;
    }

    return GamePlatformInfo(
      platform: GamePlatform.official,
      label: 'LAUNCHER OFICIAL',
      launchTarget: p.join(gameDirectory, InstallationService.gameExecutable),
    );
  }

  Future<void> launch(GamePlatformInfo info, String gameDirectory) async {
    switch (info.platform) {
      case GamePlatform.epicGames:
      case GamePlatform.steam:
        final launched = await _externalUriLauncher(
          Uri.parse(info.launchTarget),
        );
        if (!launched) {
          throw const GamePlatformException(
            'Não foi possível acionar o cliente da loja.',
          );
        }
      case GamePlatform.official:
        final executable = File(info.launchTarget);
        if (!await executable.exists()) {
          throw const GamePlatformException(
            'NTEGlobalLauncher.exe não foi encontrado.',
          );
        }
        await Process.start(
          executable.path,
          const [],
          workingDirectory: gameDirectory,
          mode: ProcessStartMode.detached,
        );
    }
  }

  Future<GamePlatformInfo?> _detectEpic(String gameDirectory) async {
    if (!await _epicManifestDirectory.exists()) {
      return null;
    }

    await for (final entity in _epicManifestDirectory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.item')) {
        continue;
      }
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final installLocation = _stringValue(json, 'InstallLocation');
        if (!_sameDirectory(installLocation, gameDirectory)) {
          continue;
        }

        final namespace = _stringValue(json, 'CatalogNamespace');
        final catalogItemId = _stringValue(json, 'CatalogItemId');
        final appName = _stringValue(json, 'AppName');
        if (!_safeEpicId(namespace) ||
            !_safeEpicId(catalogItemId) ||
            !_safeEpicId(appName)) {
          throw const GamePlatformException(
            'A instalação da Epic foi encontrada, mas seu manifesto está '
            'incompleto.',
          );
        }

        final product = Uri.encodeComponent(
          '$namespace:$catalogItemId:$appName',
        );
        return GamePlatformInfo(
          platform: GamePlatform.epicGames,
          label: 'EPIC GAMES',
          launchTarget:
              'com.epicgames.launcher://apps/$product'
              '?action=launch&silent=true',
        );
      } on GamePlatformException {
        rethrow;
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }

  Future<GamePlatformInfo?> _detectSteam(String gameDirectory) async {
    final roots = _steamRootsOverride ?? await _discoverSteamRoots();
    for (final root in roots) {
      final steamApps = Directory(p.join(root.path, 'steamapps'));
      if (!await steamApps.exists()) {
        continue;
      }

      await for (final entity in steamApps.list()) {
        final filename = p.basename(entity.path).toLowerCase();
        if (entity is! File ||
            !filename.startsWith('appmanifest_') ||
            !filename.endsWith('.acf')) {
          continue;
        }
        try {
          final contents = await entity.readAsString();
          final appId = _vdfValue(contents, 'appid');
          final installDir = _vdfValue(contents, 'installdir');
          if (!RegExp(r'^\d+$').hasMatch(appId) || installDir.isEmpty) {
            continue;
          }
          final installLocation = p.join(steamApps.path, 'common', installDir);
          if (_sameDirectory(installLocation, gameDirectory)) {
            return GamePlatformInfo(
              platform: GamePlatform.steam,
              label: 'STEAM',
              launchTarget: 'steam://run/$appId',
            );
          }
        } on FileSystemException {
          continue;
        }
      }
    }
    return null;
  }

  Future<List<Directory>> _discoverSteamRoots() async {
    final roots = <String>{};
    final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
    final programFiles = Platform.environment['ProgramFiles'];
    if (programFilesX86 != null) {
      roots.add(p.join(programFilesX86, 'Steam'));
    }
    if (programFiles != null) {
      roots.add(p.join(programFiles, 'Steam'));
    }

    try {
      final result = await Process.run('reg.exe', [
        'query',
        r'HKCU\Software\Valve\Steam',
        '/v',
        'SteamPath',
      ]);
      final match = RegExp(
        r'SteamPath\s+REG_\w+\s+(.+)$',
        multiLine: true,
      ).firstMatch(result.stdout.toString());
      final registryPath = match?.group(1)?.trim();
      if (registryPath != null && registryPath.isNotEmpty) {
        roots.add(registryPath.replaceAll('/', p.separator));
      }
    } on ProcessException {
      // Common locations are still checked if Steam is not in the registry.
    }

    final primaryRoots = roots.map(Directory.new).toList(growable: false);
    final libraries = <String>{...roots};
    for (final root in primaryRoots) {
      final libraryFile = File(
        p.join(root.path, 'steamapps', 'libraryfolders.vdf'),
      );
      if (!await libraryFile.exists()) {
        continue;
      }
      try {
        final contents = await libraryFile.readAsString();
        for (final match in RegExp(
          r'"path"\s+"([^"]+)"',
          caseSensitive: false,
        ).allMatches(contents)) {
          final value = match.group(1);
          if (value != null && value.isNotEmpty) {
            libraries.add(value.replaceAll(r'\\', r'\'));
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return libraries.map(Directory.new).toList(growable: false);
  }

  static Directory _defaultEpicManifestDirectory() {
    final programData =
        Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    return Directory(
      p.join(programData, 'Epic', 'EpicGamesLauncher', 'Data', 'Manifests'),
    );
  }

  static String _stringValue(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is String ? value.trim() : '';
  }

  static String _vdfValue(String contents, String key) {
    return RegExp(
          '"${RegExp.escape(key)}"\\s+"([^"]*)"',
          caseSensitive: false,
        ).firstMatch(contents)?.group(1) ??
        '';
  }

  static bool _sameDirectory(String first, String second) {
    if (first.trim().isEmpty || second.trim().isEmpty) {
      return false;
    }
    String normalize(String value) {
      final normalized = p.normalize(p.absolute(value.trim()));
      return Platform.isWindows ? normalized.toLowerCase() : normalized;
    }

    return normalize(first) == normalize(second);
  }

  static bool _safeEpicId(String value) {
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
  }

  static Future<bool> _launchExternalUri(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class GamePlatformException implements Exception {
  const GamePlatformException(this.message);

  final String message;

  @override
  String toString() => message;
}
