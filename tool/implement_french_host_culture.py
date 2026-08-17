from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


def patch_manifest() -> None:
    path = "lib/models/translation_manifest.dart"
    text = read(path)
    text = once(
        text,
        "    this.gameBuildId,\n    this.sourceHash,\n  });\n",
        "    this.gameBuildId,\n    this.sourceHash,\n    this.localization,\n  });\n",
        "manifest constructor localization",
    )
    text = once(
        text,
        "  final String? gameBuildId;\n  final String? sourceHash;\n\n",
        "  final String? gameBuildId;\n  final String? sourceHash;\n  final TranslationLocalization? localization;\n\n",
        "manifest localization field",
    )
    text = once(
        text,
        "      sourceHash: _optionalSha256(json['sourceHash']),\n      files: (json['files'] as List<dynamic>)\n",
        "      sourceHash: _optionalSha256(json['sourceHash']),\n      localization: json['localization'] == null\n          ? null\n          : TranslationLocalization.fromJson(\n              json['localization'] as Map<String, dynamic>,\n            ),\n      files: (json['files'] as List<dynamic>)\n",
        "manifest parse localization",
    )
    text += r'''

class TranslationLocalization {
  const TranslationLocalization({
    required this.sourceCulture,
    required this.installationCulture,
    required this.targetLanguage,
    required this.hostCompatible,
    required this.hostLocresSha256,
  });

  final String sourceCulture;
  final String installationCulture;
  final String targetLanguage;
  final bool hostCompatible;
  final String hostLocresSha256;

  factory TranslationLocalization.fromJson(Map<String, dynamic> json) {
    final value = TranslationLocalization(
      sourceCulture: json['sourceCulture'] as String,
      installationCulture: json['installationCulture'] as String,
      targetLanguage: json['targetLanguage'] as String,
      hostCompatible: json['hostCompatible'] as bool,
      hostLocresSha256: (json['hostLocresSha256'] as String).toLowerCase(),
    );
    value.validate();
    return value;
  }

  void validate() {
    if (sourceCulture != 'en' ||
        installationCulture != 'fr' ||
        targetLanguage != 'pt-BR' ||
        !hostCompatible ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hostLocresSha256)) {
      throw const FormatException(
        'Metadados de cultura da tradução não são suportados.',
      );
    }
  }
}
'''
    write(path, text)


def patch_receipt() -> None:
    path = "lib/models/install_receipt.dart"
    text = read(path)
    text = once(
        text,
        "    this.gameBuildId,\n    this.sourceHash,\n  });\n",
        "    this.gameBuildId,\n    this.sourceHash,\n    this.textLanguage,\n  });\n",
        "receipt constructor language",
    )
    text = once(
        text,
        "  final String? sourceHash;\n  final List<InstalledFileReceipt> files;\n",
        "  final String? sourceHash;\n  final TextLanguageReceipt? textLanguage;\n  final List<InstalledFileReceipt> files;\n",
        "receipt language field",
    )
    text = once(
        text,
        "      sourceHash: _optionalHash(json['sourceHash']),\n      files: files,\n",
        "      sourceHash: _optionalHash(json['sourceHash']),\n      textLanguage: json['textLanguage'] == null\n          ? null\n          : TextLanguageReceipt.fromJson(\n              json['textLanguage'] as Map<String, dynamic>,\n            ),\n      files: files,\n",
        "receipt parse language",
    )
    text = once(
        text,
        "    if (sourceHash != null) 'sourceHash': sourceHash,\n    'files': files.map((file) => file.toJson()).toList(growable: false),\n",
        "    if (sourceHash != null) 'sourceHash': sourceHash,\n    if (textLanguage != null) 'textLanguage': textLanguage!.toJson(),\n    'files': files.map((file) => file.toJson()).toList(growable: false),\n",
        "receipt serialize language",
    )
    marker = "\nclass InstalledFileReceipt {\n"
    language_class = r'''

class TextLanguageReceipt {
  const TextLanguageReceipt({
    required this.configPath,
    required this.key,
    required this.previousRawValue,
    required this.previousValue,
    required this.requestedCulture,
  });

  final String configPath;
  final String key;
  final String previousRawValue;
  final String previousValue;
  final String requestedCulture;

  factory TextLanguageReceipt.fromJson(Map<String, dynamic> json) {
    final value = TextLanguageReceipt(
      configPath: _requiredString(json, 'configPath'),
      key: _requiredString(json, 'key'),
      previousRawValue: _requiredString(json, 'previousRawValue'),
      previousValue: _requiredString(json, 'previousValue'),
      requestedCulture: _requiredString(json, 'requestedCulture'),
    );
    if (value.requestedCulture != 'fr' ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value.key)) {
      throw const ReceiptFormatException(
        'Metadados de idioma textual inválidos no recibo.',
      );
    }
    return value;
  }

  Map<String, dynamic> toJson() => {
    'configPath': configPath,
    'key': key,
    'previousRawValue': previousRawValue,
    'previousValue': previousValue,
    'requestedCulture': requestedCulture,
  };
}
'''
    text = once(text, marker, language_class + marker, "receipt language class")
    write(path, text)


def patch_installation() -> None:
    path = "lib/services/installation_service.dart"
    text = read(path)
    text = once(
        text,
        "import 'file_integrity_service.dart';\n",
        "import 'file_integrity_service.dart';\nimport 'game_language_service.dart';\n",
        "installation language import",
    )
    text = once(
        text,
        "    ReceiptRepository? receipts,\n    this.afterDestinationReplaced,\n  }) : integrity = integrity ?? FileIntegrityService(),\n",
        "    ReceiptRepository? receipts,\n    GameLanguageService? gameLanguage,\n    this.afterDestinationReplaced,\n  }) : integrity = integrity ?? FileIntegrityService(),\n",
        "installation constructor language",
    )
    text = once(
        text,
        "       safePaths = safePaths ?? SafePathService(),\n       receipts =\n",
        "       safePaths = safePaths ?? SafePathService(),\n       gameLanguage = gameLanguage ?? GameLanguageService(),\n       receipts =\n",
        "installation init language",
    )
    text = once(
        text,
        "  final ReceiptRepository receipts;\n  final Future<void> Function(File destination)? afterDestinationReplaced;\n",
        "  final ReceiptRepository receipts;\n  final GameLanguageService gameLanguage;\n  final Future<void> Function(File destination)? afterDestinationReplaced;\n",
        "installation language field",
    )
    text = once(
        text,
        "      Object? originalError;\n      StackTrace? originalStack;\n      try {\n",
        "      Object? originalError;\n      StackTrace? originalStack;\n      LanguageSwitchResult? languageSwitch;\n      try {\n",
        "installation switch state",
    )
    anchor = """        journal.state = 'destinations-validated';
        await _writeJournal(transaction, journal);

        await receipts.write(
"""
    replacement = """        journal.state = 'destinations-validated';
        await _writeJournal(transaction, journal);

        final installationCulture = manifest.localization?.installationCulture;
        if (installationCulture != null) {
          languageSwitch = await gameLanguage.ensureCulture(
            installationCulture,
            previous: previousReceipt?.textLanguage,
          );
          if (languageSwitch.changed) {
            await log.info(
              'Idioma textual do NTE alterado automaticamente para '
              '$installationCulture.',
            );
          } else if (languageSwitch.reason != null) {
            await log.info(
              'Idioma textual não foi alterado automaticamente: '
              '${languageSwitch.reason}',
            );
          }
        }

        await receipts.write(
"""
    text = once(text, anchor, replacement, "installation switch step")
    text = once(
        text,
        "            sourceHash: manifest.sourceHash,\n            files: receiptEntries,\n",
        "            sourceHash: manifest.sourceHash,\n            textLanguage: languageSwitch?.receipt ?? previousReceipt?.textLanguage,\n            files: receiptEntries,\n",
        "installation receipt language",
    )
    rollback_anchor = """        Object? rollbackError;
        try {
          journal.state = 'rollback-started';
"""
    rollback_replacement = """        Object? rollbackError;
        if (languageSwitch?.changed == true) {
          final languageRollback = await gameLanguage.restore(
            languageSwitch?.receipt,
          );
          if (!languageRollback.restored) {
            rollbackError = InstallationException(
              'A restauração do idioma textual ficou incompleta: '
              '${languageRollback.reason ?? 'motivo desconhecido'}.',
            );
          }
        }
        try {
          journal.state = 'rollback-started';
"""
    text = once(text, rollback_anchor, rollback_replacement, "installation language rollback")
    # Preserve an earlier language rollback failure if file rollback also fails.
    text = once(
        text,
        "        } catch (error, stackTrace) {\n          rollbackError = error;\n          await log.error(\n            'O rollback da instalação ficou incompleto.',\n",
        "        } catch (error, stackTrace) {\n          rollbackError ??= error;\n          await log.error(\n            'O rollback da instalação ficou incompleto.',\n",
        "rollback error preservation",
    )
    complete_anchor = """      final complete = preserved.isEmpty && failed.isEmpty;
      if (complete) {
        await receipts.deleteCurrent(gameDirectory);
"""
    complete_replacement = """      final complete = preserved.isEmpty && failed.isEmpty;
      if (complete) {
        final languageRestore = await gameLanguage.restore(receipt.textLanguage);
        if (languageRestore.restored) {
          await log.info('Idioma textual anterior do NTE restaurado.');
        } else if (languageRestore.preservedUserChoice) {
          await log.info(
            'Idioma textual atual foi preservado porque o usuário o alterou '
            'depois da instalação.',
          );
        } else if (receipt.textLanguage != null) {
          await log.info(
            'Não foi possível restaurar automaticamente o idioma textual: '
            '${languageRestore.reason ?? 'motivo desconhecido'}.',
          );
        }
        await receipts.deleteCurrent(gameDirectory);
"""
    text = once(text, complete_anchor, complete_replacement, "uninstall language restore")
    text = once(
        text,
        "            sourceHash: receipt.sourceHash,\n            files: receipt.files\n",
        "            sourceHash: receipt.sourceHash,\n            textLanguage: receipt.textLanguage,\n            files: receipt.files\n",
        "partial receipt language",
    )
    write(path, text)


def patch_test_support() -> None:
    path = "test/test_support.dart"
    text = read(path)
    text = once(
        text,
        "  List<List<int>>? contents,\n}) {\n",
        "  List<List<int>>? contents,\n  bool frenchHost = false,\n}) {\n",
        "test manifest host arg",
    )
    text = once(
        text,
        "    'publishedAt': (publishedAt ?? DateTime.utc(2026, 7, 29)).toIso8601String(),\n    'files': [\n",
        "    'publishedAt': (publishedAt ?? DateTime.utc(2026, 7, 29)).toIso8601String(),\n    if (frenchHost)\n      'localization': {\n        'sourceCulture': 'en',\n        'installationCulture': 'fr',\n        'targetLanguage': 'pt-BR',\n        'hostCompatible': true,\n        'hostLocresSha256': 'e' * 64,\n      },\n    'files': [\n",
        "test manifest localization",
    )
    write(path, text)


def add_tests() -> None:
    write(
        "test/game_language_service_test.dart",
        r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/game_language_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory config;
  late File ini;
  late GameLanguageService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-language-');
    config = Directory(
      p.join(
        sandbox.path,
        'HT',
        'Saved_Global',
        'Config',
        'Windows',
      ),
    );
    await config.create(recursive: true);
    ini = File(p.join(config.path, 'GameUserSettings.ini'));
    service = GameLanguageService(localAppData: sandbox.path);
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('switches text language without changing voice language', () async {
    await ini.writeAsString('[User]\r\nTextLanguage=en\r\nVoiceLanguage=ja\r\n');
    final result = await service.ensureCulture('fr');
    expect(result.changed, isTrue);
    expect(result.receipt?.previousValue, 'en');
    final current = await ini.readAsString();
    expect(current, contains('TextLanguage=fr'));
    expect(current, contains('VoiceLanguage=ja'));
  });

  test('restore changes only language and preserves later settings', () async {
    await ini.writeAsString('[User]\nTextLanguage=en\nQuality=2\n');
    final changed = await service.ensureCulture('fr');
    await ini.writeAsString(
      (await ini.readAsString()).replaceAll('Quality=2', 'Quality=4'),
    );
    final restored = await service.restore(changed.receipt);
    expect(restored.restored, isTrue);
    final current = await ini.readAsString();
    expect(current, contains('TextLanguage=en'));
    expect(current, contains('Quality=4'));
  });

  test('restore respects manual language change after install', () async {
    await ini.writeAsString('[User]\nTextLanguage=en\n');
    final changed = await service.ensureCulture('fr');
    await ini.writeAsString('[User]\nTextLanguage=de\n');
    final restored = await service.restore(changed.receipt);
    expect(restored.restored, isFalse);
    expect(restored.preservedUserChoice, isTrue);
    expect(await ini.readAsString(), contains('TextLanguage=de'));
  });

  test('voice-only config is never selected', () async {
    await ini.writeAsString('[User]\nVoiceLanguage=ja\n');
    final result = await service.ensureCulture('fr');
    expect(result.changed, isFalse);
    expect(result.receipt, isNull);
    expect(await ini.readAsString(), contains('VoiceLanguage=ja'));
  });

  test('ambiguous equal-priority text settings are not changed', () async {
    final second = Directory(
      p.join(sandbox.path, 'HT', 'Saved', 'Config', 'Windows'),
    );
    await second.create(recursive: true);
    await ini.writeAsString('[User]\nTextLanguage=en\n');
    await File(p.join(second.path, 'GameUserSettings.ini'))
        .writeAsString('[User]\nTextLanguage=en\n');
    final result = await service.ensureCulture('fr');
    expect(result.changed, isFalse);
    expect(result.receipt, isNull);
    expect(await ini.readAsString(), contains('TextLanguage=en'));
  });

  test('reinstall preserves the original language baseline', () async {
    await ini.writeAsString('[User]\nTextLanguage=en\n');
    final first = await service.ensureCulture('fr');
    final second = await service.ensureCulture('fr', previous: first.receipt);
    expect(second.changed, isFalse);
    expect(second.receipt?.previousValue, 'en');
    final restored = await service.restore(second.receipt);
    expect(restored.restored, isTrue);
    expect(await ini.readAsString(), contains('TextLanguage=en'));
  });

  test('preserves UTF-8 BOM state', () async {
    await ini.writeAsBytes([
      0xef,
      0xbb,
      0xbf,
      ...'[User]\nTextLanguage=en\n'.codeUnits,
    ]);
    final changed = await service.ensureCulture('fr');
    expect(changed.changed, isTrue);
    final bytes = await ini.readAsBytes();
    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
  });
}
''',
    )

    path = "test/translation_manifest_test.dart"
    text = read(path)
    marker = "\n  test('rejects duplicated destinations', () {\n"
    tests = r'''

  test('accepts French host-culture metadata', () {
    final json = manifestJson();
    json['localization'] = {
      'sourceCulture': 'en',
      'installationCulture': 'fr',
      'targetLanguage': 'pt-BR',
      'hostCompatible': true,
      'hostLocresSha256': 'e' * 64,
    };
    final manifest = TranslationManifest.fromJson(json);
    expect(manifest.localization?.installationCulture, 'fr');
    expect(manifest.localization?.targetLanguage, 'pt-BR');
  });

  test('rejects unsupported host-culture metadata', () {
    final json = manifestJson();
    json['localization'] = {
      'sourceCulture': 'en',
      'installationCulture': 'de',
      'targetLanguage': 'pt-BR',
      'hostCompatible': true,
      'hostLocresSha256': 'e' * 64,
    };
    expect(() => TranslationManifest.fromJson(json), throwsFormatException);
  });
'''
    text = once(text, marker, tests + marker, "manifest host tests")
    write(path, text)

    path = "test/receipt_repository_test.dart"
    text = read(path)
    marker = "\n  test('rejects receipt with an unsupported schema', () async {\n"
    test = r'''

  test('receipt keeps optional text-language rollback metadata', () async {
    final storage = await repository.storageFor(game.path);
    final receipt = validReceipt(
      game.path,
      textLanguage: const TextLanguageReceipt(
        configPath: r'C:\Users\Test\AppData\Local\HT\Saved_Global\Config\Windows\GameUserSettings.ini',
        key: 'TextLanguage',
        previousRawValue: 'en',
        previousValue: 'en',
        requestedCulture: 'fr',
      ),
    );
    await repository.write(game.path, receipt);
    final read = (await repository.read(game.path)).receipt;
    expect(read?.textLanguage?.previousValue, 'en');
    expect(await storage.receipt.exists(), isTrue);
  });
'''
    text = once(text, marker, test + marker, "receipt language test")
    # Extend the local validReceipt helper only if it has the expected signature.
    text = once(
        text,
        "InstallReceipt validReceipt(String gameDirectory) => InstallReceipt(\n",
        "InstallReceipt validReceipt(\n  String gameDirectory, {\n  TextLanguageReceipt? textLanguage,\n}) => InstallReceipt(\n",
        "receipt helper signature",
    )
    text = once(
        text,
        "  sourceHash: 'b' * 64,\n  files: [\n",
        "  sourceHash: 'b' * 64,\n  textLanguage: textLanguage,\n  files: [\n",
        "receipt helper metadata",
    )
    write(path, text)

    path = "test/installation_service_test.dart"
    text = read(path)
    text = once(
        text,
        "import 'package:nte_translation_launcher/services/file_integrity_service.dart';\n",
        "import 'package:nte_translation_launcher/services/file_integrity_service.dart';\nimport 'package:nte_translation_launcher/services/game_language_service.dart';\n",
        "installation test language import",
    )
    marker = "\n  test('preserves and restores an original file', () async {\n"
    tests = r'''

  test('French-host install switches text language and uninstall restores it', () async {
    final configRoot = Directory(
      p.join(
        sandbox.path,
        'local-app-data',
        'HT',
        'Saved_Global',
        'Config',
        'Windows',
      ),
    );
    await configRoot.create(recursive: true);
    final ini = File(p.join(configRoot.path, 'GameUserSettings.ini'));
    await ini.writeAsString(
      '[User]\nTextLanguage=en\nVoiceLanguage=ja\nQuality=2\n',
    );
    final frenchService = InstallationService(
      paths,
      LauncherLog(paths.logFile),
      integrity: FileIntegrityService(),
      safePaths: SafePathService(),
      receipts: receipts,
      gameLanguage: GameLanguageService(
        localAppData: p.join(sandbox.path, 'local-app-data'),
      ),
    );
    final frenchManifest = testManifest(contents: contents, frenchHost: true);
    final frenchStage = await createStage(sandbox, frenchManifest, contents);

    await frenchService.install(frenchManifest, frenchStage, game.path);
    var current = await ini.readAsString();
    expect(current, contains('TextLanguage=fr'));
    expect(current, contains('VoiceLanguage=ja'));
    expect((await receipts.read(game.path)).receipt?.textLanguage, isNotNull);

    await ini.writeAsString(current.replaceAll('Quality=2', 'Quality=4'));
    final removal = await frenchService.uninstall(game.path);
    expect(removal.complete, isTrue);
    current = await ini.readAsString();
    expect(current, contains('TextLanguage=en'));
    expect(current, contains('VoiceLanguage=ja'));
    expect(current, contains('Quality=4'));
  });

  test('legacy manifest without localization metadata does not touch language', () async {
    final configRoot = Directory(
      p.join(
        sandbox.path,
        'local-app-data',
        'HT',
        'Saved_Global',
        'Config',
        'Windows',
      ),
    );
    await configRoot.create(recursive: true);
    final ini = File(p.join(configRoot.path, 'GameUserSettings.ini'));
    await ini.writeAsString('[User]\nTextLanguage=en\n');
    final legacyService = InstallationService(
      paths,
      LauncherLog(paths.logFile),
      safePaths: SafePathService(),
      receipts: receipts,
      gameLanguage: GameLanguageService(
        localAppData: p.join(sandbox.path, 'local-app-data'),
      ),
    );

    await legacyService.install(manifest, stage, game.path);
    expect(await ini.readAsString(), contains('TextLanguage=en'));
    expect((await receipts.read(game.path)).receipt?.textLanguage, isNull);
  });
'''
    text = once(text, marker, tests + marker, "installation language tests")
    write(path, text)


def add_docs() -> None:
    write(
        "docs/FRENCH_HOST_CULTURE.md",
        r'''# PT-BR hospedado no slot francês

Novas releases podem declarar no `translation_manifest.json`:

```json
{
  "localization": {
    "sourceCulture": "en",
    "installationCulture": "fr",
    "targetLanguage": "pt-BR",
    "hostCompatible": true,
    "hostLocresSha256": "..."
  }
}
```

O launcher mantém compatibilidade com manifests antigos sem `localization`. Nesses manifests, nenhuma preferência de idioma é alterada.

Para uma release explicitamente marcada como `en -> pt-BR` hospedada em `fr`, a instalação tenta localizar uma configuração textual já existente do NTE em `%LOCALAPPDATA%/HT/.../Config/...` e mudar somente uma chave reconhecida de idioma de texto/interface/cultura para `fr`.

Regras de segurança:

- nunca altera chaves contendo `voice`, `audio`, `dub` ou `speech`;
- nunca inventa uma chave se nenhuma configuração segura existir;
- se houver candidatos igualmente plausíveis, não altera nenhum;
- guarda no recibo apenas os metadados necessários para desfazer a alteração;
- a desinstalação restaura somente a linha do idioma, preservando gráficos/controles alterados depois;
- se o usuário mudar manualmente o idioma depois da instalação, a desinstalação preserva essa escolha;
- uma reinstalação mantém a preferência original registrada na primeira instalação.

A mudança automática é um conforto. A ausência de uma chave detectável não bloqueia a instalação da tradução; nesse caso o usuário pode selecionar francês manualmente.
''',
    )


def main() -> None:
    patch_manifest()
    patch_receipt()
    patch_installation()
    patch_test_support()
    add_tests()
    add_docs()
    print("French host culture launcher integration applied.")


if __name__ == "__main__":
    main()
