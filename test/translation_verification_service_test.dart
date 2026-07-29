import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/install_receipt.dart';
import 'package:nte_translation_launcher/models/loaded_translation_manifest.dart';
import 'package:nte_translation_launcher/models/translation_installation.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/file_integrity_service.dart';
import 'package:nte_translation_launcher/services/receipt_repository.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:nte_translation_launcher/services/translation_verification_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory sandbox;
  late Directory game;
  late AppPaths paths;
  late ReceiptRepository receipts;
  late TranslationVerificationService verifier;
  late TranslationManifest manifest;
  const contents = [
    [1, 2, 3],
    [4, 5, 6, 7],
  ];

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-verifier-');
    game = await createGame(sandbox, 'game');
    paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    final safePaths = SafePathService();
    final log = LauncherLog(paths.logFile);
    receipts = ReceiptRepository(paths, log, safePaths);
    verifier = TranslationVerificationService(
      integrity: FileIntegrityService(),
      receipts: receipts,
      safePaths: safePaths,
      log: log,
    );
    manifest = testManifest(contents: contents);
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('reports all real files as current when size and hash match', () async {
    await _writeManifestFiles(game, manifest, contents);
    final progress = <int>[];
    final result = await verifier.verify(
      loadedManifest: loaded(manifest),
      gameDirectory: game.path,
      onProgress: (_, verified, _) => progress.add(verified),
    );
    expect(result.status, TranslationInstallationStatus.installedCurrent);
    expect(result.validFiles, hasLength(2));
    expect(progress, [1, 2]);
  });

  test('reports not installed when no translation file exists', () async {
    final result = await verifier.verify(
      loadedManifest: loaded(manifest),
      gameDirectory: game.path,
    );
    expect(result.status, TranslationInstallationStatus.notInstalled);
    expect(result.missingFiles, hasLength(2));
  });

  test('treats only an original version.dll as a clean installation', () async {
    final versionManifest = TranslationManifest.fromJson({
      'schemaVersion': 1,
      'translationVersion': 'current',
      'publishedAt': '2026-07-29T00:00:00Z',
      'files': [
        {
          'name': 'version.dll',
          'relativeDestination': 'Client/Binaries/version.dll',
          'url': 'https://github.com/example/version.dll',
          'size': 3,
          'sha256': hashOf([1, 2, 3]),
        },
        {
          'name': 'translation.pak',
          'relativeDestination': 'Client/Paks/translation.pak',
          'url': 'https://github.com/example/translation.pak',
          'size': 3,
          'sha256': hashOf([4, 5, 6]),
        },
      ],
    });
    final originalDll = File(p.join(game.path, 'Client/Binaries/version.dll'));
    await originalDll.parent.create(recursive: true);
    await originalDll.writeAsBytes([9, 9, 9]);

    final result = await verifier.verify(
      loadedManifest: loaded(versionManifest),
      gameDirectory: game.path,
    );

    expect(result.status, TranslationInstallationStatus.notInstalled);
    expect(result.hasInstalledFiles, isFalse);
  });

  test(
    'does not treat several unknown modified files as a clean game',
    () async {
      await _writeManifestFiles(game, manifest, const [
        [9, 9, 9],
        [8, 8, 8, 8],
      ]);
      final result = await verifier.verify(
        loadedManifest: loaded(manifest),
        gameDirectory: game.path,
      );
      expect(result.status, TranslationInstallationStatus.modified);
      expect(result.receiptVersion, isNull);
    },
  );

  test('reports incomplete when only part of the files exists', () async {
    await _writeOne(game, manifest.files.first, contents.first);
    final result = await verifier.verify(
      loadedManifest: loaded(manifest),
      gameDirectory: game.path,
    );
    expect(result.status, TranslationInstallationStatus.incomplete);
    expect(result.validFiles, hasLength(1));
    expect(result.missingFiles, hasLength(1));
  });

  test(
    'keeps a receipt-backed fully missing installation repairable',
    () async {
      await _writeReceipt(receipts, game, manifest, contents);
      final result = await verifier.verify(
        loadedManifest: loaded(manifest),
        gameDirectory: game.path,
      );
      expect(result.status, TranslationInstallationStatus.incomplete);
      expect(result.receiptVersion, manifest.translationVersion);
    },
  );

  test('reports modified for a divergent size', () async {
    await _writeManifestFiles(game, manifest, contents);
    await _writeOne(game, manifest.files.first, [9]);
    final result = await verifier.verify(
      loadedManifest: loaded(manifest),
      gameDirectory: game.path,
    );
    expect(result.status, TranslationInstallationStatus.modified);
    expect(
      result.modifiedFiles,
      contains(manifest.files.first.relativeDestination),
    );
  });

  test('reports modified for same size and divergent SHA-256', () async {
    await _writeManifestFiles(game, manifest, contents);
    await _writeOne(game, manifest.files.first, [9, 9, 9]);
    final result = await verifier.verify(
      loadedManifest: loaded(manifest),
      gameDirectory: game.path,
    );
    expect(result.status, TranslationInstallationStatus.modified);
  });

  test('reports a missing game directory as unverifiable', () async {
    final result = await verifier.verify(
      loadedManifest: loaded(manifest),
      gameDirectory: p.join(sandbox.path, 'removed'),
    );
    expect(result.status, TranslationInstallationStatus.unverifiable);
  });

  test(
    'proves an older receipt is outdated only with newer remote date',
    () async {
      final oldManifest = testManifest(
        version: 'old',
        publishedAt: DateTime.utc(2026, 7, 28),
        contents: const [
          [8, 8, 8],
          [7, 7, 7, 7],
        ],
      );
      const oldContents = [
        [8, 8, 8],
        [7, 7, 7, 7],
      ];
      await _writeManifestFiles(game, oldManifest, oldContents);
      await _writeReceipt(receipts, game, oldManifest, oldContents);

      final result = await verifier.verify(
        loadedManifest: loaded(manifest),
        gameDirectory: game.path,
      );

      expect(result.status, TranslationInstallationStatus.installedOutdated);
      expect(result.detectedVersion, 'old');
    },
  );

  for (final source in [ManifestSource.cache, ManifestSource.bundled]) {
    test('${source.name} does not downgrade a valid newer receipt', () async {
      final newer = testManifest(
        version: 'future',
        publishedAt: DateTime.utc(2026, 7, 30),
        contents: const [
          [8, 8, 8],
          [7, 7, 7, 7],
        ],
      );
      const newerContents = [
        [8, 8, 8],
        [7, 7, 7, 7],
      ];
      await _writeManifestFiles(game, newer, newerContents);
      await _writeReceipt(receipts, game, newer, newerContents);
      final result = await verifier.verify(
        loadedManifest: loaded(manifest, source: source),
        gameDirectory: game.path,
      );
      expect(result.status, TranslationInstallationStatus.installedCurrent);
      expect(result.detectedVersion, 'future');
    });
  }

  test(
    'different version without newer publication proof is not updated',
    () async {
      final other = testManifest(
        version: 'other',
        publishedAt: manifest.publishedAt,
        contents: const [
          [8, 8, 8],
          [7, 7, 7, 7],
        ],
      );
      const otherContents = [
        [8, 8, 8],
        [7, 7, 7, 7],
      ];
      await _writeManifestFiles(game, other, otherContents);
      await _writeReceipt(receipts, game, other, otherContents);
      final result = await verifier.verify(
        loadedManifest: loaded(manifest),
        gameDirectory: game.path,
      );
      expect(result.status, TranslationInstallationStatus.installedCurrent);
      expect(result.detectedVersion, 'other');
    },
  );

  test(
    'same receipt version with divergent recorded hashes is modified',
    () async {
      const recordedContents = [
        [8, 8, 8],
        [7, 7, 7, 7],
      ];
      await _writeManifestFiles(game, manifest, recordedContents);
      await _writeReceipt(receipts, game, manifest, recordedContents);

      final result = await verifier.verify(
        loadedManifest: loaded(manifest),
        gameDirectory: game.path,
      );

      expect(result.status, TranslationInstallationStatus.modified);
    },
  );

  test('detects a receipt managed in another directory', () async {
    final other = await createGame(sandbox, 'other');
    await _writeReceipt(receipts, other, manifest, contents);
    final result = await verifier.verify(
      loadedManifest: loaded(manifest),
      gameDirectory: game.path,
    );
    expect(
      result.status,
      TranslationInstallationStatus.managedInAnotherDirectory,
    );
    expect(result.managedDirectory, isNotNull);
  });

  test('invalid receipt makes the installation unverifiable', () async {
    final storage = await receipts.storageFor(game.path);
    await storage.root.create(recursive: true);
    await storage.receipt.writeAsString('{');
    final result = await verifier.verify(
      loadedManifest: loaded(manifest),
      gameDirectory: game.path,
    );
    expect(result.status, TranslationInstallationStatus.unverifiable);
  });
}

Future<void> _writeReceipt(
  ReceiptRepository receipts,
  Directory target,
  TranslationManifest value,
  List<List<int>> bytes,
) async {
  final storage = await receipts.storageFor(target.path);
  await receipts.write(
    target.path,
    InstallReceipt(
      schemaVersion: InstallReceipt.currentSchemaVersion,
      translationVersion: value.translationVersion,
      installedAt: DateTime.utc(2026, 7, 29),
      gameDirectory: storage.gameDirectory,
      manifestPublishedAt: value.publishedAt,
      files: [
        for (var index = 0; index < value.files.length; index++)
          InstalledFileReceipt(
            relativePath: value.files[index].relativeDestination,
            installedSize: bytes[index].length,
            installedSha256: hashOf(bytes[index]),
            originalExisted: false,
          ),
      ],
    ),
  );
}

Future<void> _writeManifestFiles(
  Directory game,
  TranslationManifest manifest,
  List<List<int>> contents,
) async {
  for (var index = 0; index < manifest.files.length; index++) {
    await _writeOne(game, manifest.files[index], contents[index]);
  }
}

Future<void> _writeOne(
  Directory game,
  TranslationFile file,
  List<int> contents,
) async {
  final destination = File(p.join(game.path, file.relativeDestination));
  await destination.parent.create(recursive: true);
  await destination.writeAsBytes(contents);
}
