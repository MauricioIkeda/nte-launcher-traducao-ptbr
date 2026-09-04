import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/launcher_log.dart';
import '../core/runtime_environment.dart';
import '../models/install_receipt.dart';
import '../models/translation_manifest.dart';
import 'game_platform_service.dart';
import 'installation_service.dart';

class DiagnosticService {
  DiagnosticService({
    required this.paths,
    required this.log,
    required this.installer,
  });

  static const _maxHistoryBytes = 512 * 1024;
  static const _maxEmbeddedLauncherLogBytes = 1024 * 1024;
  static const _maxGameLogBytes = 128 * 1024;
  static const _maxHtLogScanBytes = 512 * 1024;
  static const _maxSigLogScanBytes = 256 * 1024;
  static const _maxGameLogs = 14;
  static const _maxManagedInstallations = 50;
  static const _maxInventoryEntries = 250;
  static const _maxModCandidateHashBytes = 32 * 1024 * 1024;

  static const _knownProxyDlls = <String>{
    'version.dll',
    'winmm.dll',
    'dsound.dll',
    'dinput8.dll',
    'xinput1_3.dll',
    'xinput9_1_0.dll',
    'dxgi.dll',
    'd3d11.dll',
    'd3d12.dll',
  };

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
    final operationHistory = await _readOperationHistory();
    final runtime = await _collectRuntime();
    final game = await _collectGame(
      gameDirectory,
      gamePlatform,
      manifest,
      operationHistory,
    );
    final payload = <String, Object?>{
      'schemaVersion': 4,
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
            'metadados técnicos, inventário limitado de possíveis mods e '
            'trechos filtrados de logs com segredos conhecidos suprimidos; '
            'não inclui o ambiente completo, senhas ou tokens.',
        'redactionApplied': true,
      },
      'diagnosticCapabilities': {
        'runtimeLoaderEvidence': true,
        'loadedModuleInspection': Platform.isWindows,
        'fullGameClientSha256': true,
        'foreignModInventory': true,
        'languageConfigurationInspection': true,
        'privilegeAndUacInspection': Platform.isWindows,
        'wineProtonInspection': true,
        'startupInterruptionAnalysis': true,
        'filteredUnrealLogInspection': true,
      },
      'launcher': _redactObject(launcherState),
      'startupHealth': _analyzeStartupHistory(operationHistory),
      'runtime': runtime,
      'game': game,
      'applicationStorage': await _directorySummary(paths.root),
      'storageState': await _collectStorageState(gameDirectory),
      'managedInstallations': await _collectManagedInstallations(gameDirectory),
      'lastOfficialLaunchAutomation': await _readJsonFile(
        paths.officialLaunchResultFile,
      ),
      'operationHistory': operationHistory,
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
      'Diagnóstico autocontido schema 4 exportado para '
      '${paths.diagnosticFile.path}.',
    );
    return paths.diagnosticFile;
  }

  Future<Map<String, Object?>> _collectRuntime() async {
    final wineRuntime = RuntimeEnvironment.detectWine().toJson();
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
      'GDK_BACKEND',
      'GDK_SCALE',
      'QT_QPA_PLATFORM',
      'QT_SCALE_FACTOR',
      'DXVK_LOG_LEVEL',
      'VKD3D_DEBUG',
      'MANGOHUD',
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
      'privilege': await _privilegeState(),
      'uacPolicy': await _uacPolicy(),
      'systemResources': await _systemResources(),
      'graphics': await _graphicsInfo(),
      'securityProducts': await _securityProducts(),
      'relevantEnvironment': environment,
      'commandAvailability': await _commandAvailability(),
      'relevantProcesses': await _relevantProcesses(),
    };
  }

  Future<Map<String, Object?>> _collectGame(
    String? gameDirectory,
    GamePlatformInfo? gamePlatform,
    TranslationManifest? manifest,
    List<Object?> operationHistory,
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
      'pathEnvironment': await _pathEnvironment(normalizedDirectory),
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
        'note':
            'Compara o manifesto com o recibo instalado; não representa, por '
            'si só, o build real atualmente executado pelo jogo.',
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
        'gameClient': await _describeFile(
          htGame,
          includeHash: true,
          hashLimitBytes: null,
        ),
      },
      'languageConfiguration': await _languageConfiguration(receipt),
      'translationRuntime': await _translationRuntime(
        normalizedDirectory,
        operationHistory,
      ),
      'modAndLoaderInventory': await _modAndLoaderInventory(
        normalizedDirectory,
        manifest,
      ),
      'installationStorage': {
        'root': await _directorySummary(storage.root),
        'originals': await _directorySummary(storage.originals),
        'transactions': await _directorySummary(storage.transactions),
      },
    };
  }

  Future<Map<String, Object?>> _pathEnvironment(String gameDirectory) async {
    final lower = gameDirectory.toLowerCase();
    return {
      'underProgramFiles':
          Platform.isWindows &&
          (lower.contains(r'\program files\') ||
              lower.contains(r'\program files (x86)\')),
      'pathLength': gameDirectory.length,
      'storage': await _pathStorage(gameDirectory),
      'directoryStat': await _describeDirectory(Directory(gameDirectory)),
    };
  }

  Future<Map<String, Object?>> _translationRuntime(
    String gameDirectory,
    List<Object?> operationHistory,
  ) async {
    final win64 = p.join(
      gameDirectory,
      'Client',
      'WindowsNoEditor',
      'HT',
      'Binaries',
      'Win64',
    );
    final sigLog = File(p.join(win64, 'SigBypasser.log'));
    final lastLaunch = _latestEventTime(
      operationHistory,
      'game_launch_started',
    );
    final lastDispatch = _latestEventTime(
      operationHistory,
      'game_launch_dispatched',
    );
    final logDescription = await _describeFile(sigLog);
    String content = '';
    if (await sigLog.exists()) {
      try {
        final bytes = await _readTailBytes(sigLog, _maxSigLogScanBytes);
        content = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {}
    }
    final allMarkers = _sigMarkers(content);
    final recentMarkers = _sigMarkers(content, sinceUtc: lastLaunch);
    final lastModified = _dateFromObject(logDescription['lastModified']);
    final changedAfterLaunch = lastLaunch == null || lastModified == null
        ? null
        : !lastModified.isBefore(
            lastLaunch.subtract(const Duration(seconds: 2)),
          );

    String status;
    if (lastLaunch == null) {
      status = 'no_recorded_launch';
    } else if (!await sigLog.exists()) {
      status = 'sig_log_missing';
    } else if (changedAfterLaunch == false) {
      status = 'stale_after_last_launch';
    } else if ((recentMarkers['patchApplied'] as int) > 0) {
      status = 'patch_applied_after_last_launch';
    } else if ((recentMarkers['loaderLoaded'] as int) > 0 &&
        (recentMarkers['patternNotFound'] as int) > 0) {
      status = 'loader_started_but_patch_failed_after_last_launch';
    } else if ((recentMarkers['loaderLoaded'] as int) > 0) {
      status = 'loader_started_after_last_launch';
    } else if (changedAfterLaunch == true) {
      status = 'log_changed_without_recognized_loader_event';
    } else {
      status = 'unknown';
    }

    return {
      'derivedStatus': status,
      'lastRecordedLaunchAt': lastLaunch?.toIso8601String(),
      'lastRecordedDispatchAt': lastDispatch?.toIso8601String(),
      'sigBypasserLog': logDescription,
      'sigLogChangedAfterLastLaunch': changedAfterLaunch,
      'allObservedMarkersInTail': allMarkers,
      'markersAtOrAfterLastLaunch': recentMarkers,
      'currentlyLoadedModules': await _loadedModuleEvidence(),
      'loaderFiles': {
        'versionDll': await _describeFile(
          File(p.join(win64, 'version.dll')),
          includeHash: true,
        ),
        'universalSigBypasser': await _describeFile(
          File(p.join(win64, 'UniversalSigBypasser.asi')),
          includeHash: true,
        ),
      },
    };
  }

  Map<String, Object?> _sigMarkers(String content, {DateTime? sinceUtc}) {
    var loaderLoaded = 0;
    var patternFound = 0;
    var patchApplied = 0;
    var patternNotFound = 0;
    String? lastRelevantLine;
    DateTime? lastRelevantAt;

    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final timestamp = _sigTimestamp(line);
      if (sinceUtc != null) {
        if (timestamp == null ||
            timestamp.isBefore(sinceUtc.subtract(const Duration(seconds: 5)))) {
          continue;
        }
      }
      final lower = line.toLowerCase();
      var relevant = false;
      if (lower.contains('universalsigbypasser loaded')) {
        loaderLoaded++;
        relevant = true;
      }
      if (lower.contains('pattern ') && lower.contains(' found')) {
        patternFound++;
        relevant = true;
      }
      if (lower.contains('patch applied')) {
        patchApplied++;
        relevant = true;
      }
      if (lower.contains('pattern not found')) {
        patternNotFound++;
        relevant = true;
      }
      if (relevant) {
        lastRelevantLine = LauncherLog.redactSensitiveValues(line);
        lastRelevantAt = timestamp;
      }
    }
    return {
      'loaderLoaded': loaderLoaded,
      'patternFound': patternFound,
      'patchApplied': patchApplied,
      'patternNotFound': patternNotFound,
      'lastRelevantLine': lastRelevantLine,
      'lastRelevantAt': lastRelevantAt?.toIso8601String(),
    };
  }

  DateTime? _sigTimestamp(String line) {
    final match = RegExp(
      r'^\[(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2}(?:\.\d+)?)\]',
    ).firstMatch(line);
    if (match == null) return null;
    final local = DateTime.tryParse('${match.group(1)}T${match.group(2)}');
    return local?.toUtc();
  }

  Future<Map<String, Object?>> _loadedModuleEvidence() async {
    if (!Platform.isWindows) {
      return {'supported': false, 'reason': 'module_snapshot_is_windows_only'};
    }
    try {
      final result = await Process.run('tasklist.exe', const [
        '/FI',
        'IMAGENAME eq HTGame.exe',
        '/M',
        '/FO',
        'CSV',
        '/NH',
      ]).timeout(const Duration(seconds: 4));
      final output = LauncherLog.redactSensitiveValues(
        result.stdout.toString().trim(),
      );
      final error = LauncherLog.redactSensitiveValues(
        result.stderr.toString().trim(),
      );
      final lower = output.toLowerCase();
      final running = lower.contains('htgame.exe');
      return {
        'supported': true,
        'queryExitCode': result.exitCode,
        'htGameRunning': running,
        'versionDllLoaded': running && lower.contains('version.dll'),
        'universalSigBypasserLoaded':
            running && lower.contains('universalsigbypasser.asi'),
        'raw': output.length <= 32768 ? output : output.substring(0, 32768),
        if (error.isNotEmpty) 'stderr': error,
      };
    } catch (error) {
      return {'supported': true, 'queryError': error.toString()};
    }
  }

  Future<Map<String, Object?>> _modAndLoaderInventory(
    String gameDirectory,
    TranslationManifest? manifest,
  ) async {
    final managed = <String>{
      if (manifest != null)
        for (final file in manifest.files)
          p.normalize(file.relativeDestination).toLowerCase(),
    };
    final win64 = Directory(
      p.join(
        gameDirectory,
        'Client',
        'WindowsNoEditor',
        'HT',
        'Binaries',
        'Win64',
      ),
    );
    final paks = Directory(
      p.join(
        gameDirectory,
        'Client',
        'WindowsNoEditor',
        'HT',
        'Content',
        'Paks',
      ),
    );

    final loaderCandidates = <Map<String, Object?>>[];
    if (await win64.exists()) {
      try {
        await for (final entity in win64.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path).toLowerCase();
          if (!name.endsWith('.asi') && !_knownProxyDlls.contains(name)) {
            continue;
          }
          final relative = p.normalize(
            p.relative(entity.path, from: gameDirectory),
          );
          final isManaged = managed.contains(relative.toLowerCase());
          loaderCandidates.add({
            'relativePath': relative,
            'managedByCurrentManifest': isManaged,
            'potentialForeignLoader': !isManaged,
            ...await _describeFile(
              entity,
              includeHash: true,
              hashLimitBytes: _maxModCandidateHashBytes,
              includePath: false,
            ),
          });
          if (loaderCandidates.length >= _maxInventoryEntries) break;
        }
      } catch (error) {
        loaderCandidates.add({'scanError': error.toString()});
      }
    }

    final containerCandidates = <Map<String, Object?>>[];
    final extensionCounts = <String, int>{};
    var inspectedContainers = 0;
    var truncated = false;
    final roots = <Directory>[
      paks,
      Directory(p.join(paks.path, '~mods')),
      Directory(p.join(paks.path, 'Mods')),
      Directory(p.join(paks.path, 'LogicMods')),
    ];
    final seenRoots = <String>{};
    for (final root in roots) {
      final normalizedRoot = p.normalize(root.path).toLowerCase();
      if (!seenRoots.add(normalizedRoot) || !await root.exists()) continue;
      try {
        await for (final entity in root.list(followLinks: false)) {
          if (entity is! File) continue;
          final extension = p.extension(entity.path).toLowerCase();
          if (!const {'.pak', '.utoc', '.ucas', '.sig'}.contains(extension)) {
            continue;
          }
          inspectedContainers++;
          extensionCounts[extension] = (extensionCounts[extension] ?? 0) + 1;
          final relative = p.normalize(
            p.relative(entity.path, from: gameDirectory),
          );
          final lowerRelative = relative.toLowerCase();
          final name = p.basename(entity.path).toLowerCase();
          final isManaged = managed.contains(lowerRelative);
          final inModDirectory =
              normalizedRoot != p.normalize(paks.path).toLowerCase();
          final highPriority = name.contains('_p.');
          final nameLooksModded = RegExp(
            r'pt.?br|portugu|trad|localiz|mod|pakchunk999',
            caseSensitive: false,
          ).hasMatch(name);
          if (!isManaged &&
              !inModDirectory &&
              !highPriority &&
              !nameLooksModded) {
            continue;
          }
          containerCandidates.add({
            'relativePath': relative,
            'managedByCurrentManifest': isManaged,
            'insideKnownModDirectory': inModDirectory,
            'highPriorityContainer': highPriority,
            'potentialForeignContainer': !isManaged,
            ...await _describeFile(
              entity,
              includeHash: true,
              hashLimitBytes: _maxModCandidateHashBytes,
              includePath: false,
            ),
          });
          if (containerCandidates.length >= _maxInventoryEntries) {
            truncated = true;
            break;
          }
        }
      } catch (error) {
        containerCandidates.add({
          'root': LauncherLog.redactSensitiveValues(root.path),
          'scanError': error.toString(),
        });
      }
      if (truncated) break;
    }

    final modDirectories = <Map<String, Object?>>[];
    for (final directory in roots.skip(1)) {
      if (await directory.exists()) {
        modDirectories.add(await _directorySummary(directory));
      }
    }

    return {
      'loaderCandidates': loaderCandidates,
      'foreignLoaderCandidateCount': loaderCandidates
          .where((entry) => entry['potentialForeignLoader'] == true)
          .length,
      'containerSummary': {
        'inspected': inspectedContainers,
        'extensionCounts': extensionCounts,
        'candidateListTruncated': truncated,
      },
      'containerCandidates': containerCandidates,
      'foreignContainerCandidateCount': containerCandidates
          .where((entry) => entry['potentialForeignContainer'] == true)
          .length,
      'knownModDirectories': modDirectories,
    };
  }

  Future<Map<String, Object?>> _languageConfiguration(
    InstallReceipt? receipt,
  ) async {
    final language = receipt?.textLanguage;
    if (language == null) {
      return {'receiptHasTextLanguage': false};
    }
    final file = File(language.configPath);
    final result = <String, Object?>{
      'receiptHasTextLanguage': true,
      'key': language.key,
      'requestedCulture': language.requestedCulture,
      'file': await _describeFile(file),
    };
    if (!await file.exists()) return result;
    try {
      if (await file.length() > 2 * 1024 * 1024) {
        result['readSkipped'] = 'file_larger_than_2_mib';
        return result;
      }
      final source = await file.readAsString();
      final match = RegExp(
        '^${RegExp.escape(language.key)}=(.*)\$',
        multiLine: true,
      ).firstMatch(source);
      final raw = match?.group(1)?.trim();
      result['keyPresent'] = raw != null;
      if (raw != null) {
        result['currentRawValue'] = LauncherLog.redactSensitiveValues(raw);
        final cultures = <String, String>{};
        for (final entry in const [
          'globalLanguage',
          'globalLocale',
          'gameLanguage',
        ]) {
          final culture = RegExp(
            '"${RegExp.escape(entry)}"\\s*:\\s*"([^"]+)"',
          ).firstMatch(raw)?.group(1);
          if (culture != null) cultures[entry] = culture;
        }
        result['parsedCultures'] = cultures;
      }
    } catch (error) {
      result['readError'] = error.toString();
    }
    return result;
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
    results.addAll(await _filteredUnrealLogs());
    return results.take(_maxGameLogs).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> _filteredUnrealLogs() async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.trim().isEmpty) return const [];
    final root = Directory(p.join(localAppData, 'HT', 'Saved_Global', 'Logs'));
    if (!await root.exists()) return const [];
    final files = <File>[];
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.log')) {
          files.add(entity);
        }
      }
    } catch (_) {
      return const [];
    }
    files.sort((first, second) {
      try {
        return second.lastModifiedSync().compareTo(first.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });
    final relevant = RegExp(
      r'sigbypass|pakchunk999|logpak|iostore|mount|culture|localiz|'
      r'internationalization|version\.dll|\.asi|mod|error|warning|failed',
      caseSensitive: false,
    );
    final results = <Map<String, Object?>>[];
    for (final file in files.take(3)) {
      try {
        final length = await file.length();
        final bytes = await _readTailBytes(file, _maxHtLogScanBytes);
        final lines = utf8
            .decode(bytes, allowMalformed: true)
            .split('\n')
            .where((line) => relevant.hasMatch(line))
            .take(400)
            .map(LauncherLog.redactSensitiveValues)
            .join('\n');
        results.add({
          'path': LauncherLog.redactSensitiveValues(file.path),
          'size': length,
          'lastModified': (await file.lastModified()).toUtc().toIso8601String(),
          'filtered': true,
          'filter':
              'loader, pak/iostore, mount, culture/localization, mod, '
              'error/warning/failure',
          'content': lines,
        });
      } catch (error) {
        results.add({
          'path': LauncherLog.redactSensitiveValues(file.path),
          'filtered': true,
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
    int? hashLimitBytes = 16 * 1024 * 1024,
    bool includePath = true,
  }) async {
    final exists = await file.exists();
    final result = <String, Object?>{
      if (includePath) 'path': LauncherLog.redactSensitiveValues(file.path),
      'exists': exists,
    };
    if (!exists) return result;
    try {
      final stat = await file.stat();
      final size = stat.size;
      result['size'] = size;
      result['lastModified'] = stat.modified.toUtc().toIso8601String();
      result['lastChanged'] = stat.changed.toUtc().toIso8601String();
      result['mode'] = stat.mode;
      if (includeHash && (hashLimitBytes == null || size <= hashLimitBytes)) {
        result['sha256'] = (await sha256.bind(file.openRead()).first)
            .toString();
      } else if (includeHash) {
        result['sha256Skipped'] = 'file_larger_than_${hashLimitBytes}_bytes';
      }
    } catch (error) {
      result['metadataError'] = error.toString();
    }
    return result;
  }

  Future<Map<String, Object?>> _describeDirectory(Directory directory) async {
    final exists = await directory.exists();
    final result = <String, Object?>{
      'path': LauncherLog.redactSensitiveValues(directory.path),
      'exists': exists,
    };
    if (!exists) return result;
    try {
      final stat = await directory.stat();
      result['lastModified'] = stat.modified.toUtc().toIso8601String();
      result['lastChanged'] = stat.changed.toUtc().toIso8601String();
      result['mode'] = stat.mode;
    } catch (error) {
      result['metadataError'] = error.toString();
    }
    return result;
  }

  Future<Map<String, Object?>> _directorySummary(Directory directory) async {
    if (!await directory.exists()) {
      return {
        'path': LauncherLog.redactSensitiveValues(directory.path),
        'exists': false,
      };
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
      'logRetentionMaximumBytes':
          p.normalize(directory.path) == p.normalize(paths.root.path)
          ? log.maxBytes * (log.retainedFiles + 1)
          : null,
    };
  }

  Future<Map<String, Object?>> _collectStorageState(
    String? gameDirectory,
  ) async {
    final result = <String, Object?>{
      'cache': await _directorySummary(paths.cache),
      'downloads': await _directorySummary(paths.downloads),
      'legacyTransactions': await _directorySummary(paths.transactions),
      'installations': await _directorySummary(paths.installations),
      'diagnostics': await _directorySummary(paths.diagnostics),
    };
    if (gameDirectory != null) {
      try {
        final storage = await installer.receipts.storageFor(gameDirectory);
        result['selectedInstallation'] = {
          'id': storage.id,
          'root': await _directorySummary(storage.root),
          'originals': await _directorySummary(storage.originals),
          'transactions': await _directorySummary(storage.transactions),
          'receipt': await _describeFile(storage.receipt),
          'temporaryReceipt': await _describeFile(
            File('${storage.receipt.path}.tmp'),
          ),
          'previousReceipt': await _describeFile(
            File('${storage.receipt.path}.previous'),
          ),
        };
      } catch (error) {
        result['selectedInstallationError'] = error.toString();
      }
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _collectManagedInstallations(
    String? selectedGameDirectory,
  ) async {
    if (!await paths.installations.exists()) return const [];
    String? selectedId;
    if (selectedGameDirectory != null) {
      try {
        selectedId = (await installer.receipts.storageFor(
          selectedGameDirectory,
        )).id;
      } catch (_) {}
    }
    final results = <Map<String, Object?>>[];
    try {
      await for (final entity in paths.installations.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final id = p.basename(entity.path);
        final receiptFile = File(p.join(entity.path, 'receipt.json'));
        final entry = <String, Object?>{
          'storageId': id,
          'selected': selectedId == id,
          'root': LauncherLog.redactSensitiveValues(entity.path),
          'receiptExists': await receiptFile.exists(),
        };
        if (await receiptFile.exists()) {
          try {
            final decoded = jsonDecode(await receiptFile.readAsString());
            if (decoded is Map<String, dynamic>) {
              entry['translationVersion'] = decoded['translationVersion'];
              entry['installedAt'] = decoded['installedAt'];
              entry['gameDirectory'] = _redactObject(decoded['gameDirectory']);
              final files = decoded['files'];
              entry['managedFiles'] = files is List ? files.length : null;
            } else {
              entry['receiptError'] = 'root_not_object';
            }
          } catch (error) {
            entry['receiptError'] = error.toString();
          }
        }
        results.add(entry);
        if (results.length >= _maxManagedInstallations) break;
      }
    } catch (error) {
      results.add({'scanError': error.toString()});
    }
    return results;
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

  Map<String, Object?> _analyzeStartupHistory(List<Object?> history) {
    final sessions = <Map<String, Object?>>[];
    Map<String, Object?>? active;
    for (final item in history) {
      if (item is! Map) continue;
      final event = item['event']?.toString();
      final at = DateTime.tryParse(item['at']?.toString() ?? '')?.toUtc();
      if (event == 'launcher_initialize_started') {
        if (active != null) {
          active['interruptedByNewInitialization'] = true;
          sessions.add(active);
        }
        active = {'startedAt': at?.toIso8601String(), 'completed': false};
      } else if (event == 'launcher_initialize_completed' && active != null) {
        active['completed'] = true;
        active['completedAt'] = at?.toIso8601String();
        final started = DateTime.tryParse(
          active['startedAt']?.toString() ?? '',
        );
        if (started != null && at != null) {
          active['durationMs'] = at.difference(started).inMilliseconds;
        }
        final details = item['details'];
        if (details is Map) {
          active['verification'] = details['verification'];
          active['manifestSource'] = details['manifestSource'];
        }
        sessions.add(active);
        active = null;
      }
    }
    if (active != null) {
      active['completed'] = false;
      active['stillIncompleteAtDiagnostic'] = true;
      sessions.add(active);
    }
    final recent = sessions.reversed.take(10).toList().reversed.toList();
    return {
      'recentInitializations': recent,
      'incompleteCount': recent
          .where((entry) => entry['completed'] != true)
          .length,
      'hasRecentInterruptedInitialization': recent.any(
        (entry) => entry['interruptedByNewInitialization'] == true,
      ),
      'lastHistoryEvent': history.isEmpty ? null : history.last,
    };
  }

  DateTime? _latestEventTime(List<Object?> history, String eventName) {
    for (final item in history.reversed) {
      if (item is! Map || item['event']?.toString() != eventName) continue;
      return DateTime.tryParse(item['at']?.toString() ?? '')?.toUtc();
    }
    return null;
  }

  Future<Map<String, Object?>?> _readJsonFile(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic>
          ? Map<String, Object?>.from(decoded)
          : {'formatError': 'root_not_object'};
    } catch (error) {
      return {
        'readError': error.toString(),
        'path': LauncherLog.redactSensitiveValues(file.path),
      };
    }
  }

  Future<Map<String, Object?>> _commandAvailability() async {
    final result = <String, Object?>{};
    for (final command in const [
      'powershell.exe',
      'reg.exe',
      'tasklist.exe',
      'whoami.exe',
      'steam',
      'wine',
      'wineserver',
      'umu-run',
      'xdotool',
      'lspci',
      'vulkaninfo',
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

  Future<Map<String, Object?>> _privilegeState() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('whoami.exe', const [
          '/groups',
          '/FO',
          'CSV',
          '/NH',
        ]).timeout(const Duration(seconds: 3));
        final text = result.stdout.toString();
        String integrity = 'unknown';
        if (text.contains('S-1-16-16384')) {
          integrity = 'system';
        } else if (text.contains('S-1-16-12288')) {
          integrity = 'high';
        } else if (text.contains('S-1-16-8192')) {
          integrity = 'medium';
        } else if (text.contains('S-1-16-4096')) {
          integrity = 'low';
        }
        return {
          'queryExitCode': result.exitCode,
          'integrityLevel': integrity,
          'elevated': integrity == 'high' || integrity == 'system',
        };
      } catch (error) {
        return {'queryError': error.toString()};
      }
    }
    if (Platform.isLinux) {
      try {
        final uid = await Process.run('id', const [
          '-u',
        ]).timeout(const Duration(seconds: 2));
        final gid = await Process.run('id', const [
          '-g',
        ]).timeout(const Duration(seconds: 2));
        final uidText = uid.stdout.toString().trim();
        return {
          'uid': int.tryParse(uidText),
          'gid': int.tryParse(gid.stdout.toString().trim()),
          'root': uidText == '0',
        };
      } catch (error) {
        return {'queryError': error.toString()};
      }
    }
    return {'supported': false};
  }

  Future<Map<String, Object?>?> _uacPolicy() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run('reg.exe', const [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
      ]).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) {
        return {
          'queryExitCode': result.exitCode,
          'stderr': LauncherLog.redactSensitiveValues(
            result.stderr.toString().trim(),
          ),
        };
      }
      final text = result.stdout.toString();
      int? value(String name) {
        final match = RegExp(
          '${RegExp.escape(name)}\\s+REG_DWORD\\s+0x([0-9a-fA-F]+)',
        ).firstMatch(text);
        return match == null ? null : int.tryParse(match.group(1)!, radix: 16);
      }

      return {
        'enableLUA': value('EnableLUA'),
        'consentPromptBehaviorAdmin': value('ConsentPromptBehaviorAdmin'),
        'promptOnSecureDesktop': value('PromptOnSecureDesktop'),
        'filterAdministratorToken': value('FilterAdministratorToken'),
      };
    } catch (error) {
      return {'queryError': error.toString()};
    }
  }

  Future<Map<String, Object?>?> _systemResources() async {
    if (Platform.isLinux) {
      final file = File('/proc/meminfo');
      if (!await file.exists()) return null;
      try {
        final values = <String, int>{};
        for (final line in await file.readAsLines()) {
          final match = RegExp(
            r'^(MemTotal|MemAvailable):\s+(\d+)\s+kB',
          ).firstMatch(line);
          if (match != null) {
            values[match.group(1)!] = int.parse(match.group(2)!) * 1024;
          }
        }
        return {
          'totalPhysicalMemoryBytes': values['MemTotal'],
          'availablePhysicalMemoryBytes': values['MemAvailable'],
        };
      } catch (error) {
        return {'queryError': error.toString()};
      }
    }
    if (Platform.isWindows) {
      final decoded = await _powershellJson(
        r'Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize,FreePhysicalMemory | ConvertTo-Json -Compress',
      );
      if (decoded is Map) {
        int? kib(String key) {
          final raw = decoded[key];
          final value = raw is num ? raw.toInt() : int.tryParse('$raw');
          return value == null ? null : value * 1024;
        }

        return {
          'totalPhysicalMemoryBytes': kib('TotalVisibleMemorySize'),
          'availablePhysicalMemoryBytes': kib('FreePhysicalMemory'),
        };
      }
      return decoded == null ? null : {'raw': decoded};
    }
    return null;
  }

  Future<Object?> _graphicsInfo() async {
    if (Platform.isWindows) {
      return _powershellJson(
        r'Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM | ConvertTo-Json -Compress',
      );
    }
    if (Platform.isLinux) {
      try {
        final result = await Process.run('sh', const [
          '-lc',
          "if command -v lspci >/dev/null 2>&1; then lspci -nn | grep -Ei 'vga|3d|display' | head -n 8; fi",
        ]).timeout(const Duration(seconds: 3));
        final output = LauncherLog.redactSensitiveValues(
          result.stdout.toString().trim(),
        );
        String? vulkan;
        try {
          final vk = await Process.run('sh', const [
            '-lc',
            'if command -v vulkaninfo >/dev/null 2>&1; then vulkaninfo --summary 2>/dev/null | head -n 120; fi',
          ]).timeout(const Duration(seconds: 4));
          final text = LauncherLog.redactSensitiveValues(
            vk.stdout.toString().trim(),
          );
          if (text.isNotEmpty) vulkan = text;
        } catch (_) {}
        return {
          'displayControllers': output.isEmpty ? null : output,
          'vulkanSummary': vulkan,
        };
      } catch (error) {
        return {'queryError': error.toString()};
      }
    }
    return null;
  }

  Future<Object?> _securityProducts() async {
    if (!Platform.isWindows || RuntimeEnvironment.isWine) return null;
    return _powershellJson(
      r'Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | Select-Object displayName,productState | ConvertTo-Json -Compress',
    );
  }

  Future<Object?> _powershellJson(String command) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        command,
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) {
        return {
          'queryExitCode': result.exitCode,
          'stderr': LauncherLog.redactSensitiveValues(
            result.stderr.toString().trim(),
          ),
        };
      }
      final output = result.stdout.toString().trim();
      if (output.isEmpty) return null;
      try {
        return _redactObject(jsonDecode(output));
      } catch (_) {
        return LauncherLog.redactSensitiveValues(output);
      }
    } catch (error) {
      return {'queryError': error.toString()};
    }
  }

  Future<Map<String, Object?>?> _pathStorage(String path) async {
    if (Platform.isLinux) {
      try {
        final result = await Process.run('df', [
          '-PT',
          '--',
          path,
        ]).timeout(const Duration(seconds: 3));
        if (result.exitCode != 0) {
          return {
            'queryExitCode': result.exitCode,
            'stderr': LauncherLog.redactSensitiveValues(
              result.stderr.toString().trim(),
            ),
          };
        }
        final lines = result.stdout
            .toString()
            .trim()
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        if (lines.length < 2) return null;
        final parts = lines.last.trim().split(RegExp(r'\s+'));
        return {
          'filesystem': parts.isNotEmpty ? parts[0] : null,
          'type': parts.length > 1 ? parts[1] : null,
          'blocks1024': parts.length > 2 ? int.tryParse(parts[2]) : null,
          'used1024': parts.length > 3 ? int.tryParse(parts[3]) : null,
          'available1024': parts.length > 4 ? int.tryParse(parts[4]) : null,
          'capacity': parts.length > 5 ? parts[5] : null,
          'mountPoint': parts.length > 6
              ? LauncherLog.redactSensitiveValues(parts.sublist(6).join(' '))
              : null,
        };
      } catch (error) {
        return {'queryError': error.toString()};
      }
    }
    if (Platform.isWindows) {
      final match = RegExp(r'^([A-Za-z]):').firstMatch(path);
      if (match == null) return null;
      final drive = match.group(1)!;
      final result = await _powershellJson(
        "Get-Volume -DriveLetter '$drive' | Select-Object DriveLetter,FileSystem,FileSystemLabel,HealthStatus,Size,SizeRemaining | ConvertTo-Json -Compress",
      );
      return result is Map
          ? Map<String, Object?>.from(
              result.map((key, value) => MapEntry(key.toString(), value)),
            )
          : {'raw': result};
    }
    return null;
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

  static DateTime? _dateFromObject(Object? value) {
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }

  static bool? _equalOptional(String? expected, String? installed) {
    if (expected == null || installed == null) return null;
    return expected == installed;
  }
}
