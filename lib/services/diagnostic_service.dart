import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/launcher_log.dart';
import '../models/translation_manifest.dart';
import 'game_platform_service.dart';
import 'installation_service.dart';

typedef _WineGetVersionNative = Pointer<Uint8> Function();
typedef _WineGetVersionDart = Pointer<Uint8> Function();
typedef _WineGetHostVersionNative =
    Void Function(Pointer<Pointer<Uint8>>, Pointer<Pointer<Uint8>>);
typedef _WineGetHostVersionDart =
    void Function(Pointer<Pointer<Uint8>>, Pointer<Pointer<Uint8>>);

class DiagnosticService {
  DiagnosticService({
    required this.paths,
    required this.log,
    required this.installer,
  });

  static const _maxHistoryBytes = 512 * 1024;
  static const _maxEmbeddedLauncherLogBytes = 1024 * 1024;
  static const _maxGameLogBytes = 128 * 1024;
  static const _maxGameLogs = 10;

  final AppPaths paths;
  final LauncherLog log;
  final InstallationService installer;
  Future<void> _pendingHistoryWrite = Future<void>.value();

  Future<void> record(String event, {Map<String, Object?> details = const {}}) {
    _pendingHistoryWrite = _pendingHistoryWrite.then((_) async {
      try {
        await paths.diagnostics.create(recursive: true);
        final entry = jsonEncode({
          'at': DateTime.now().toUtc().toIso8601String(),
          'event': event,
          'details': _redactObject(details),
        });
        final file = paths.diagnosticEventsFile;
        if (await file.exists() && await file.length() > _maxHistoryBytes) {
          final bytes = await _readTailBytes(file, _maxHistoryBytes ~/ 2);
          final firstLine = bytes.indexOf(10);
          final retained = firstLine >= 0
              ? bytes.sublist(firstLine + 1)
              : bytes;
          await file.writeAsBytes(retained, flush: true);
        }
        await file.writeAsString(
          '$entry\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Diagnostics must never prevent the launcher from working.
      }
    });
    return _pendingHistoryWrite;
  }

  Future<File> export({
    required Map<String, Object?> launcherState,
    required String? gameDirectory,
    required GamePlatformInfo? gamePlatform,
    required TranslationManifest? manifest,
  }) async {
    await record(
      'diagnostic_export_requested',
      details: {
        'launcherStatus': launcherState['status'],
        'gameDirectory': gameDirectory,
      },
    );
    await _pendingHistoryWrite;
    await paths.diagnostics.create(recursive: true);

    final createdAt = DateTime.now().toUtc();
    final runtime = await _collectRuntime();
    final game = await _collectGame(gameDirectory, gamePlatform, manifest);
    final payload = <String, Object?>{
      'schemaVersion': 3,
      'reportId': sha256
          .convert(
            utf8.encode(
              '${createdAt.toIso8601String()}|$pid|${runtime['resolvedExecutable']}',
            ),
          )
          .toString()
          .substring(0, 20),
      'createdAt': createdAt.toIso8601String(),
      'privacy': {
        'singleFile': true,
        'description':
            'Relatório autocontido para suporte. Inclui caminhos locais, '
            'metadados técnicos e trechos de logs com segredos conhecidos '
            'suprimidos; não inclui o ambiente completo, senhas ou tokens.',
        'redactionApplied': true,
      },
      'launcher': _redactObject(launcherState),
      'runtime': runtime,
      'game': game,
      'applicationStorage': await _directorySummary(paths.root),
      'lastOfficialLaunchAutomation': await _readJsonFile(
        paths.officialLaunchResultFile,
      ),
      'operationHistory': await _readOperationHistory(),
      'embeddedLogs': {
        'launcher': await log.diagnosticExcerpts(
          maxTotalBytes: _maxEmbeddedLauncherLogBytes,
        ),
        'game': await _collectGameLogs(gameDirectory),
      },
    };

    final temporary = File('${paths.diagnosticFile.path}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
      flush: true,
    );
    if (await paths.diagnosticFile.exists()) {
      await paths.diagnosticFile.delete();
    }
    await temporary.rename(paths.diagnosticFile.path);
    await log.info(
      'Diagnóstico autocontido schema 3 exportado para '
      '${paths.diagnosticFile.path}.',
    );
    return paths.diagnosticFile;
  }

  Future<Map<String, Object?>> _collectRuntime() async {
    final wineRuntime = _detectWineRuntime();
    final wineVersion = wineRuntime['version'] as String?;
    final environment = <String, String>{};
    for (final key in const [
      'WINEPREFIX',
      'WINEARCH',
      'WINELOADERNOEXEC',
      'STEAM_COMPAT_DATA_PATH',
      'STEAM_COMPAT_CLIENT_INSTALL_PATH',
      'STEAM_COMPAT_TOOL_PATHS',
      'SteamAppId',
      'SteamGameId',
      'PROTONPATH',
      'PROTON_VERSION',
      'UMU_ID',
      'GAMEID',
      'XDG_SESSION_TYPE',
      'XDG_CURRENT_DESKTOP',
      'WAYLAND_DISPLAY',
      'DISPLAY',
    ]) {
      final value = Platform.environment[key];
      if (value != null && value.trim().isNotEmpty) {
        environment[key] = LauncherLog.redactSensitiveValues(value.trim());
      }
    }
    final indicators = <String>[
      if (wineVersion != null) 'ntdll.wine_get_version',
      for (final key in environment.keys)
        if (key.contains('WINE') ||
            key.contains('PROTON') ||
            key.startsWith('STEAM_COMPAT'))
          'env:$key',
    ];
    final environmentText = environment.values.join(' ').toLowerCase();
    final compatibilityText = [
      environmentText,
      wineRuntime['version'],
      wineRuntime['buildId'],
    ].whereType<Object>().join(' ').toLowerCase();
    final protonDetected =
        environment.keys.any(
          (key) => key.contains('PROTON') || key.startsWith('STEAM_COMPAT'),
        ) ||
        compatibilityText.contains('proton');
    final dwProtonDetected =
        compatibilityText.contains('dw-proton') ||
        compatibilityText.contains('dwproton');

    return {
      'targetOperatingSystem': Platform.operatingSystem,
      'targetOperatingSystemVersion': LauncherLog.redactSensitiveValues(
        Platform.operatingSystemVersion,
      ),
      'hostLinuxDistribution': await _linuxDistribution(),
      'kernel': await _kernelDescription(),
      'locale': Platform.localeName,
      'numberOfProcessors': Platform.numberOfProcessors,
      'dartVersion': Platform.version,
      'nativeAbi': Abi.current().toString(),
      'pathSeparator': p.separator,
      'executable': LauncherLog.redactSensitiveValues(Platform.executable),
      'resolvedExecutable': LauncherLog.redactSensitiveValues(
        Platform.resolvedExecutable,
      ),
      'processId': pid,
      'wine': {
        ...wineRuntime,
        'detected': wineVersion != null || indicators.isNotEmpty,
        'protonDetected': protonDetected,
        'dwProtonDetected': dwProtonDetected,
        'indicators': indicators,
      },
      'relevantEnvironment': environment,
      'commandAvailability': await _commandAvailability(),
      'relevantProcesses': await _relevantProcesses(),
    };
  }

  Future<Map<String, Object?>> _collectGame(
    String? gameDirectory,
    GamePlatformInfo? gamePlatform,
    TranslationManifest? manifest,
  ) async {
    if (gameDirectory == null) {
      return {
        'selectedDirectory': null,
        'directoryExists': false,
        'platform': gamePlatform?.toDiagnosticJson(),
      };
    }

    final resolution = await installer.resolveGameDirectory(gameDirectory);
    final normalizedDirectory = resolution?.gameDirectory ?? gameDirectory;
    final launcher = await InstallationService.findGameLauncher(
      normalizedDirectory,
    );
    final internalLaunchers = <File>[
      File(p.join(normalizedDirectory, 'NTEGlobal', 'NTEGlobalGame.exe')),
      File(p.join(normalizedDirectory, 'NTE Global', 'NTEGlobalGame.exe')),
      if (launcher != null)
        File(p.join(launcher.parent.path, 'NTEGlobalGame.exe')),
    ];
    final uniqueInternal = <String, File>{
      for (final file in internalLaunchers) p.normalize(file.path): file,
    };
    final htGame = File(
      p.join(
        normalizedDirectory,
        'Client',
        'WindowsNoEditor',
        'HT',
        'Binaries',
        'Win64',
        'HTGame.exe',
      ),
    );
    final receiptRead = await installer.receipts.read(normalizedDirectory);
    final storage = await installer.receipts.storageFor(normalizedDirectory);
    final receipt = receiptRead.receipt;

    return {
      'selectedDirectory': LauncherLog.redactSensitiveValues(gameDirectory),
      'normalizedDirectory': LauncherLog.redactSensitiveValues(
        normalizedDirectory,
      ),
      'directoryExists': await Directory(normalizedDirectory).exists(),
      'directoryWasNormalized': resolution?.wasAdjusted ?? false,
      'installationStorageId': storage.id,
      'platform': gamePlatform?.toDiagnosticJson(),
      'manifest': manifest == null
          ? null
          : {
              'schemaVersion': manifest.schemaVersion,
              'translationVersion': manifest.translationVersion,
              'publishedAt': manifest.publishedAt.toUtc().toIso8601String(),
              'gameBuildId': manifest.gameBuildId,
              'sourceHash': manifest.sourceHash,
              'totalBytes': manifest.totalBytes,
              'files': [
                for (final file in manifest.files)
                  {
                    'name': file.name,
                    'relativeDestination': file.relativeDestination,
                    'size': file.size,
                    'sha256': file.sha256,
                    'urlHost': file.url.host,
                  },
              ],
            },
      'receipt': receipt?.toJson(),
      'receiptError': receiptRead.error?.toString(),
      'temporaryReceiptFound': receiptRead.temporaryReceiptFound,
      'sourceIdentityComparison': {
        'manifestGameBuildId': manifest?.gameBuildId,
        'installedGameBuildId': receipt?.gameBuildId,
        'gameBuildMatches': _equalOptional(
          manifest?.gameBuildId,
          receipt?.gameBuildId,
        ),
        'manifestSourceHash': manifest?.sourceHash,
        'installedSourceHash': receipt?.sourceHash,
        'sourceHashMatches': _equalOptional(
          manifest?.sourceHash,
          receipt?.sourceHash,
        ),
      },
      'executables': {
        'outerLauncher': launcher == null
            ? null
            : await _describeFile(launcher, includeHash: true),
        'internalLaunchers': [
          for (final file in uniqueInternal.values)
            await _describeFile(file, includeHash: true),
        ],
        'gameClient': await _describeFile(htGame),
      },
    };
  }

  Future<List<Map<String, Object?>>> _collectGameLogs(
    String? gameDirectory,
  ) async {
    if (gameDirectory == null || !await Directory(gameDirectory).exists()) {
      return const [];
    }
    final candidates = <File>[];
    for (final launcherDirectory in ['NTEGlobal', 'NTE Global', '']) {
      final root = Directory(
        p.joinAll([
          gameDirectory,
          if (launcherDirectory.isNotEmpty) launcherDirectory,
          'UserData',
          'Log',
        ]),
      );
      for (final name in const [
        'NTEGlobalGame.log',
        'NTEGlobalUpdate.log',
        'NTEGlobalBrowser.log',
        'crash.log',
      ]) {
        candidates.add(File(p.join(root.path, name)));
      }
    }
    candidates.add(
      File(
        p.join(
          gameDirectory,
          'Client',
          'WindowsNoEditor',
          'HT',
          'Binaries',
          'Win64',
          'SigBypasser.log',
        ),
      ),
    );
    candidates.addAll(await _recentCrashLogs(gameDirectory));

    final existing = <File>[];
    final seen = <String>{};
    for (final file in candidates) {
      final normalized = p.normalize(file.path);
      if (seen.add(normalized) && await file.exists()) {
        existing.add(file);
      }
    }
    existing.sort((first, second) {
      try {
        return second.lastModifiedSync().compareTo(first.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });

    final results = <Map<String, Object?>>[];
    for (final file in existing.take(_maxGameLogs)) {
      try {
        final length = await file.length();
        final bytes = await _readTailBytes(file, _maxGameLogBytes);
        results.add({
          'path': LauncherLog.redactSensitiveValues(file.path),
          'size': length,
          'lastModified': (await file.lastModified()).toUtc().toIso8601String(),
          'truncated': bytes.length < length,
          'content': LauncherLog.redactSensitiveValues(
            utf8.decode(bytes, allowMalformed: true),
          ),
        });
      } catch (error) {
        results.add({
          'path': LauncherLog.redactSensitiveValues(file.path),
          'readError': error.toString(),
        });
      }
    }
    return results;
  }

  Future<List<File>> _recentCrashLogs(String gameDirectory) async {
    final root = Directory(
      p.join(gameDirectory, 'Client', 'WindowsNoEditor', 'PxCrashSDK'),
    );
    if (!await root.exists()) return const [];
    final results = <File>[];
    var inspected = 0;
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (++inspected > 1000) break;
        if (entity is File &&
            entity.path.toLowerCase().endsWith('.log') &&
            p.basename(entity.path).toLowerCase().contains('crash')) {
          results.add(entity);
        }
      }
    } catch (_) {
      return results;
    }
    results.sort((first, second) {
      try {
        return second.lastModifiedSync().compareTo(first.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });
    return results.take(3).toList(growable: false);
  }

  Future<Map<String, Object?>> _describeFile(
    File file, {
    bool includeHash = false,
  }) async {
    final result = <String, Object?>{
      'path': LauncherLog.redactSensitiveValues(file.path),
      'exists': await file.exists(),
    };
    if (!await file.exists()) return result;
    try {
      final size = await file.length();
      result['size'] = size;
      result['lastModified'] = (await file.lastModified())
          .toUtc()
          .toIso8601String();
      if (includeHash && size <= 16 * 1024 * 1024) {
        result['sha256'] = sha256.convert(await file.readAsBytes()).toString();
      } else if (includeHash) {
        result['sha256Skipped'] = 'file_larger_than_16_mib';
      }
    } catch (error) {
      result['metadataError'] = error.toString();
    }
    return result;
  }

  Future<Map<String, Object?>> _directorySummary(Directory directory) async {
    if (!await directory.exists()) {
      return {'path': directory.path, 'exists': false};
    }
    var files = 0;
    var directories = 0;
    var bytes = 0;
    var truncated = false;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (files + directories >= 10000) {
          truncated = true;
          break;
        }
        if (entity is Directory) {
          directories++;
        } else if (entity is File) {
          files++;
          try {
            bytes += await entity.length();
          } catch (_) {}
        }
      }
    } catch (error) {
      return {
        'path': LauncherLog.redactSensitiveValues(directory.path),
        'exists': true,
        'scanError': error.toString(),
      };
    }
    return {
      'path': LauncherLog.redactSensitiveValues(directory.path),
      'exists': true,
      'files': files,
      'directories': directories,
      'bytes': bytes,
      'truncated': truncated,
      'logRetentionMaximumBytes': log.maxBytes * (log.retainedFiles + 1),
    };
  }

  Future<List<Object?>> _readOperationHistory() async {
    await _pendingHistoryWrite;
    final file = paths.diagnosticEventsFile;
    if (!await file.exists()) return const [];
    try {
      final bytes = await _readTailBytes(file, _maxHistoryBytes);
      final lines = utf8
          .decode(bytes, allowMalformed: true)
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      final results = <Object?>[];
      for (final line in lines.reversed.take(250).toList().reversed) {
        try {
          results.add(jsonDecode(line));
        } catch (_) {
          results.add({'malformed': LauncherLog.redactSensitiveValues(line)});
        }
      }
      return results;
    } catch (error) {
      return [
        {'readError': error.toString()},
      ];
    }
  }

  Future<Map<String, Object?>?> _readJsonFile(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic>
          ? Map<String, Object?>.from(decoded)
          : {'formatError': 'root_not_object'};
    } catch (error) {
      return {'readError': error.toString(), 'path': file.path};
    }
  }

  Future<Map<String, Object?>> _commandAvailability() async {
    final result = <String, Object?>{};
    for (final command in const [
      'powershell.exe',
      'reg.exe',
      'steam',
      'wine',
      'umu-run',
      'xdotool',
    ]) {
      result[command] = await _commandPath(command);
    }
    return result;
  }

  Future<String?> _commandPath(String command) async {
    try {
      final result = Platform.isWindows
          ? await Process.run('where.exe', [
              command,
            ]).timeout(const Duration(seconds: 2))
          : await Process.run('sh', [
              '-lc',
              'command -v -- "\$1"',
              'nte-diagnostic',
              command,
            ]).timeout(const Duration(seconds: 2));
      if (result.exitCode != 0) return null;
      final first = result.stdout.toString().trim().split('\n').first.trim();
      return first.isEmpty ? null : LauncherLog.redactSensitiveValues(first);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _relevantProcesses() async {
    try {
      final result = Platform.isWindows
          ? await Process.run('tasklist.exe', const ['/FO', 'CSV', '/NH'])
          : await Process.run('ps', const ['-eo', 'pid=,ppid=,comm=,args=']);
      if (result.exitCode != 0) return const [];
      final pattern = RegExp(
        r'nte|htgame|steam|epic|wine|proton|umu|lutris|bottles|ace|anti.?cheat',
        caseSensitive: false,
      );
      return result.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && pattern.hasMatch(line))
          .take(100)
          .map(LauncherLog.redactSensitiveValues)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, String>?> _linuxDistribution() async {
    if (!Platform.isLinux) return null;
    final file = File('/etc/os-release');
    if (!await file.exists()) return null;
    try {
      final values = <String, String>{};
      for (final line in await file.readAsLines()) {
        final separator = line.indexOf('=');
        if (separator <= 0) continue;
        final key = line.substring(0, separator);
        if (!const {'ID', 'VERSION_ID', 'PRETTY_NAME'}.contains(key)) continue;
        values[key] = line
            .substring(separator + 1)
            .replaceAll(RegExp(r'^"|"$'), '');
      }
      return values;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _kernelDescription() async {
    if (!Platform.isLinux) return null;
    try {
      final result = await Process.run('uname', const ['-a']);
      return result.exitCode == 0
          ? LauncherLog.redactSensitiveValues(result.stdout.toString().trim())
          : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _detectWineRuntime() {
    if (!Platform.isWindows) return const {'detected': false};
    try {
      final library = DynamicLibrary.open('ntdll.dll');
      final versionFunction = library
          .lookupFunction<_WineGetVersionNative, _WineGetVersionDart>(
            'wine_get_version',
          );
      final version = _readNativeString(versionFunction());
      String? buildId;
      try {
        final buildFunction = library
            .lookupFunction<_WineGetVersionNative, _WineGetVersionDart>(
              'wine_get_build_id',
            );
        buildId = _readNativeString(buildFunction());
      } catch (_) {}

      String? hostSystem;
      String? hostRelease;
      final systemPointer = calloc<Pointer<Uint8>>();
      final releasePointer = calloc<Pointer<Uint8>>();
      try {
        final hostFunction = library
            .lookupFunction<_WineGetHostVersionNative, _WineGetHostVersionDart>(
              'wine_get_host_version',
            );
        hostFunction(systemPointer, releasePointer);
        hostSystem = _readNativeString(systemPointer.value);
        hostRelease = _readNativeString(releasePointer.value);
      } catch (_) {
        // Older Wine builds may not expose host version details.
      } finally {
        calloc.free(systemPointer);
        calloc.free(releasePointer);
      }

      return {
        'detected': true,
        'version': version,
        'buildId': buildId,
        'hostSystem': hostSystem,
        'hostRelease': hostRelease,
      };
    } catch (_) {
      return const {'detected': false};
    }
  }

  static String? _readNativeString(Pointer<Uint8> pointer) {
    if (pointer == nullptr) return null;
    final bytes = <int>[];
    for (var index = 0; index < 512; index++) {
      final value = pointer[index];
      if (value == 0) break;
      bytes.add(value);
    }
    return bytes.isEmpty ? null : utf8.decode(bytes, allowMalformed: true);
  }

  static Future<List<int>> _readTailBytes(File file, int maximum) async {
    final length = await file.length();
    final readLength = length < maximum ? length : maximum;
    final handle = await file.open();
    try {
      await handle.setPosition(length - readLength);
      return await handle.read(readLength);
    } finally {
      await handle.close();
    }
  }

  static Object? _redactObject(Object? value) {
    if (value is String) return LauncherLog.redactSensitiveValues(value);
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _redactObject(entry.value),
      };
    }
    if (value is Iterable) return value.map(_redactObject).toList();
    return value;
  }

  static bool? _equalOptional(String? expected, String? installed) {
    if (expected == null || installed == null) return null;
    return expected == installed;
  }
}
