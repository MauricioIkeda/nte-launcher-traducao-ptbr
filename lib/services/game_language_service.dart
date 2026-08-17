import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/install_receipt.dart';

class LanguageSwitchResult {
  const LanguageSwitchResult({
    required this.changed,
    this.receipt,
    this.reason,
    this.preservedUserChoice = false,
  });

  final bool changed;
  final TextLanguageReceipt? receipt;
  final String? reason;
  final bool preservedUserChoice;
}

class LanguageRestoreResult {
  const LanguageRestoreResult({
    required this.restored,
    this.reason,
    this.preservedUserChoice = false,
  });

  final bool restored;
  final String? reason;
  final bool preservedUserChoice;
}

class GameLanguageService {
  GameLanguageService({String? localAppData})
    : _localAppData = localAppData ?? Platform.environment['LOCALAPPDATA'];

  final String? _localAppData;

  static const _knownValues = <String>{
    'en',
    'fr',
    'de',
    'es',
    'ru',
    'ja',
    'ko',
    'zh-cn',
    'zh-hant',
    'zh-tw',
    'english',
    'french',
    'german',
    'spanish',
    'russian',
    'japanese',
    'korean',
    'chinese',
  };

  static const _safeKeys = <String>{
    'culture',
    'currentculture',
    'gameculture',
    'language',
    'currentlanguage',
    'textlanguage',
    'textlanguagecode',
    'subtitlelanguage',
    'subtitlelanguagecode',
    'uilanguage',
    'uilanguagecode',
    'locale',
    'currentlocale',
    'languagecode',
  };

  static const _voiceTerms = <String>['voice', 'audio', 'dub', 'speech'];

  Future<LanguageSwitchResult> ensureCulture(
    String culture, {
    TextLanguageReceipt? previous,
  }) async {
    if (culture != 'fr') {
      return const LanguageSwitchResult(
        changed: false,
        reason: 'O launcher só permite troca automática para o slot fr.',
      );
    }

    final detected = await _detect();
    if (previous != null) {
      if (detected == null) {
        return LanguageSwitchResult(changed: false, receipt: previous);
      }
      if (!_sameSetting(detected, previous)) {
        return LanguageSwitchResult(
          changed: false,
          receipt: previous,
          reason: 'A configuração de idioma mudou desde a instalação anterior.',
          preservedUserChoice: true,
        );
      }
      if (detected.value.toLowerCase() != culture) {
        return LanguageSwitchResult(
          changed: false,
          receipt: previous,
          reason: 'O usuário alterou o idioma depois da instalação.',
          preservedUserChoice: true,
        );
      }
      return LanguageSwitchResult(changed: false, receipt: previous);
    }

    if (detected == null) {
      return const LanguageSwitchResult(
        changed: false,
        reason: 'Nenhuma configuração textual de idioma segura foi encontrada.',
      );
    }
    if (detected.value.toLowerCase() == culture) {
      return const LanguageSwitchResult(
        changed: false,
        reason: 'O NTE já está usando o slot francês.',
      );
    }

    final receipt = TextLanguageReceipt(
      configPath: detected.file.path,
      key: detected.key,
      previousRawValue: detected.rawValue,
      previousValue: detected.value,
      requestedCulture: culture,
    );
    await _replaceSetting(detected, culture);
    return LanguageSwitchResult(changed: true, receipt: receipt);
  }

  Future<LanguageRestoreResult> restore(TextLanguageReceipt? receipt) async {
    if (receipt == null) {
      return const LanguageRestoreResult(
        restored: false,
        reason: 'Nenhuma alteração automática de idioma foi registrada.',
      );
    }
    if (!_isAllowedConfigPath(receipt.configPath)) {
      return const LanguageRestoreResult(
        restored: false,
        reason: 'O caminho salvo da configuração não é permitido.',
      );
    }

    final file = File(receipt.configPath);
    if (!await file.exists()) {
      return const LanguageRestoreResult(
        restored: false,
        reason: 'O arquivo de configuração não existe mais.',
      );
    }
    final parsed = await _readIni(file);
    final matches = parsed.settings
        .where(
          (setting) => _normalizeKey(setting.key) == _normalizeKey(receipt.key),
        )
        .toList(growable: false);
    if (matches.length != 1) {
      return const LanguageRestoreResult(
        restored: false,
        reason: 'A chave de idioma não pôde ser identificada de forma única.',
      );
    }
    final current = matches.single;
    if (current.value.toLowerCase() != receipt.requestedCulture.toLowerCase()) {
      return const LanguageRestoreResult(
        restored: false,
        reason:
            'O idioma foi alterado depois da instalação; a escolha atual foi preservada.',
        preservedUserChoice: true,
      );
    }

    await _replaceSetting(
      current,
      receipt.previousRawValue,
      rawReplacement: true,
    );
    return const LanguageRestoreResult(restored: true);
  }

  Future<_DetectedSetting?> _detect() async {
    final candidates = <_DetectedSetting>[];
    for (final file in _candidateFiles()) {
      if (!await file.exists()) {
        continue;
      }
      final parsed = await _readIni(file);
      for (final setting in parsed.settings) {
        final normalized = _normalizeKey(setting.key);
        final combined = '${setting.section} ${setting.key}'.toLowerCase();
        if (_voiceTerms.any(combined.contains)) {
          continue;
        }
        final safe =
            _safeKeys.contains(normalized) ||
            (setting.section.toLowerCase().contains('internationalization') &&
                const {'culture', 'language', 'locale'}.contains(normalized));
        if (!safe || !_knownValues.contains(setting.value.toLowerCase())) {
          continue;
        }
        candidates.add(setting);
      }
    }
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) {
      final score = _score(a).compareTo(_score(b));
      if (score != 0) {
        return score;
      }
      return a.file.path.compareTo(b.file.path);
    });
    final bestScore = _score(candidates.first);
    final best = candidates.where((item) => _score(item) == bestScore).toList();
    if (best.length != 1) {
      return null;
    }
    return best.single;
  }

  int _score(_DetectedSetting setting) {
    final key = _normalizeKey(setting.key);
    const keyOrder = <String, int>{
      'textlanguage': 0,
      'textlanguagecode': 0,
      'subtitlelanguage': 1,
      'subtitlelanguagecode': 1,
      'uilanguage': 2,
      'uilanguagecode': 2,
      'language': 3,
      'currentlanguage': 3,
      'languagecode': 3,
      'culture': 4,
      'currentculture': 4,
      'gameculture': 4,
      'locale': 5,
      'currentlocale': 5,
    };
    final fileOrder =
        p.basename(setting.file.path).toLowerCase() == 'gameusersettings.ini'
        ? 0
        : 1;
    return (keyOrder[key] ?? 99) * 10 + fileOrder;
  }

  List<File> _candidateFiles() {
    final local = _localAppData?.trim();
    if (local == null || local.isEmpty) {
      return const [];
    }
    final base = p.join(local, 'HT');
    final roots = [
      p.join(base, 'Saved_Global', 'Config', 'Windows'),
      p.join(base, 'Saved', 'Config', 'Windows'),
      p.join(base, 'Saved', 'Config', 'WindowsClient'),
    ];
    const names = ['GameUserSettings.ini', 'Game.ini', 'UserSettings.ini'];
    return [
      for (final root in roots)
        for (final name in names) File(p.join(root, name)),
    ];
  }

  bool _isAllowedConfigPath(String value) {
    final local = _localAppData?.trim();
    if (local == null || local.isEmpty) {
      return false;
    }
    final candidate = p.normalize(p.absolute(value));
    final roots = [
      p.join(local, 'HT', 'Saved_Global', 'Config', 'Windows'),
      p.join(local, 'HT', 'Saved', 'Config', 'Windows'),
      p.join(local, 'HT', 'Saved', 'Config', 'WindowsClient'),
    ].map((root) => p.normalize(p.absolute(root)));
    if (!const {
      'gameusersettings.ini',
      'game.ini',
      'usersettings.ini',
    }.contains(p.basename(candidate).toLowerCase())) {
      return false;
    }
    return roots.any((root) => p.isWithin(root, candidate));
  }

  bool _sameSetting(_DetectedSetting current, TextLanguageReceipt previous) =>
      p.equals(
        p.normalize(current.file.path),
        p.normalize(previous.configPath),
      ) &&
      _normalizeKey(current.key) == _normalizeKey(previous.key);

  Future<_ParsedIni> _readIni(File file) async {
    final bytes = await file.readAsBytes();
    late final List<int> bom;
    late final String text;
    late final _IniEncoding encoding;
    if (bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      bom = const [0xef, 0xbb, 0xbf];
      encoding = _IniEncoding.utf8;
      text = utf8.decode(bytes.sublist(3));
    } else {
      bom = const [];
      try {
        text = utf8.decode(bytes);
        encoding = _IniEncoding.utf8;
      } on FormatException {
        text = latin1.decode(bytes);
        encoding = _IniEncoding.latin1;
      }
    }

    final lines = _splitLines(text);
    final settings = <_DetectedSetting>[];
    var section = '';
    final assignment = RegExp(r'^(\s*)([^;#][^=]*?)(\s*=\s*)(.*)$');
    for (var index = 0; index < lines.length; index++) {
      final body = _withoutLineEnding(lines[index]);
      final stripped = body.trim();
      if (stripped.startsWith('[') && stripped.endsWith(']')) {
        section = stripped.substring(1, stripped.length - 1);
        continue;
      }
      final match = assignment.firstMatch(body);
      if (match == null) {
        continue;
      }
      final rawValue = match.group(4)!.trim();
      final value = _unquote(rawValue);
      settings.add(
        _DetectedSetting(
          file: file,
          parsed: _ParsedIni(
            text: text,
            encoding: encoding,
            bom: bom,
            lines: lines,
            settings: const [],
          ),
          lineIndex: index,
          section: section,
          key: match.group(2)!.trim(),
          rawValue: rawValue,
          value: value,
        ),
      );
    }
    final parsed = _ParsedIni(
      text: text,
      encoding: encoding,
      bom: bom,
      lines: lines,
      settings: const [],
    );
    return parsed.withSettings([
      for (final item in settings) item.withParsed(parsed),
    ]);
  }

  Future<void> _replaceSetting(
    _DetectedSetting setting,
    String replacement, {
    bool rawReplacement = false,
  }) async {
    final current = await _readIni(setting.file);
    final candidates = current.settings
        .where(
          (item) =>
              _normalizeKey(item.key) == _normalizeKey(setting.key) &&
              item.lineIndex == setting.lineIndex,
        )
        .toList(growable: false);
    if (candidates.length != 1) {
      throw const FormatException(
        'A configuração de idioma mudou durante a operação.',
      );
    }
    final validated = candidates.single;
    final line = _withoutLineEnding(current.lines[validated.lineIndex]);
    final ending = current.lines[validated.lineIndex].substring(line.length);
    final assignment = RegExp(r'^(\s*)([^;#][^=]*?)(\s*=\s*)(.*)$');
    final match = assignment.firstMatch(line);
    if (match == null) {
      throw const FormatException('A linha de idioma deixou de ser válida.');
    }
    var output = replacement;
    if (!rawReplacement) {
      final raw = match.group(4)!.trim();
      final quote =
          raw.length >= 2 &&
              raw[0] == raw[raw.length - 1] &&
              (raw[0] == '"' || raw[0] == "'")
          ? raw[0]
          : '';
      output = '$quote$replacement$quote';
    }
    current.lines[validated.lineIndex] =
        '${match.group(1)}${match.group(2)}${match.group(3)}$output$ending';
    final text = current.lines.join();
    final payload = current.encoding == _IniEncoding.utf8
        ? utf8.encode(text)
        : latin1.encode(text);
    final temporary = File('${setting.file.path}.nte-new');
    await temporary.writeAsBytes([...current.bom, ...payload], flush: true);
    if (await setting.file.exists()) {
      await setting.file.delete();
    }
    await temporary.rename(setting.file.path);
  }

  static List<String> _splitLines(String text) {
    final result = <String>[];
    var start = 0;
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) == 10) {
        result.add(text.substring(start, index + 1));
        start = index + 1;
      }
    }
    if (start < text.length || text.isEmpty) {
      result.add(text.substring(start));
    }
    return result;
  }

  static String _withoutLineEnding(String line) {
    if (line.endsWith('\r\n')) {
      return line.substring(0, line.length - 2);
    }
    if (line.endsWith('\n') || line.endsWith('\r')) {
      return line.substring(0, line.length - 1);
    }
    return line;
  }

  static String _unquote(String value) {
    if (value.length >= 2 &&
        value[0] == value[value.length - 1] &&
        (value[0] == '"' || value[0] == "'")) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  static String _normalizeKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

enum _IniEncoding { utf8, latin1 }

class _ParsedIni {
  const _ParsedIni({
    required this.text,
    required this.encoding,
    required this.bom,
    required this.lines,
    required this.settings,
  });

  final String text;
  final _IniEncoding encoding;
  final List<int> bom;
  final List<String> lines;
  final List<_DetectedSetting> settings;

  _ParsedIni withSettings(List<_DetectedSetting> value) => _ParsedIni(
    text: text,
    encoding: encoding,
    bom: bom,
    lines: lines,
    settings: value,
  );
}

class _DetectedSetting {
  const _DetectedSetting({
    required this.file,
    required this.parsed,
    required this.lineIndex,
    required this.section,
    required this.key,
    required this.rawValue,
    required this.value,
  });

  final File file;
  final _ParsedIni parsed;
  final int lineIndex;
  final String section;
  final String key;
  final String rawValue;
  final String value;

  _DetectedSetting withParsed(_ParsedIni value) => _DetectedSetting(
    file: file,
    parsed: value,
    lineIndex: lineIndex,
    section: section,
    key: key,
    rawValue: rawValue,
    value: this.value,
  );
}
