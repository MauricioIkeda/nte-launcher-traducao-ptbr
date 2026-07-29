import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/install_receipt.dart';
import 'package:nte_translation_launcher/services/receipt_repository.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late AppPaths paths;
  late ReceiptRepository repository;
  late Directory gameA;
  late Directory gameB;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-receipt-');
    paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    repository = ReceiptRepository(
      paths,
      LauncherLog(paths.logFile),
      SafePathService(),
    );
    gameA = Directory(p.join(sandbox.path, 'game-a'));
    gameB = Directory(p.join(sandbox.path, 'game-b'));
    await gameA.create();
    await gameB.create();
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('writes and reads a versioned receipt atomically', () async {
    final receipt = await _receipt(repository, gameA.path);
    await repository.write(gameA.path, receipt);

    final result = await repository.read(gameA.path);

    expect(result.receipt?.translationVersion, 'v-current');
    expect(
      await File(
        '${(await repository.storageFor(gameA.path)).receipt.path}.tmp',
      ).exists(),
      isFalse,
    );
  });

  test(
    'two game directories use independent receipt and backup roots',
    () async {
      final first = await repository.storageFor(gameA.path);
      final second = await repository.storageFor(gameB.path);
      expect(first.id, isNot(second.id));
      expect(first.receipt.path, isNot(second.receipt.path));
      expect(first.originals.path, isNot(second.originals.path));
    },
  );

  test('equivalent Windows paths produce the same installation id', () async {
    if (!Platform.isWindows) {
      return;
    }
    final first = await repository.storageFor(gameA.path);
    final second = await repository.storageFor('${gameA.path.toUpperCase()}\\');
    expect(first.id, second.id);
  });

  test('rejects a receipt that belongs to another directory', () async {
    final storage = await repository.storageFor(gameA.path);
    await storage.root.create(recursive: true);
    final receipt = await _receipt(repository, gameB.path);
    await storage.receipt.writeAsString(jsonEncode(receipt.toJson()));

    final result = await repository.read(gameA.path);

    expect(result.isInvalid, isTrue);
    expect(result.receipt, isNull);
  });

  for (final source in ['', '{', '[]', '{"schemaVersion":999}']) {
    test('handles invalid or truncated receipt: $source', () async {
      final storage = await repository.storageFor(gameA.path);
      await storage.root.create(recursive: true);
      await storage.receipt.writeAsString(source);
      final result = await repository.read(gameA.path);
      expect(result.isInvalid, isTrue);
    });
  }

  test('detects an abandoned temporary receipt', () async {
    final storage = await repository.storageFor(gameA.path);
    await storage.root.create(recursive: true);
    await File('${storage.receipt.path}.tmp').writeAsString('{}');
    final result = await repository.read(gameA.path);
    expect(result.temporaryReceiptFound, isTrue);
  });

  test(
    'restores the last valid receipt after an interrupted replacement',
    () async {
      final storage = await repository.storageFor(gameA.path);
      await storage.root.create(recursive: true);
      final receipt = await _receipt(repository, gameA.path);
      await File(
        '${storage.receipt.path}.previous',
      ).writeAsString(jsonEncode(receipt.toJson()));

      final result = await repository.read(gameA.path);

      expect(result.receipt?.translationVersion, 'v-current');
      expect(await storage.receipt.exists(), isTrue);
    },
  );

  test('rejects duplicate and unsafe receipt destinations', () async {
    final receipt = await _receipt(repository, gameA.path);
    final json = receipt.toJson();
    final files = List<dynamic>.from(json['files'] as List<dynamic>);
    json['files'] = files;
    files.add(Map<String, dynamic>.from(files.first as Map));
    final storage = await repository.storageFor(gameA.path);
    await storage.root.create(recursive: true);
    await storage.receipt.writeAsString(jsonEncode(json));
    expect((await repository.read(gameA.path)).isInvalid, isTrue);

    (files.first as Map<String, dynamic>)['relativePath'] = '../evil.bin';
    files.removeLast();
    await storage.receipt.writeAsString(jsonEncode(json));
    expect((await repository.read(gameA.path)).isInvalid, isTrue);
  });
}

Future<InstallReceipt> _receipt(
  ReceiptRepository repository,
  String gameDirectory,
) async {
  final storage = await repository.storageFor(gameDirectory);
  return InstallReceipt(
    schemaVersion: InstallReceipt.currentSchemaVersion,
    translationVersion: 'v-current',
    installedAt: DateTime.utc(2026, 7, 29),
    gameDirectory: storage.gameDirectory,
    manifestPublishedAt: DateTime.utc(2026, 7, 29),
    files: const [
      InstalledFileReceipt(
        relativePath: 'Client/file.bin',
        installedSize: 3,
        installedSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        originalExisted: false,
      ),
    ],
  );
}
