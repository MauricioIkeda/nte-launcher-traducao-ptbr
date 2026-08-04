import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/file_integrity_service.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:nte_translation_launcher/services/receipt_repository.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory sandbox;
  late Directory game;
  late AppPaths paths;
  late ReceiptRepository receipts;
  late InstallationService service;
  late TranslationManifest manifest;
  late Directory stage;
  const contents = [
    [1, 2, 3],
    [4, 5, 6, 7],
  ];

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-installation-');
    game = await createGame(sandbox, 'game');
    paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    final log = LauncherLog(paths.logFile);
    final safePaths = SafePathService();
    receipts = ReceiptRepository(paths, log, safePaths);
    service = InstallationService(
      paths,
      log,
      integrity: FileIntegrityService(),
      safePaths: safePaths,
      receipts: receipts,
    );
    manifest = testManifest(contents: contents);
    stage = await createStage(sandbox, manifest, contents);
  });

  test(
    'nested launcher selection installs into the real client root',
    () async {
      await File(
        p.join(game.path, InstallationService.gameExecutable),
      ).delete();
      final nested = Directory(p.join(game.path, 'NTEGlobal'));
      await nested.create();
      await File(
        p.join(nested.path, InstallationService.gameExecutable),
      ).writeAsBytes(const [77, 90]);

      await service.install(manifest, stage, nested.path);

      expect(
        File(
          p.join(game.path, manifest.files.first.relativeDestination),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(nested.path, manifest.files.first.relativeDestination),
        ).existsSync(),
        isFalse,
      );
      expect((await receipts.read(game.path)).receipt, isNotNull);
    },
  );

  tearDown(() => sandbox.delete(recursive: true));

  test(
    'successful install validates destinations and writes receipt last',
    () async {
      await service.install(manifest, stage, game.path);

      final receipt = (await receipts.read(game.path)).receipt;
      expect(receipt?.translationVersion, manifest.translationVersion);
      expect(receipt?.files, hasLength(2));
      for (var index = 0; index < manifest.files.length; index++) {
        expect(
          await File(
            p.join(game.path, manifest.files[index].relativeDestination),
          ).readAsBytes(),
          contents[index],
        );
      }
    },
  );

  test('preserves and restores an original file', () async {
    final destination = File(
      p.join(game.path, manifest.files.first.relativeDestination),
    );
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes([9, 8, 7]);

    await service.install(manifest, stage, game.path);
    final result = await service.uninstall(game.path);

    expect(result.complete, isTrue);
    expect(await destination.readAsBytes(), [9, 8, 7]);
  });

  test('removes an installed file that had no original', () async {
    await service.install(manifest, stage, game.path);
    final destination = File(
      p.join(game.path, manifest.files.last.relativeDestination),
    );
    await service.uninstall(game.path);
    expect(await destination.exists(), isFalse);
  });

  test('invalid stage file stops before a definitive receipt', () async {
    await File(p.join(stage.path, manifest.files.first.name)).writeAsBytes([0]);
    await expectLater(
      service.install(manifest, stage, game.path),
      throwsA(isA<InstallationException>()),
    );
    expect((await receipts.read(game.path)).receipt, isNull);
  });

  test('post-install hash failure rolls all replaced files back', () async {
    final original = File(
      p.join(game.path, manifest.files.first.relativeDestination),
    );
    await original.parent.create(recursive: true);
    await original.writeAsBytes([9, 9, 9]);
    var calls = 0;
    final failing = InstallationService(
      paths,
      LauncherLog(paths.logFile),
      safePaths: SafePathService(),
      receipts: receipts,
      afterDestinationReplaced: (destination) async {
        calls++;
        if (calls == 2) {
          await destination.writeAsBytes([0, 0, 0, 0]);
        }
      },
    );

    await expectLater(
      failing.install(manifest, stage, game.path),
      throwsA(isA<InstallationException>()),
    );

    expect(await original.readAsBytes(), [9, 9, 9]);
    final second = File(
      p.join(game.path, manifest.files.last.relativeDestination),
    );
    expect(await second.exists(), isFalse);
    expect((await receipts.read(game.path)).receipt, isNull);
  });

  test('successful transaction removes temporary files and journal', () async {
    await service.install(manifest, stage, game.path);
    final storage = await receipts.storageFor(game.path);
    expect(
      await storage.transactions.exists()
          ? await storage.transactions.list().isEmpty
          : true,
      isTrue,
    );
    for (final asset in manifest.files) {
      final destination = p.join(game.path, asset.relativeDestination);
      expect(await File('$destination.nte-new').exists(), isFalse);
      expect(await File('$destination.nte-restore').exists(), isFalse);
    }
  });

  test(
    'exclusive operation lock blocks a second simultaneous install',
    () async {
      final replaced = Completer<void>();
      final release = Completer<void>();
      var paused = false;
      final firstService = InstallationService(
        paths,
        LauncherLog(paths.logFile),
        safePaths: SafePathService(),
        receipts: receipts,
        afterDestinationReplaced: (_) async {
          if (!paused) {
            paused = true;
            replaced.complete();
            await release.future;
          }
        },
      );
      final first = firstService.install(manifest, stage, game.path);
      await replaced.future;

      await expectLater(
        service.install(manifest, stage, game.path),
        throwsA(isA<InstallationException>()),
      );

      release.complete();
      await first;
    },
  );

  test('two installations never share permanent backups', () async {
    final other = await createGame(sandbox, 'other');
    for (final target in [game, other]) {
      final original = File(
        p.join(target.path, manifest.files.first.relativeDestination),
      );
      await original.parent.create(recursive: true);
      await original.writeAsBytes(target == game ? [1, 1, 1] : [2, 2, 2]);
      await service.install(manifest, stage, target.path);
    }
    final firstStorage = await receipts.storageFor(game.path);
    final secondStorage = await receipts.storageFor(other.path);
    final firstBackup = File(
      p.join(
        firstStorage.originals.path,
        manifest.files.first.relativeDestination,
      ),
    );
    final secondBackup = File(
      p.join(
        secondStorage.originals.path,
        manifest.files.first.relativeDestination,
      ),
    );
    expect(await firstBackup.readAsBytes(), [1, 1, 1]);
    expect(await secondBackup.readAsBytes(), [2, 2, 2]);
  });

  test('reinstall repairs a missing and a modified destination', () async {
    await service.install(manifest, stage, game.path);
    await File(
      p.join(game.path, manifest.files.first.relativeDestination),
    ).delete();
    await File(
      p.join(game.path, manifest.files.last.relativeDestination),
    ).writeAsBytes([0, 0, 0, 0]);

    await service.install(manifest, stage, game.path);

    for (var index = 0; index < manifest.files.length; index++) {
      expect(
        await File(
          p.join(game.path, manifest.files[index].relativeDestination),
        ).readAsBytes(),
        contents[index],
      );
    }
  });

  test('removal preserves a file modified after installation', () async {
    await service.install(manifest, stage, game.path);
    final modified = File(
      p.join(game.path, manifest.files.first.relativeDestination),
    );
    await modified.writeAsBytes([7, 7, 7]);

    final result = await service.uninstall(game.path);

    expect(result.complete, isFalse);
    expect(
      result.preservedModifiedFiles,
      contains(p.joinAll(manifest.files.first.relativeDestination.split('/'))),
    );
    expect(await modified.readAsBytes(), [7, 7, 7]);
    expect((await receipts.read(game.path)).receipt, isNotNull);
  });

  test('missing backup causes partial removal and keeps diagnostics', () async {
    final destination = File(
      p.join(game.path, manifest.files.first.relativeDestination),
    );
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes([9, 9, 9]);
    await service.install(manifest, stage, game.path);
    final storage = await receipts.storageFor(game.path);
    await File(
      p.join(storage.originals.path, manifest.files.first.relativeDestination),
    ).delete();

    final result = await service.uninstall(game.path);

    expect(result.complete, isFalse);
    expect(
      result.failedFiles,
      contains(p.joinAll(manifest.files.first.relativeDestination.split('/'))),
    );
    expect(await storage.receipt.exists(), isTrue);
  });

  test('receipt from another directory cannot remove current files', () async {
    final other = await createGame(sandbox, 'other');
    await service.install(manifest, stage, other.path);
    await expectLater(
      service.uninstall(game.path),
      throwsA(isA<InstallationException>()),
    );
  });

  test('recovers an abandoned transaction with a rollback', () async {
    final destination = File(
      p.join(game.path, manifest.files.first.relativeDestination),
    );
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(contents.first);
    final storage = await receipts.storageFor(game.path);
    final transaction = Directory(p.join(storage.transactions.path, 'orphan'));
    final backup = File(
      p.join(
        transaction.path,
        'previous',
        manifest.files.first.relativeDestination,
      ),
    );
    await backup.parent.create(recursive: true);
    await backup.writeAsBytes([9, 9, 9]);
    await File(p.join(transaction.path, 'transaction.json')).writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'gameDirectory': storage.gameDirectory,
        'state': 'files-replaced',
        'entries': [
          {
            'relativePath': manifest.files.first.relativeDestination,
            'destinationExisted': true,
          },
        ],
      }),
    );

    final recovery = await service.recoverAbandoned(game.path, manifest);

    expect(recovery.complete, isTrue);
    expect(await destination.readAsBytes(), [9, 9, 9]);
    expect(await transaction.exists(), isFalse);
  });

  test(
    'preserves an unparseable abandoned transaction for diagnosis',
    () async {
      final storage = await receipts.storageFor(game.path);
      final transaction = Directory(p.join(storage.transactions.path, 'bad'));
      await transaction.create(recursive: true);
      await File(
        p.join(transaction.path, 'transaction.json'),
      ).writeAsString('{');

      final recovery = await service.recoverAbandoned(game.path, manifest);

      expect(recovery.complete, isFalse);
      expect(await transaction.exists(), isTrue);
    },
  );

  test('removes an operation lock whose process no longer exists', () async {
    final storage = await receipts.storageFor(game.path);
    await storage.root.create(recursive: true);
    final lock = File(p.join(storage.root.path, 'operation.lock'));
    await lock.writeAsString(
      jsonEncode({
        'pid': 2147483646,
        'createdAt': DateTime.utc(2026, 7, 29).toIso8601String(),
      }),
    );

    final recovery = await service.recoverAbandoned(game.path, manifest);

    expect(recovery.complete, isTrue);
    expect(await lock.exists(), isFalse);
  });
}
