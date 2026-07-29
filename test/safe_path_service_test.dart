import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/safe_path_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late SafePathService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-safe-path-');
    service = SafePathService();
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('resolves a relative file inside the selected root', () async {
    final result = await service.resolveFile(
      sandbox.path,
      'Client/Content/file.pak',
    );
    final canonical = await service.canonicalDirectory(sandbox.path);
    expect(p.isWithin(canonical, result.path), isTrue);
  });

  for (final malicious in [
    '../outside.dll',
    'Client/../../outside.dll',
    '/absolute/file.dll',
    r'C:\Windows\file.dll',
    r'\\server\share\file.dll',
    'Client//file.dll',
  ]) {
    test('rejects malicious path $malicious', () {
      expect(
        () => service.normalizeRelative(malicious),
        throwsA(isA<UnsafePathException>()),
      );
    });
  }

  test('equivalent Windows paths share the same canonical identity', () {
    if (!Platform.isWindows) {
      return;
    }
    expect(
      service.sameDirectory(
        '${sandbox.path.toUpperCase()}\\',
        sandbox.path.toLowerCase(),
      ),
      isTrue,
    );
  });

  test(
    'rejects a symbolic link that escapes the root when supported',
    () async {
      final outside = await Directory.systemTemp.createTemp('nte-outside-');
      addTearDown(() => outside.delete(recursive: true));
      final link = Link(p.join(sandbox.path, 'linked'));
      try {
        await link.create(outside.path);
      } on FileSystemException {
        return;
      }
      await expectLater(
        service.resolveFile(sandbox.path, 'linked/file.bin'),
        throwsA(isA<UnsafePathException>()),
      );
    },
  );
}
