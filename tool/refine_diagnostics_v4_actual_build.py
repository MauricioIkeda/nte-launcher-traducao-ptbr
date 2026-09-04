from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"anchor not found: {label}")
    return text.replace(old, new, 1)


diagnostic_path = Path("lib/services/diagnostic_service.dart")
diagnostic = diagnostic_path.read_text(encoding="utf-8")

diagnostic = replace_once(
    diagnostic,
    "      'temporaryReceiptFound': receiptRead.temporaryReceiptFound,\n      'sourceIdentityComparison': {",
    "      'temporaryReceiptFound': receiptRead.temporaryReceiptFound,\n"
    "      'actualGameBuildEvidence': await _gameBuildEvidence(\n"
    "        normalizedDirectory,\n"
    "      ),\n"
    "      'sourceIdentityComparison': {",
    "game build field",
)

anchor = "  Future<Map<String, Object?>> _pathEnvironment(String gameDirectory) async {"
method = r"""  Future<Map<String, Object?>> _gameBuildEvidence(
    String gameDirectory,
  ) async {
    final logRoots = <Directory>[
      Directory(p.join(gameDirectory, 'NTEGlobal', 'UserData', 'Log')),
      Directory(p.join(gameDirectory, 'NTE Global', 'UserData', 'Log')),
      Directory(p.join(gameDirectory, 'UserData', 'Log')),
    ];
    final seen = <String>{};
    final launcherCandidates = <File>[];
    final updateCandidates = <File>[];
    for (final root in logRoots) {
      final key = p.normalize(root.path).toLowerCase();
      if (!seen.add(key)) continue;
      launcherCandidates.add(File(p.join(root.path, 'NTEGlobalGame.log')));
      updateCandidates.add(File(p.join(root.path, 'NTEGlobalUpdate.log')));
    }

    final launcher = await _latestExistingFile(launcherCandidates);
    final update = await _latestExistingFile(updateCandidates);
    final launcherEvidence = launcher == null
        ? null
        : await _launcherBuildEvidence(launcher);
    final updateEvidence = update == null
        ? null
        : await _updateBuildEvidence(update);
    return {
      'launcher': launcherEvidence,
      'updater': updateEvidence,
      'detectedVersion': launcherEvidence?['version'] ??
          updateEvidence?['currentVersion'] ??
          updateEvidence?['availableVersion'],
      'detectedBuild': launcherEvidence?['build'] ??
          updateEvidence?['currentBuild'] ??
          updateEvidence?['availableBuild'],
      'note':
          'Evidência extraída dos logs do launcher oficial do NTE. '
          'O formato pode diferir do gameBuildId editorial do manifesto; '
          'por isso não é declarada compatibilidade automaticamente.',
    };
  }

  Future<File?> _latestExistingFile(List<File> candidates) async {
    final existing = <File>[];
    for (final file in candidates) {
      if (await file.exists()) existing.add(file);
    }
    if (existing.isEmpty) return null;
    existing.sort((first, second) {
      try {
        return second.lastModifiedSync().compareTo(first.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });
    return existing.first;
  }

  Future<Map<String, Object?>> _launcherBuildEvidence(File file) async {
    final result = <String, Object?>{
      'file': await _describeFile(file),
    };
    try {
      final bytes = await _readTailBytes(file, _maxHtLogScanBytes);
      final source = utf8.decode(bytes, allowMalformed: true);
      final matches = RegExp(
        r'Current version:\s*([^\s(]+)\s*\(build:([^\)]+)\)',
        caseSensitive: false,
      ).allMatches(source).toList();
      if (matches.isNotEmpty) {
        final match = matches.last;
        result['version'] = match.group(1)?.trim();
        result['build'] = match.group(2)?.trim();
      }
    } catch (error) {
      result['readError'] = error.toString();
    }
    return result;
  }

  Future<Map<String, Object?>> _updateBuildEvidence(File file) async {
    final result = <String, Object?>{
      'file': await _describeFile(file),
    };
    try {
      final bytes = await _readTailBytes(file, _maxHtLogScanBytes);
      final source = utf8.decode(bytes, allowMalformed: true);
      final available = RegExp(
        r'Get new version succeed,\s*Version=([^,\s]+),\s*BuildNo=([^\s]+)',
        caseSensitive: false,
      ).allMatches(source).toList();
      if (available.isNotEmpty) {
        final match = available.last;
        result['availableVersion'] = match.group(1)?.trim();
        result['availableBuild'] = match.group(2)?.trim();
      }
      final current = RegExp(
        r'Current(?:\s+client)?\s+version[:=]\s*([^,\s]+)(?:,?\s*Build(?:No)?[:=]\s*([^\s]+))?',
        caseSensitive: false,
      ).allMatches(source).toList();
      if (current.isNotEmpty) {
        final match = current.last;
        result['currentVersion'] = match.group(1)?.trim();
        result['currentBuild'] = match.group(2)?.trim();
      }
    } catch (error) {
      result['readError'] = error.toString();
    }
    return result;
  }

"""

diagnostic = replace_once(
    diagnostic,
    anchor,
    method + anchor,
    "game build methods",
)
diagnostic_path.write_text(diagnostic, encoding="utf-8")

test_path = Path("test/launcher_controller_test.dart")
test = test_path.read_text(encoding="utf-8")
old_log = "      'all ready, wait for start game access_token=hidden-game-token',"
new_log = (
    "      'Current version: 1.0.8.0807_2(build:76a5250a)\\n'\n"
    "      'all ready, wait for start game access_token=hidden-game-token',"
)
test = replace_once(test, old_log, new_log, "official log fixture")
assertion_anchor = "    expect(decoded['game']['normalizedDirectory'], game.path);\n"
assertions = (
    assertion_anchor
    + "    expect(\n"
    + "      decoded['game']['actualGameBuildEvidence']['detectedVersion'],\n"
    + "      '1.0.8.0807_2',\n"
    + "    );\n"
    + "    expect(\n"
    + "      decoded['game']['actualGameBuildEvidence']['detectedBuild'],\n"
    + "      '76a5250a',\n"
    + "    );\n"
)
if "actualGameBuildEvidence']['detectedVersion" not in test:
    if assertion_anchor not in test:
        raise SystemExit("diagnostic assertion anchor not found")
    test = test.replace(assertion_anchor, assertions, 1)
test_path.write_text(test, encoding="utf-8")
