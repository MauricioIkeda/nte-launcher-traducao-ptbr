import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/file_integrity_service.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory sandbox;
  late FileIntegrityService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nte-integrity-');
    service = FileIntegrityService();
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('validates size and SHA-256 using streamed contents', () async {
    final file = File(p.join(sandbox.path, 'valid.bin'));
    final bytes = List<int>.generate(4096, (index) => index % 251);
    await file.writeAsBytes(bytes);

    final result = await service.startOperation().verify(
      file: file,
      expectedSize: bytes.length,
      expectedSha256: hashOf(bytes),
    );

    expect(result.status, FileIntegrityStatus.valid);
    expect(result.actualSha256, hashOf(bytes));
  });

  test('reports a missing file', () async {
    final result = await service.startOperation().verify(
      file: File(p.join(sandbox.path, 'missing.bin')),
      expectedSize: 1,
      expectedSha256: 'a' * 64,
    );
    expect(result.status, FileIntegrityStatus.missing);
  });

  test('compares size before calculating the hash', () async {
    final file = File(p.join(sandbox.path, 'size.bin'));
    await file.writeAsBytes([1, 2]);
    final result = await service.startOperation().verify(
      file: file,
      expectedSize: 3,
      expectedSha256: 'a' * 64,
    );
    expect(result.status, FileIntegrityStatus.sizeMismatch);
    expect(result.actualSha256, isNull);
  });

  test('detects same-size content with a different hash', () async {
    final file = File(p.join(sandbox.path, 'hash.bin'));
    await file.writeAsBytes([1, 2, 3]);
    final result = await service.startOperation().verify(
      file: file,
      expectedSize: 3,
      expectedSha256: hashOf([3, 2, 1]),
    );
    expect(result.status, FileIntegrityStatus.hashMismatch);
  });

  test('normalizes uppercase expected hashes', () async {
    final file = File(p.join(sandbox.path, 'case.bin'));
    await file.writeAsBytes([1, 2, 3]);
    final result = await service.startOperation().verify(
      file: file,
      expectedSize: 3,
      expectedSha256: hashOf([1, 2, 3]).toUpperCase(),
    );
    expect(result.status, FileIntegrityStatus.valid);
  });

  test('supports cancellation between stream chunks', () async {
    final file = File(p.join(sandbox.path, 'cancel.bin'));
    await file.writeAsBytes(List<int>.filled(1024 * 1024, 1));
    var cancelled = true;
    final result = await service
        .startOperation(isCancelled: () => cancelled)
        .verify(
          file: file,
          expectedSize: await file.length(),
          expectedSha256: 'a' * 64,
        );
    cancelled = false;
    expect(result.status, FileIntegrityStatus.cancelled);
  });

  test('classifies an unreadable entity as a read error', () async {
    final directory = Directory(p.join(sandbox.path, 'not-a-file'));
    await directory.create();
    final result = await service.startOperation().verify(
      file: File(directory.path),
      expectedSize: 1,
      expectedSha256: 'a' * 64,
    );
    expect(
      result.status,
      anyOf(
        FileIntegrityStatus.readError,
        FileIntegrityStatus.sizeMismatch,
        FileIntegrityStatus.missing,
      ),
    );
  });

  test('classifies Windows access denied errors', () {
    expect(
      classifyFileSystemError(
        const FileSystemException(
          'denied',
          'file.bin',
          OSError('Access is denied', 5),
        ),
      ),
      FileIntegrityStatus.accessDenied,
    );
  });

  test('classifies Windows sharing violations as file in use', () {
    expect(
      classifyFileSystemError(
        const FileSystemException(
          'locked',
          'file.bin',
          OSError('Sharing violation', 32),
        ),
      ),
      FileIntegrityStatus.inUse,
    );
  });
}
