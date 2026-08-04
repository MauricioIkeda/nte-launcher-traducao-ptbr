import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/app_paths.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:nte_translation_launcher/services/installation_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late InstallationService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-directory-');
    final paths = AppPaths.forTesting(Directory(p.join(sandbox.path, 'app')));
    service = InstallationService(paths, LauncherLog(paths.logFile));
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('accepts the launcher directly in the game root', () async {
    final root = await _createClientRoot(sandbox, 'Neverness To Everness');
    final launcher = File(p.join(root.path, 'NTEGlobalLauncher.exe'));
    await launcher.writeAsBytes(const [77, 90]);

    final result = await service.resolveGameDirectory(root.path);

    expect(result, isNotNull);
    expect(result!.gameDirectory, p.normalize(p.absolute(root.path)));
    expect(result.launcherExecutable, launcher.path);
    expect(result.wasAdjusted, isFalse);
  });

  test('accepts a launcher in the nested NTEGlobal directory', () async {
    final root = await _createClientRoot(sandbox, 'Neverness To Everness');
    final launcher = File(
      p.join(root.path, 'NTEGlobal', 'NTEGlobalLauncher.exe'),
    );
    await launcher.parent.create(recursive: true);
    await launcher.writeAsBytes(const [77, 90]);

    final result = await service.resolveGameDirectory(root.path);

    expect(result, isNotNull);
    expect(result!.gameDirectory, p.normalize(p.absolute(root.path)));
    expect(result.launcherExecutable, launcher.path);
  });

  test(
    'normalizes a selected NTE Global folder back to the client root',
    () async {
      final root = await _createClientRoot(sandbox, 'Neverness To Everness');
      final nested = Directory(p.join(root.path, 'NTE Global'));
      await nested.create();
      final launcher = File(p.join(nested.path, 'NTEGlobalLauncher.exe'));
      await launcher.writeAsBytes(const [77, 90]);

      final result = await service.resolveGameDirectory(nested.path);

      expect(result, isNotNull);
      expect(result!.gameDirectory, p.normalize(p.absolute(root.path)));
      expect(result.launcherExecutable, launcher.path);
      expect(result.wasAdjusted, isTrue);
    },
  );

  test('rejects a launcher folder without the real game client', () async {
    final launcherOnly = Directory(p.join(sandbox.path, 'NTEGlobal'));
    await launcherOnly.create();
    await File(
      p.join(launcherOnly.path, 'NTEGlobalLauncher.exe'),
    ).writeAsBytes(const [77, 90]);

    expect(await service.resolveGameDirectory(launcherOnly.path), isNull);
  });
}

Future<Directory> _createClientRoot(Directory sandbox, String name) async {
  final root = Directory(p.join(sandbox.path, name));
  final executable = File(
    p.join(
      root.path,
      'Client',
      'WindowsNoEditor',
      'HT',
      'Binaries',
      'Win64',
      'HTGame.exe',
    ),
  );
  await executable.parent.create(recursive: true);
  await executable.writeAsBytes(const [77, 90]);
  return root;
}
