import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/models/translation_manifest.dart';
import 'package:nte_translation_launcher/services/file_integrity_service.dart';
import 'package:nte_translation_launcher/services/native_container_guard.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  test('does not claim a pak outside the NTE Paks directory', () async {
    final sandbox = await Directory.systemTemp.createTemp('nte-cleanroom-scope-');
    try {
      const relative = 'Client/WindowsNoEditor/HT/Content/Other/example.pak';
      final file = File(p.join(sandbox.path, relative));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(const [9, 9, 9]);

      final collisions = await NativeContainerGuard.findCollisions(
        manifest: _manifest(relative),
        gameDirectory: sandbox.path,
        previousReceipt: null,
        safePaths: SafePathService(),
        integrity: FileIntegrityService(),
      );

      expect(collisions, isEmpty);
      expect(await file.readAsBytes(), const [9, 9, 9]);
    } finally {
      await sandbox.delete(recursive: true);
    }
  });

  test('does not claim a non-container file inside Paks', () async {
    final sandbox = await Directory.systemTemp.createTemp('nte-cleanroom-scope-');
    try {
      const relative = 'Client/WindowsNoEditor/HT/Content/Paks/readme.txt';
      final file = File(p.join(sandbox.path, relative));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(const [4, 2]);

      final collisions = await NativeContainerGuard.findCollisions(
        manifest: _manifest(relative),
        gameDirectory: sandbox.path,
        previousReceipt: null,
        safePaths: SafePathService(),
        integrity: FileIntegrityService(),
      );

      expect(collisions, isEmpty);
    } finally {
      await sandbox.delete(recursive: true);
    }
  });
}

TranslationManifest _manifest(String relative) {
  const bytes = [1, 2, 3];
  final name = p.posix.basename(relative);
  return TranslationManifest.fromJson({
    'schemaVersion': 1,
    'translationVersion': 'nte-auto-cleanroom-scope',
    'publishedAt': DateTime.utc(2026, 8, 18).toIso8601String(),
    'files': [
      {
        'name': name,
        'relativeDestination': relative,
        'url': 'https://github.com/example/releases/download/test/$name',
        'size': bytes.length,
        'sha256': hashOf(bytes),
      },
    ],
  });
}
