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

  static const _nteEncryptedKey = 'NteEncryptedCulture'; // legacy
  static const _nteHybridKey = 'NteHybridCulture';

  static const _knownValues = <String>{
    'en',
    'en-us',
    'en-gb',
    'fr',
    'fr-fr',
    'de',
    'de-de',
    'es',
    'es-es',
    'ru',
    'ru-ru',
    'ja',
    'ja-jp',
    'ko',
    'ko-kr',
    'zh-cn',
    'zh-hans',
    'zh-hant',
    'zh-tw',
    'th',
    'th-th',
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

  // NTE serializes each GameUserSettings.ini line independently using
  // AES-256-ECB + PKCS7 + Base64. We deliberately recognize only deterministic
  // Language/Locale ciphertexts. AudioCulture and every unrelated encrypted
  // setting stay byte-for-byte untouched.
  static const _encryptedLanguageLines = <String, String>{
    'en': 'zUs1iPOD6DH9WVA/j/WFQGymGOWDheFjSanKLCRlfZ4=',
    'en-us': '/3xqiRrC9gSVSzzgk9s+n4Ay2jEgNpY5BibX5hbRjA4=',
    'en-gb': 'Wnsy+vibeymVdcnxBPcIcYAy2jEgNpY5BibX5hbRjA4=',
    'fr': 'Lm88wdHSFnR2x5z6Z1s5umymGOWDheFjSanKLCRlfZ4=',
    'fr-fr': 'yM4HMC+PisXzFlO02IFU6IAy2jEgNpY5BibX5hbRjA4=',
    'de': 'kInAsIbW2RO39jtDoqxgRWymGOWDheFjSanKLCRlfZ4=',
    'de-de': 'o6s0CjJEKw4NruSwyGjP34Ay2jEgNpY5BibX5hbRjA4=',
    'es': 'nDVC6GjSxzk1HCELSNSNV2ymGOWDheFjSanKLCRlfZ4=',
    'es-es': 'GQBPvWNBp5ej9L4FpzLOtoAy2jEgNpY5BibX5hbRjA4=',
    'ru': 'GZeeimE9/EmQGWU5/eqB62ymGOWDheFjSanKLCRlfZ4=',
    'ru-ru': '9AupYWE2FKnFmbEBiOJVboAy2jEgNpY5BibX5hbRjA4=',
    'ja': 'FrRu/t7fsNwUvrMHA6lpUGymGOWDheFjSanKLCRlfZ4=',
    'ja-jp': 'v0/zImR7UgWAhYBy0bw2s4Ay2jEgNpY5BibX5hbRjA4=',
    'ko': 'ldZcTw0NKtqYUmr7GQ2ltmymGOWDheFjSanKLCRlfZ4=',
    'ko-kr': '2fzBE7VBcOP6lDHMa5HpZYAy2jEgNpY5BibX5hbRjA4=',
    'zh-cn': 'H+LS8ZaBI3EFCBAz2OhZdYAy2jEgNpY5BibX5hbRjA4=',
    'zh-hans': 'B+IsDNZQeF7VjuAXj9+GXsnVOUEe9Mh6izI/8SyK1z8=',
    'zh-hant': '+jBfHDlY9MUpA9QfKNqwpsnVOUEe9Mh6izI/8SyK1z8=',
    'zh-tw': 'K1PAMfH81lzWgVmLxiMddoAy2jEgNpY5BibX5hbRjA4=',
    'th': 'Mr/FGRfaUUxjE5mHBiBSumymGOWDheFjSanKLCRlfZ4=',
    'th-th': 'scPl6Bopz8d7oCI3sStOfoAy2jEgNpY5BibX5hbRjA4=',
  };

  static const _encryptedLocaleLines = <String, String>{
    'en': 'de0DvvQ7z4UvvV6EWBKSQAl+l+fR2Cyd408uYnmPbXw=',
    'en-us': 'X4NgZX5cv+MBEOqLsJ/zmCc7J11Vc2iciV0GHNrqZX0=',
    'en-gb': 'AaSNAnZrxYCl5HdPaUwRYSc7J11Vc2iciV0GHNrqZX0=',
    'fr': 'NeXLYGL6ZN14QCC1BFkXxgl+l+fR2Cyd408uYnmPbXw=',
    'fr-fr': 'fqp8w3C9R1LFT1Lz0vfPIyc7J11Vc2iciV0GHNrqZX0=',
    'de': 'kAx51uJGW9PhnQsypySd8gl+l+fR2Cyd408uYnmPbXw=',
    'de-de': '0oo3XcNTtPVxum+FCYchfSc7J11Vc2iciV0GHNrqZX0=',
    'es': 'U7ww0XObGiKxLTqDkHKbSQl+l+fR2Cyd408uYnmPbXw=',
    'es-es': 'Y/dXMjA4fB7tAyrjtguJKic7J11Vc2iciV0GHNrqZX0=',
    'ru': 'kJTNBpBHvFxsO9IJk5+E6Ql+l+fR2Cyd408uYnmPbXw=',
    'ru-ru': 'TVcG18meJR+2TXOcI1d9Yic7J11Vc2iciV0GHNrqZX0=',
    'ja': 'qe+3AT0Tj/K5P1A5tvJjwQl+l+fR2Cyd408uYnmPbXw=',
    'ja-jp': '7WVfleWuhmHIfd0lOG5Nxyc7J11Vc2iciV0GHNrqZX0=',
    'ko': 'ma+Rq+fFnNQZV8IpWBWjBwl+l+fR2Cyd408uYnmPbXw=',
    'ko-kr': '5xBkMQnSE0nBNaXd2Hp+sCc7J11Vc2iciV0GHNrqZX0=',
    'zh-cn': 'pj/WJENp2s6VPPXU8bSTRSc7J11Vc2iciV0GHNrqZX0=',
    'zh-hans': 'fJFprmlW9w3evcFFJSEFSIAy2jEgNpY5BibX5hbRjA4=',
    'zh-hant': '+zghpGpk7iBaLrNdFwsZxYAy2jEgNpY5BibX5hbRjA4=',
    'zh-tw': 'zi/BI3/n9FWVoLSYmk8KpSc7J11Vc2iciV0GHNrqZX0=',
    'th': 'zgFNxwqwkGly7CWrNMvapwl+l+fR2Cyd408uYnmPbXw=',
    'th-th': 'bg3m7zPMLUM9aJXBn1K3OSc7J11Vc2iciV0GHNrqZX0=',
  };

  static final _encryptedLanguageLookup = <String, String>{
    for (final entry in _encryptedLanguageLines.entries) entry.value: entry.key,
  };
  static final _encryptedLocaleLookup = <String, String>{
    for (final entry in _encryptedLocaleLines.entries) entry.value: entry.key,
  };

  Future<LanguageSwitchResult> ensureCulture(
    String culture, {
    TextLanguageReceipt? previous,
  }) async {
    if (culture != 'fr') {
      return const LanguageSwitchResult(
        changed: false,
        reason: 'O launcher só permite o host de texto no slot fr.',
      );
    }

    final encrypted = await _detectSingleEncryptedState();
    if (encrypted != null) {
      final receipt = _hybridReceipt(encrypted, culture, previous);
      final changed =
          encrypted.globalLanguage.toLowerCase() != 'en' ||
          encrypted.globalLocale.toLowerCase() != 'en' ||
          encrypted.gameLanguage.toLowerCase() != culture;
      if (changed) {
        await _writeEncryptedState(
          encrypted,
          globalLanguage: 'en',
          globalLocale: 'en',
          gameLanguage: culture,
        );
      }
      return LanguageSwitchResult(changed: changed, receipt: receipt);
    }

    return _ensurePlainCulture(culture, previous: previous);
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

    final normalizedKey = _normalizeKey(receipt.key);
    if (normalizedKey == _normalizeKey(_nteHybridKey)) {
      return _restoreHybrid(file, receipt);
    }
    if (normalizedKey == _normalizeKey(_nteEncryptedKey)) {
      return _restoreLegacyEncrypted(file, receipt);
    }
    return _restorePlain(file, receipt);
  }

  TextLanguageReceipt _hybridReceipt(
    _EncryptedState current,
    String culture,
    TextLanguageReceipt? previous,
  ) {
    if (previous != null &&
        p.equals(
          p.normalize(previous.configPath),
          p.normalize(current.file.path),
        )) {
      final key = _normalizeKey(previous.key);
      if (key == _normalizeKey(_nteHybridKey)) {
        return previous;
      }
      if (key == _normalizeKey(_nteEncryptedKey)) {
        final baseline = previous.previousValue.toLowerCase();
        if (_encryptedLanguageLines.containsKey(baseline) &&
            _encryptedLocaleLines.containsKey(baseline)) {
          return TextLanguageReceipt(
            configPath: current.file.path,
            key: _nteHybridKey,
            previousRawValue: jsonEncode({
              'globalLanguage': baseline,
              'globalLocale': baseline,
              'gameLanguage': baseline,
            }),
            previousValue: baseline,
            requestedCulture: culture,
          );
        }
      }
    }

    return TextLanguageReceipt(
      configPath: current.file.path,
      key: _nteHybridKey,
      previousRawValue: jsonEncode({
        'globalLanguage': current.globalLanguage,
        'globalLocale': current.globalLocale,
        'gameLanguage': current.gameLanguage,
      }),
      previousValue: current.gameLanguage,
      requestedCulture: culture,
    );
  }

  Future<LanguageRestoreResult> _restoreHybrid(
    File file,
    TextLanguageReceipt receipt,
  ) async {
    final current = await _detectEncryptedState(file);
    final baseline = _parseHybridBaseline(receipt.previousRawValue);
    if (current == null || baseline == null) {
      return const LanguageRestoreResult(
        restored: false,
        reason: 'O estado híbrido criptografado do NTE não pôde ser revalidado.',
      );
    }

    final requested = receipt.requestedCulture.toLowerCase();
    final currentTriplet = (
      current.globalLanguage.toLowerCase(),
      current.globalLocale.toLowerCase(),
      current.gameLanguage.toLowerCase(),
    );
    final expectedHybrid = ('en', 'en', requested);
    final expectedAfterGame = (requested, requested, requested);
    if (currentTriplet != expectedHybrid && currentTriplet != expectedAfterGame) {
      return const LanguageRestoreResult(
        restored: false,
        reason:
            'O idioma foi alterado depois da instalação; a escolha atual foi preservada.',
        preservedUserChoice: true,
      );
    }

    await _writeEncryptedState(
      current,
      globalLanguage: baseline.globalLanguage,
      globalLocale: baseline.globalLocale,
      gameLanguage: baseline.gameLanguage,
    );
    return const LanguageRestoreResult(restored: true);
  }

  Future<LanguageRestoreResult> _restoreLegacyEncrypted(
    File file,
    TextLanguageReceipt receipt,
  ) async {
    final current = await _detectEncryptedState(file);
    if (current == null) {
      return const LanguageRestoreResult(
        restored: false,
        reason: 'O idioma criptografado do NTE não pôde ser revalidado.',
      );
    }
    final requested = receipt.requestedCulture.toLowerCase();
    if (current.globalLanguage.toLowerCase() != requested ||
        current.globalLocale.toLowerCase() != requested ||
        current.gameLanguage.toLowerCase() != requested) {
      return const LanguageRestoreResult(
        restored: false,
        reason:
            'O idioma foi alterado depois da instalação; a escolha atual foi preservada.',
        preservedUserChoice: true,
      );
    }
    final previous = receipt.previousValue.toLowerCase();
    if (!_encryptedLanguageLines.containsKey(previous) ||
        !_encryptedLocaleLines.containsKey(previous)) {
      return const LanguageRestoreResult(
        restored: false,
        reason: 'A cultura anterior não é suportada para restauração.',
      );
    }
    await _writeEncryptedState(
      current,
      globalLanguage: previous,
      globalLocale: previous,
      gameLanguage: previous,
    );
    return const LanguageRestoreResult(restored: true);
  }

  Future<LanguageSwitchResult> _ensurePlainCulture(
    String culture, {
    TextLanguageReceipt? previous,
  }) async {
    final detected = await _detectPlain();
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
    await _replacePlainSetting(detected, culture);
    return LanguageSwitchResult(changed: true, receipt: receipt);
  }

  Future<LanguageRestoreResult> _restorePlain(
    File file,
    TextLanguageReceipt receipt,
  ) async {
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
    await _replacePlainSetting(
      current,
      receipt.previousRawValue,
      rawReplacement: true,
    );
    return const LanguageRestoreResult(restored: true);
  }

  Future<_EncryptedState?> _detectSingleEncryptedState() async {
    final found = <_EncryptedState>[];
    for (final file in _candidateFiles()) {
      if (!await file.exists() ||
          p.basename(file.path).toLowerCase() != 'gameusersettings.ini') {
        continue;
      }
      final state = await _detectEncryptedState(file);
      if (state != null) {
        found.add(state);
      }
    }
    return found.length == 1 ? found.single : null;
  }

  Future<_EncryptedState?> _detectEncryptedState(File file) async {
    final parsed = await _readUtf8Payload(file);
    if (parsed == null) {
      return null;
    }
    final lines = _splitLines(parsed.text);
    final languages = <(int, String)>[];
    final locales = <(int, String)>[];
    for (var index = 0; index < lines.length; index++) {
      final token = _withoutLineEnding(lines[index]).trim();
      final language = _encryptedLanguageLookup[token];
      if (language != null) {
        languages.add((index, language));
      }
      final locale = _encryptedLocaleLookup[token];
      if (locale != null) {
        locales.add((index, locale));
      }
    }

    // Real NTE layout: [Internationalization] Language, Locale, then later
    // [/Script/HTGame.HTGameUserSettings] Language.
    if (languages.length != 2 || locales.length != 1) {
      return null;
    }
    if (!(languages[0].$1 < locales[0].$1 &&
        locales[0].$1 < languages[1].$1)) {
      return null;
    }
    return _EncryptedState(
      file: file,
      parsed: parsed,
      lines: lines,
      globalLanguageIndex: languages[0].$1,
      globalLocaleIndex: locales[0].$1,
      gameLanguageIndex: languages[1].$1,
      globalLanguage: languages[0].$2,
      globalLocale: locales[0].$2,
      gameLanguage: languages[1].$2,
    );
  }

  Future<void> _writeEncryptedState(
    _EncryptedState state, {
    required String globalLanguage,
    required String globalLocale,
    required String gameLanguage,
  }) async {
    final globalLanguageToken =
        _encryptedLanguageLines[globalLanguage.toLowerCase()];
    final globalLocaleToken = _encryptedLocaleLines[globalLocale.toLowerCase()];
    final gameLanguageToken =
        _encryptedLanguageLines[gameLanguage.toLowerCase()];
    if (globalLanguageToken == null ||
        globalLocaleToken == null ||
        gameLanguageToken == null) {
      throw const FormatException(
        'Uma das culturas solicitadas não é suportada pelo GameUserSettings criptografado.',
      );
    }

    final current = await _detectEncryptedState(state.file);
    if (current == null) {
      throw const FormatException(
        'Layout criptografado do GameUserSettings mudou durante a operação.',
      );
    }
    final lines = List<String>.from(current.lines);
    void replace(int index, String token) {
      final body = _withoutLineEnding(lines[index]);
      final ending = lines[index].substring(body.length);
      lines[index] = '$token$ending';
    }

    replace(current.globalLanguageIndex, globalLanguageToken);
    replace(current.globalLocaleIndex, globalLocaleToken);
    replace(current.gameLanguageIndex, gameLanguageToken);
    await _writeAtomic(
      current.file,
      current.parsed.bom,
      utf8.encode(lines.join()),
    );
  }

  _HybridBaseline? _parseHybridBaseline(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) {
        return null;
      }
      final globalLanguage =
          value['globalLanguage']?.toString().toLowerCase() ?? '';
      final globalLocale =
          value['globalLocale']?.toString().toLowerCase() ?? '';
      final gameLanguage =
          value['gameLanguage']?.toString().toLowerCase() ?? '';
      if (!_encryptedLanguageLines.containsKey(globalLanguage) ||
          !_encryptedLocaleLines.containsKey(globalLocale) ||
          !_encryptedLanguageLines.containsKey(gameLanguage)) {
        return null;
      }
      return _HybridBaseline(globalLanguage, globalLocale, gameLanguage);
    } on FormatException {
      return null;
    }
  }

  Future<_DetectedSetting?> _detectPlain() async {
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
    return best.length == 1 ? best.single : null;
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
      p.join(base, 'Saved_GlobalSteam', 'Config', 'Windows'),
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
      p.join(local, 'HT', 'Saved_GlobalSteam', 'Config', 'Windows'),
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

  Future<_Utf8Payload?> _readUtf8Payload(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      try {
        return _Utf8Payload(
          utf8.decode(bytes.sublist(3)),
          const [0xef, 0xbb, 0xbf],
        );
      } on FormatException {
        return null;
      }
    }
    try {
      return _Utf8Payload(utf8.decode(bytes), const []);
    } on FormatException {
      return null;
    }
  }

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

  Future<void> _replacePlainSetting(
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
    await _writeAtomic(setting.file, current.bom, payload);
  }

  Future<void> _writeAtomic(
    File file,
    List<int> bom,
    List<int> payload,
  ) async {
    final temporary = File('${file.path}.nte-new');
    if (await temporary.exists()) {
      await temporary.delete();
    }
    await temporary.writeAsBytes([...bom, ...payload], flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
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

class _Utf8Payload {
  const _Utf8Payload(this.text, this.bom);

  final String text;
  final List<int> bom;
}

class _EncryptedState {
  const _EncryptedState({
    required this.file,
    required this.parsed,
    required this.lines,
    required this.globalLanguageIndex,
    required this.globalLocaleIndex,
    required this.gameLanguageIndex,
    required this.globalLanguage,
    required this.globalLocale,
    required this.gameLanguage,
  });

  final File file;
  final _Utf8Payload parsed;
  final List<String> lines;
  final int globalLanguageIndex;
  final int globalLocaleIndex;
  final int gameLanguageIndex;
  final String globalLanguage;
  final String globalLocale;
  final String gameLanguage;
}

class _HybridBaseline {
  const _HybridBaseline(
    this.globalLanguage,
    this.globalLocale,
    this.gameLanguage,
  );

  final String globalLanguage;
  final String globalLocale;
  final String gameLanguage;
}

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
