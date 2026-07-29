import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nte_translation_launcher/models/loaded_translation_manifest.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:path/path.dart' as p;

String hashOf(List<int> bytes) => sha256.convert(bytes).toString();

TranslationManifest testManifest({
  String version = 'nte-auto-20260729-current',
  DateTime? publishedAt,
  List<List<int>>? contents,
}) {
  final values =
      contents ??
      const [
        [1, 2, 3],
        [4, 5, 6, 7],
      ];
  return TranslationManifest.fromJson({
    'schemaVersion': 1,
    'translationVersion': version,
    'publishedAt': (publishedAt ?? DateTime.utc(2026, 7, 29)).toIso8601String(),
    'files': [
      for (var index = 0; index < values.length; index++)
        {
          'name': 'translation-$index.bin',
          'relativeDestination': 'Client/Content/Paks/translation-$index.bin',
          'url':
              'https://github.com/example/releases/download/$version/'
              'translation-$index.bin',
          'size': values[index].length,
          'sha256': hashOf(values[index]),
        },
    ],
  });
}

LoadedTranslationManifest loaded(
  TranslationManifest manifest, {
  ManifestSource source = ManifestSource.remote,
}) => LoadedTranslationManifest(manifest: manifest, source: source);

Future<Directory> createGame(Directory root, String name) async {
  final game = Directory(p.join(root.path, name));
  await game.create(recursive: true);
  await File(p.join(game.path, 'NTEGlobalLauncher.exe')).writeAsBytes([77, 90]);
  return game;
}

Future<Directory> createStage(
  Directory root,
  TranslationManifest manifest,
  List<List<int>> contents,
) async {
  final stage = Directory(
    p.join(root.path, 'stage-${manifest.translationVersion}'),
  );
  await stage.create(recursive: true);
  for (var index = 0; index < manifest.files.length; index++) {
    await File(
      p.join(stage.path, manifest.files[index].name),
    ).writeAsBytes(contents[index]);
  }
  return stage;
}
