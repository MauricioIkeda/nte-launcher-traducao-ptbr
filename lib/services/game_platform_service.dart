import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../core/launcher_log.dart';
import '../core/runtime_environment.dart';
import 'installation_service.dart';

typedef ExternalUriLauncher = Future<bool> Function(Uri uri);
typedef OfficialLauncherAutomation =
    Future<void> Function(String executable, String gameDirectory);
typedef OfficialLauncherOpener =
    Future<void> Function(String executable, String gameDirectory);
typedef WineRuntimeDetector = bool Function();
typedef DirectHelperStarter =
    Future<void> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );
typedef ElevatedHelperStarter =
    Future<int> Function(Map<String, String> environment);

enum GamePlatform { epicGames, steam, official }

class GamePlatformInfo {
  const GamePlatformInfo({
    required this.platform,
    required this.label,
    required this.launchTarget,
    this.evidence = const {},
  });

  final GamePlatform platform;
  final String label;
  final String launchTarget;
  final Map<String, Object?> evidence;

  Map<String, Object?> toDiagnosticJson() => {
    'id': platform.name,
    'label': label,
    'launchTarget': LauncherLog.redactSensitiveValues(launchTarget),
    'evidence': evidence,
  };
}

class GamePlatformService {
  GamePlatformService({
    Directory? epicManifestDirectory,
    List<Directory>? steamRoots,
    ExternalUriLauncher? externalUriLauncher,
    OfficialLauncherAutomation? officialLauncherAutomation,
    OfficialLauncherOpener? officialLauncherOpener,
  }) : _epicManifestDirectory =
           epicManifestDirectory ?? _defaultEpicManifestDirectory(),
       _steamRootsOverride = steamRoots,
       _externalUriLauncher = externalUriLauncher ?? _launchExternalUri,
       _officialLauncherAutomation =
           officialLauncherAutomation ??
           OfficialLauncherAutomationService().launch,
       _officialLauncherOpener =
           officialLauncherOpener ?? _openOfficialLauncher;

  final Directory _epicManifestDirectory;
  final List<Directory>? _steamRootsOverride;
  final ExternalUriLauncher _externalUriLauncher;
  final OfficialLauncherAutomation _officialLauncherAutomation;
  final OfficialLauncherOpener _officialLauncherOpener;

  Future<GamePlatformInfo> detect(String gameDirectory) async {
    final epic = await _detectEpic(gameDirectory);
    if (epic != null) {
      return epic;
    }

    final steam = await _detectSteam(gameDirectory);
    if (steam != null) {
      return steam;
    }

    final launcher = await InstallationService.findGameLauncher(gameDirectory);
    return GamePlatformInfo(
      platform: GamePlatform.official,
      label: 'LAUNCHER OFICIAL',
      launchTarget:
          launcher?.path ??
          p.join(gameDirectory, InstallationService.gameExecutable),
      evidence: {
        'method': 'official_launcher_fallback',
        'launcherFound': launcher != null,
        'launcherPath': launcher?.path,
        'epicManifestDirectory': _epicManifestDirectory.path,
        'steamRootsOverride': _steamRootsOverride
            ?.map((directory) => directory.path)
            .toList(growable: false),
      },
    );
  }

  Future<void> launch(
    GamePlatformInfo info,
    String gameDirectory, {
    bool automateOfficialPlay = false,
  }) async {
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
        // Never use /autoplay: it can start HTGame before local resources are
        // ready and remove character voices. Manual Play is the conservative
        // default. When explicitly enabled, a runtime-aware helper opens the
        // official launcher normally, waits for its ready marker and presses
        // Play only after preparation. Native Windows uses UAC; Wine/Proton
        // starts the helper directly inside the same prefix.
        if (automateOfficialPlay) {
          await _officialLauncherAutomation(executable.path, gameDirectory);
        } else {
          await _officialLauncherOpener(executable.path, gameDirectory);
        }
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
          evidence: {
            'method': 'epic_item_manifest',
            'manifestPath': entity.path,
            'installLocation': installLocation,
            'catalogNamespace': namespace,
            'catalogItemId': catalogItemId,
            'appName': appName,
          },
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
              evidence: {
                'method': 'steam_appmanifest',
                'manifestPath': entity.path,
                'steamRoot': root.path,
                'appId': appId,
                'installDir': installDir,
                'installLocation': installLocation,
              },
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

  static Future<void> _launchGameExecutable(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) async {
    await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
    );
  }

  static Future<void> _openOfficialLauncher(
    String executable,
    String gameDirectory,
  ) => _launchGameExecutable(executable, const [], gameDirectory);

  static Future<File?> findInternalOfficialLauncher(
    String selectedLauncher,
    String gameDirectory,
  ) async {
    final candidates = <File>[
      File(p.join(gameDirectory, 'NTEGlobal', 'NTEGlobalGame.exe')),
      File(p.join(gameDirectory, 'NTE Global', 'NTEGlobalGame.exe')),
      File(p.join(p.dirname(selectedLauncher), 'NTEGlobalGame.exe')),
    ];
    for (final candidate in candidates) {
      if (await candidate.exists()) {
        return candidate;
      }
    }
    return null;
  }
}

class OfficialLauncherAutomationService {
  OfficialLauncherAutomationService({
    WineRuntimeDetector? wineRuntimeDetector,
    DirectHelperStarter? directHelperStarter,
    ElevatedHelperStarter? elevatedHelperStarter,
    File? resultFile,
    String? helperExecutable,
    this.confirmationTimeout = const Duration(seconds: 5),
  }) : _wineRuntimeDetector =
           wineRuntimeDetector ?? (() => RuntimeEnvironment.isWine),
       _directHelperStarter = directHelperStarter ?? _startDirectHelper,
       _elevatedHelperStarter = elevatedHelperStarter ?? _startElevatedHelper,
       _resultFile = resultFile ?? _defaultResultFile(),
       _helperExecutable = helperExecutable ?? Platform.resolvedExecutable;

  final WineRuntimeDetector _wineRuntimeDetector;
  final DirectHelperStarter _directHelperStarter;
  final ElevatedHelperStarter _elevatedHelperStarter;
  final File _resultFile;
  final String _helperExecutable;
  final Duration confirmationTimeout;

  Future<void> launch(String executable, String gameDirectory) async {
    if (!Platform.isWindows) {
      await GamePlatformService._launchGameExecutable(
        executable,
        const [],
        gameDirectory,
      );
      return;
    }

    final internalLauncher =
        await GamePlatformService.findInternalOfficialLauncher(
          executable,
          gameDirectory,
        );
    if (internalLauncher == null) {
      await GamePlatformService._launchGameExecutable(
        executable,
        const [],
        gameDirectory,
      );
      return;
    }
    final logFile = File(
      p.join(
        internalLauncher.parent.path,
        'UserData',
        'Log',
        'NTEGlobalGame.log',
      ),
    );
    final attemptId =
        '${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16)}-'
        '${pid.toRadixString(16)}';
    final arguments = [
      '--official-ready-play',
      '--automation-id=$attemptId',
      '--official-launcher-hex=${_hexUtf8(executable)}',
      '--internal-launcher-hex=${_hexUtf8(internalLauncher.path)}',
      '--official-log-hex=${_hexUtf8(logFile.path)}',
    ];

    await _resultFile.parent.create(recursive: true);
    if (await _resultFile.exists()) {
      await _resultFile.delete();
    }

    if (_wineRuntimeDetector()) {
      await _directHelperStarter(
        _helperExecutable,
        arguments,
        p.dirname(_helperExecutable),
      );
    } else {
      final exitCode = await _elevatedHelperStarter({
        ...Platform.environment,
        'NTE_TRANSLATION_LAUNCHER': _helperExecutable,
        'NTE_AUTOMATION_ID': attemptId,
        'NTE_OFFICIAL_LAUNCHER_HEX': _hexUtf8(executable),
        'NTE_INTERNAL_LAUNCHER_HEX': _hexUtf8(internalLauncher.path),
        'NTE_OFFICIAL_LOG_HEX': _hexUtf8(logFile.path),
      });
      if (exitCode != 0) {
        throw const GamePlatformException(
          'A permissão para abrir o launcher oficial foi cancelada ou '
          'recusada.',
        );
      }
    }

    await _confirmHelperStarted(attemptId);
  }

  Future<void> _confirmHelperStarted(String attemptId) async {
    final deadline = DateTime.now().add(confirmationTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _resultFile.exists()) {
        try {
          final decoded = jsonDecode(await _resultFile.readAsString());
          if (decoded is Map<String, dynamic>) {
            if (decoded['attemptId'] != attemptId) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              continue;
            }
            final stage = decoded['stage'];
            final exitCode = decoded['exitCode'];
            if (stage is String && stage.isNotEmpty) {
              if (exitCode is int && exitCode >= 10) {
                throw GamePlatformException(_failureMessage(exitCode, stage));
              }
              return;
            }
          }
        } on FormatException {
          // The native helper may be replacing the tiny JSON file right now.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const GamePlatformException(
      'O componente de Play automático não confirmou a inicialização. '
      'O launcher permanecerá aberto para permitir o diagnóstico.',
    );
  }

  static String _failureMessage(int exitCode, String stage) =>
      switch (exitCode) {
        10 => 'Os caminhos usados pelo Play automático foram rejeitados.',
        11 => 'O launcher oficial não pôde ser iniciado automaticamente.',
        12 => 'O launcher oficial não ficou pronto dentro do tempo limite.',
        13 => 'O botão Jogar do launcher oficial não pôde ser acionado.',
        14 => 'O launcher oficial recebeu o comando, mas o jogo não iniciou.',
        15 => 'Já existe uma tentativa de Play automático em andamento.',
        16 => 'O Play automático não conseguiu criar seu controle de execução.',
        _ => 'O Play automático falhou na etapa $stage (código $exitCode).',
      };

  static Future<void> _startDirectHelper(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) async {
    await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
    );
  }

  static Future<int> _startElevatedHelper(
    Map<String, String> environment,
  ) async {
    final result = await Process.run(
      'powershell.exe',
      const [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference='Stop'; $helperArgs='--official-ready-play --automation-id=' + $env:NTE_AUTOMATION_ID + ' --official-launcher-hex=' + $env:NTE_OFFICIAL_LAUNCHER_HEX + ' --internal-launcher-hex=' + $env:NTE_INTERNAL_LAUNCHER_HEX + ' --official-log-hex=' + $env:NTE_OFFICIAL_LOG_HEX; Start-Process -FilePath $env:NTE_TRANSLATION_LAUNCHER -ArgumentList $helperArgs -Verb RunAs -WindowStyle Hidden",
      ],
      environment: environment,
      runInShell: false,
    );
    return result.exitCode;
  }

  static File _defaultResultFile() => File(
    p.join(
      Directory.systemTemp.path,
      'NTE-Translation-Launcher',
      'official-launch-result.json',
    ),
  );

  static String _hexUtf8(String value) => utf8
      .encode(value)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

class GamePlatformException implements Exception {
  const GamePlatformException(this.message);

  final String message;

  @override
  String toString() => message;
}
