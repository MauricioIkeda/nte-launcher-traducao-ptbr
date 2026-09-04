from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"anchor not found: {label}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# DiagnosticService
# ---------------------------------------------------------------------------
diagnostic_path = Path("lib/services/diagnostic_service.dart")
diagnostic = diagnostic_path.read_text(encoding="utf-8")

diagnostic = replace_once(
    diagnostic,
    "import 'game_platform_service.dart';\nimport 'installation_service.dart';",
    "import 'game_language_service.dart';\nimport 'game_platform_service.dart';\nimport 'installation_service.dart';",
    "diagnostic import",
)

diagnostic = replace_once(
    diagnostic,
    "  static const _knownProxyDlls = <String>{\n"
    "    'version.dll',\n"
    "    'winmm.dll',\n"
    "    'dsound.dll',\n"
    "    'dinput8.dll',\n"
    "    'xinput1_3.dll',\n"
    "    'xinput9_1_0.dll',\n"
    "    'dxgi.dll',\n"
    "    'd3d11.dll',\n"
    "    'd3d12.dll',\n"
    "  };",
    "  static const _knownProxyDlls = <String>{\n"
    "    'version.dll',\n"
    "    'winmm.dll',\n"
    "    'dsound.dll',\n"
    "    'dinput8.dll',\n"
    "    'xinput1_3.dll',\n"
    "    'xinput9_1_0.dll',\n"
    "    'dxgi.dll',\n"
    "    'd3d11.dll',\n"
    "    'd3d12.dll',\n"
    "  };\n\n"
    "  // Some filenames that can act as proxy loaders are also legitimate\n"
    "  // runtime dependencies shipped by games. Keep them visible in the\n"
    "  // inventory, but do not accuse them of being foreign mods based on the\n"
    "  // filename alone.\n"
    "  static const _commonRuntimeDllNames = <String>{\n"
    "    'xinput1_3.dll',\n"
    "    'xinput9_1_0.dll',\n"
    "  };",
    "common runtime dll names",
)

old_timestamp = r"""  DateTime? _sigTimestamp(String line) {
    final match = RegExp(
      r'^\[(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2}(?:\.\d+)?)\]',
    ).firstMatch(line);
    if (match == null) return null;
    final local = DateTime.tryParse('${match.group(1)}T${match.group(2)}');
    return local?.toUtc();
  }
"""
new_timestamp = r"""  DateTime? _sigTimestamp(String line) {
    // UniversalSigBypasser currently emits timestamps without brackets, while
    // older/test fixtures may use brackets. Accept both shapes. The log uses
    // local wall-clock time, so parse it as local and normalize to UTC before
    // comparing it with launcher events.
    final match = RegExp(
      r'^\[?(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2}(?:\.\d+)?)(?:\])?',
    ).firstMatch(line);
    if (match == null) return null;
    var time = match.group(2)!;
    final dot = time.indexOf('.');
    if (dot >= 0 && time.length - dot - 1 > 6) {
      time = time.substring(0, dot + 7);
    }
    final local = DateTime.tryParse('${match.group(1)}T$time');
    return local?.toUtc();
  }
"""
diagnostic = replace_once(
    diagnostic,
    old_timestamp,
    new_timestamp,
    "SigBypasser timestamp parser",
)

old_modules = r"""  Future<Map<String, Object?>> _loadedModuleEvidence() async {
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
"""
new_modules = r"""  Future<Map<String, Object?>> _loadedModuleEvidence() async {
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
      final moduleListUnavailable =
          running &&
          (lower.contains('"n/a"') ||
              lower.contains(',n/a') ||
              lower.endsWith('n/a'));
      final moduleListAvailable = running && !moduleListUnavailable;
      return {
        'supported': true,
        'queryExitCode': result.exitCode,
        'htGameRunning': running,
        'moduleListAvailable': running ? moduleListAvailable : null,
        // A protected process may let tasklist see HTGame.exe while returning
        // N/A for its module list. In that situation "false" would be a false
        // negative, so report null/unknown instead.
        'versionDllLoaded': !running
            ? false
            : moduleListAvailable
            ? lower.contains('version.dll')
            : null,
        'universalSigBypasserLoaded': !running
            ? false
            : moduleListAvailable
            ? lower.contains('universalsigbypasser.asi')
            : null,
        if (moduleListUnavailable)
          'reason': 'tasklist_module_list_unavailable_for_running_process',
        'raw': output.length <= 32768 ? output : output.substring(0, 32768),
        if (error.isNotEmpty) 'stderr': error,
      };
    } catch (error) {
      return {'supported': true, 'queryError': error.toString()};
    }
  }
"""
diagnostic = replace_once(
    diagnostic,
    old_modules,
    new_modules,
    "loaded module evidence",
)

old_loader_candidate = r"""          final isManaged = managed.contains(relative.toLowerCase());
          loaderCandidates.add({
            'relativePath': relative,
            'managedByCurrentManifest': isManaged,
            'potentialForeignLoader': !isManaged,
"""
new_loader_candidate = r"""          final isManaged = managed.contains(relative.toLowerCase());
          final commonRuntimeName = _commonRuntimeDllNames.contains(name);
          loaderCandidates.add({
            'relativePath': relative,
            'managedByCurrentManifest': isManaged,
            'commonRuntimeName': commonRuntimeName,
            'potentialForeignLoader': !isManaged && !commonRuntimeName,
            'candidateClassification': isManaged
                ? 'managed_translation_file'
                : commonRuntimeName
                ? 'unmanaged_common_runtime_name'
                : 'unmanaged_loader_candidate',
"""
diagnostic = replace_once(
    diagnostic,
    old_loader_candidate,
    new_loader_candidate,
    "loader candidate classification",
)

old_language_anchor = r"""    if (!await file.exists()) return result;
    try {
      if (await file.length() > 2 * 1024 * 1024) {
"""
new_language_anchor = r"""    if (!await file.exists()) return result;

    // NteHybridCulture/NteEncryptedCulture are receipt sentinels, not literal
    // INI keys. Asking the file for "NteHybridCulture=" therefore produced a
    // misleading keyPresent=false even on healthy installations.
    if (language.key == 'NteHybridCulture' ||
        language.key == 'NteEncryptedCulture') {
      result['keyIsSynthetic'] = true;
      result['currentState'] = await GameLanguageService().inspectReceiptState(
        language,
      );
      return result;
    }

    try {
      if (await file.length() > 2 * 1024 * 1024) {
"""
diagnostic = replace_once(
    diagnostic,
    old_language_anchor,
    new_language_anchor,
    "synthetic language receipt inspection",
)

diagnostic = replace_once(
    diagnostic,
    "            .where((line) => relevant.hasMatch(line))\n            .take(400)",
    "            .where(\n"
    "              (line) =>\n"
    "                  relevant.hasMatch(line) && !_looksLikeOpaqueEncodedLine(line),\n"
    "            )\n"
    "            .take(400)",
    "filtered Unreal log opaque-line suppression",
)

helper_anchor = "  Future<List<File>> _recentCrashLogs(String gameDirectory) async {"
helper_method = r"""  bool _looksLikeOpaqueEncodedLine(String line) {
    final value = line.trim();
    if (value.length < 96 || value.contains(' ') || value.contains('\t')) {
      return false;
    }
    // GameUserSettings/log payloads can contain long Base64 ciphertext lines.
    // Keyword substring matching inside ciphertext produces meaningless noise
    // (for example an accidental "mod" or "error" sequence), so suppress a
    // line only when it strongly resembles one opaque encoded token.
    return RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(value);
  }

"""
diagnostic = replace_once(
    diagnostic,
    helper_anchor,
    helper_method + helper_anchor,
    "opaque encoded line helper",
)

diagnostic_path.write_text(diagnostic, encoding="utf-8")


# ---------------------------------------------------------------------------
# GameLanguageService: expose a safe, read-only diagnostic interpretation of
# the receipt without leaking encrypted raw tokens.
# ---------------------------------------------------------------------------
language_path = Path("lib/services/game_language_service.dart")
language = language_path.read_text(encoding="utf-8")

language_anchor = "  Future<LanguageSwitchResult> ensureCulture(\n"
inspection_method = r"""  Future<Map<String, Object?>> inspectReceiptState(
    TextLanguageReceipt receipt,
  ) async {
    if (!_isAllowedConfigPath(receipt.configPath)) {
      return const {
        'detected': false,
        'reason': 'config_path_not_allowed',
      };
    }
    final file = File(receipt.configPath);
    if (!await file.exists()) {
      return const {
        'detected': false,
        'reason': 'config_file_missing',
      };
    }

    final normalizedKey = _normalizeKey(receipt.key);
    if (normalizedKey == _normalizeKey(_nteHybridKey) ||
        normalizedKey == _normalizeKey(_nteEncryptedKey)) {
      final state = await _detectEncryptedState(file);
      if (state == null) {
        return const {
          'mode': 'encrypted',
          'detected': false,
          'reason': 'encrypted_language_layout_not_recognized',
        };
      }
      final requested = receipt.requestedCulture.toLowerCase();
      final currentTriplet = (
        state.globalLanguage.toLowerCase(),
        state.globalLocale.toLowerCase(),
        state.gameLanguage.toLowerCase(),
      );
      final expectedHybrid = ('en', 'en', requested);
      final expectedAfterGame = (requested, requested, requested);
      return {
        'mode': 'encrypted',
        'detected': true,
        'cultures': {
          'globalLanguage': state.globalLanguage,
          'globalLocale': state.globalLocale,
          'gameLanguage': state.gameLanguage,
        },
        'matchesManagedExpectation':
            currentTriplet == expectedHybrid || currentTriplet == expectedAfterGame,
      };
    }

    final parsed = await _readIni(file);
    final matches = parsed.settings
        .where(
          (setting) => _normalizeKey(setting.key) == normalizedKey,
        )
        .toList(growable: false);
    if (matches.length != 1) {
      return {
        'mode': 'plain',
        'detected': false,
        'matchingKeyCount': matches.length,
      };
    }
    final current = matches.single.value;
    return {
      'mode': 'plain',
      'detected': true,
      'currentCulture': current,
      'matchesRequestedCulture':
          current.toLowerCase() == receipt.requestedCulture.toLowerCase(),
    };
  }

"""
language = replace_once(
    language,
    language_anchor,
    inspection_method + language_anchor,
    "language receipt diagnostic inspection",
)
language_path.write_text(language, encoding="utf-8")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
language_test_path = Path("test/game_language_service_test.dart")
language_test = language_test_path.read_text(encoding="utf-8")

old_language_test = r"""      final current = await ini.readAsString();
      expect(RegExp(RegExp.escape(languageEn)).allMatches(current).length, 1);
      expect(RegExp(RegExp.escape(languageFr)).allMatches(current).length, 1);
      expect(RegExp(RegExp.escape(localeEn)).allMatches(current).length, 1);
      expect(current, isNot(contains(localeFr)));
      expect(current, contains(audioEn));

      final restored = await service.restore(result.receipt);
"""
new_language_test = r"""      final current = await ini.readAsString();
      expect(RegExp(RegExp.escape(languageEn)).allMatches(current).length, 1);
      expect(RegExp(RegExp.escape(languageFr)).allMatches(current).length, 1);
      expect(RegExp(RegExp.escape(localeEn)).allMatches(current).length, 1);
      expect(current, isNot(contains(localeFr)));
      expect(current, contains(audioEn));

      final inspection = await service.inspectReceiptState(result.receipt!);
      expect(inspection['mode'], 'encrypted');
      expect(inspection['detected'], isTrue);
      expect(inspection['matchesManagedExpectation'], isTrue);
      expect(inspection['cultures'], {
        'globalLanguage': 'en',
        'globalLocale': 'en',
        'gameLanguage': 'fr',
      });

      final restored = await service.restore(result.receipt);
"""
language_test = replace_once(
    language_test,
    old_language_test,
    new_language_test,
    "language inspection test",
)
language_test_path.write_text(language_test, encoding="utf-8")

controller_test_path = Path("test/launcher_controller_test.dart")
controller_test = controller_test_path.read_text(encoding="utf-8")

old_fixture_anchor = r"""    await officialLog.writeAsString(
      'Current version: 1.0.8.0807_2(build:76a5250a)\n'
      'all ready, wait for start game access_token=hidden-game-token',
    );
    await paths.officialLaunchResultFile.parent.create(recursive: true);
"""
new_fixture_anchor = r"""    await officialLog.writeAsString(
      'Current version: 1.0.8.0807_2(build:76a5250a)\n'
      'all ready, wait for start game access_token=hidden-game-token',
    );

    // Reproduce the real UniversalSigBypasser timestamp shape observed in NTE:
    // no surrounding brackets and local wall-clock time.
    await paths.diagnosticEventsFile.parent.create(recursive: true);
    final launchAt = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    await paths.diagnosticEventsFile.writeAsString(
      '${jsonEncode({
        'at': launchAt.toIso8601String(),
        'event': 'game_launch_started',
        'details': <String, Object?>{},
      })}\n',
    );
    final sigLog = File(
      p.join(
        game.path,
        'Client',
        'WindowsNoEditor',
        'HT',
        'Binaries',
        'Win64',
        'SigBypasser.log',
      ),
    );
    await sigLog.parent.create(recursive: true);
    final sigTimestamp = DateTime.now().toIso8601String().replaceFirst('T', ' ');
    await sigLog.writeAsString(
      '$sigTimestamp [INFO] <UniversalPatch:43>: UniversalSigBypasser Loaded.\n'
      '$sigTimestamp [INFO] <UniversalPatch:66>: Pattern 2 found at 0x1\n'
      '$sigTimestamp [INFO] <UniversalPatch:81>: Patch applied at 0x2\n'
      '$sigTimestamp [INFO] <UniversalPatch:91>: Bypass process ended.\n',
    );

    // xinput1_3.dll is a loader-like filename but can be a legitimate game
    // runtime dependency. Keep it in inventory without flagging it as a mod.
    final xinput = File(
      p.join(
        game.path,
        'Client',
        'WindowsNoEditor',
        'HT',
        'Binaries',
        'Win64',
        'xinput1_3.dll',
      ),
    );
    await xinput.writeAsBytes(const [1, 2, 3, 4]);

    await paths.officialLaunchResultFile.parent.create(recursive: true);
"""
controller_test = replace_once(
    controller_test,
    old_fixture_anchor,
    new_fixture_anchor,
    "diagnostic runtime fixture",
)

assertion_anchor = "    expect(decoded['game']['translationRuntime'], isA<Map<String, dynamic>>());\n"
assertions = (
    assertion_anchor
    + "    expect(\n"
    + "      decoded['game']['translationRuntime']['derivedStatus'],\n"
    + "      'patch_applied_after_last_launch',\n"
    + "    );\n"
    + "    expect(\n"
    + "      decoded['game']['translationRuntime']['markersAtOrAfterLastLaunch']\n"
    + "          ['patchApplied'],\n"
    + "      1,\n"
    + "    );\n"
    + "    expect(\n"
    + "      decoded['game']['modAndLoaderInventory']['foreignLoaderCandidateCount'],\n"
    + "      0,\n"
    + "    );\n"
)
if "'patch_applied_after_last_launch'" not in controller_test:
    if assertion_anchor not in controller_test:
        raise SystemExit("anchor not found: runtime diagnostic assertions")
    controller_test = controller_test.replace(assertion_anchor, assertions, 1)
controller_test_path.write_text(controller_test, encoding="utf-8")
