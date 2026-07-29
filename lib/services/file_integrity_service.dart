import 'dart:io';

import 'package:crypto/crypto.dart';

enum FileIntegrityStatus {
  valid,
  missing,
  sizeMismatch,
  hashMismatch,
  accessDenied,
  inUse,
  readError,
  cancelled,
}

class FileIntegrityResult {
  const FileIntegrityResult({
    required this.status,
    this.actualSize,
    this.actualSha256,
    this.error,
  });

  final FileIntegrityStatus status;
  final int? actualSize;
  final String? actualSha256;
  final Object? error;

  bool get isValid => status == FileIntegrityStatus.valid;
}

class FileIntegrityService {
  FileIntegrityOperation startOperation({bool Function()? isCancelled}) =>
      FileIntegrityOperation(isCancelled: isCancelled ?? _neverCancelled);

  Future<String> calculateSha256(
    File file, {
    bool Function()? isCancelled,
  }) async {
    final digest = _DigestSink();
    final input = sha256.startChunkedConversion(digest);
    var closed = false;
    try {
      await for (final chunk in file.openRead()) {
        if (isCancelled?.call() == true) {
          throw const IntegrityCancelledException();
        }
        input.add(chunk);
      }
      input.close();
      closed = true;
      return digest.value!.toString().toLowerCase();
    } finally {
      if (!closed) {
        input.close();
      }
    }
  }

  static bool _neverCancelled() => false;
}

class FileIntegrityOperation {
  FileIntegrityOperation({required this.isCancelled});

  final bool Function() isCancelled;
  final Map<String, FileIntegrityResult> _cache = {};

  Future<FileIntegrityResult> verify({
    required File file,
    required int expectedSize,
    required String expectedSha256,
  }) async {
    final normalizedHash = expectedSha256.toLowerCase();
    final key = '${file.absolute.path}|$expectedSize|$normalizedHash';
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    if (isCancelled()) {
      return const FileIntegrityResult(status: FileIntegrityStatus.cancelled);
    }
    try {
      if (!await file.exists()) {
        return _remember(
          key,
          const FileIntegrityResult(status: FileIntegrityStatus.missing),
        );
      }
      final size = await file.length();
      if (size != expectedSize) {
        return _remember(
          key,
          FileIntegrityResult(
            status: FileIntegrityStatus.sizeMismatch,
            actualSize: size,
          ),
        );
      }
      final hash = await FileIntegrityService().calculateSha256(
        file,
        isCancelled: isCancelled,
      );
      return _remember(
        key,
        FileIntegrityResult(
          status: hash == normalizedHash
              ? FileIntegrityStatus.valid
              : FileIntegrityStatus.hashMismatch,
          actualSize: size,
          actualSha256: hash,
        ),
      );
    } on IntegrityCancelledException catch (error) {
      return FileIntegrityResult(
        status: FileIntegrityStatus.cancelled,
        error: error,
      );
    } on FileSystemException catch (error) {
      return _remember(
        key,
        FileIntegrityResult(
          status: classifyFileSystemError(error),
          error: error,
        ),
      );
    } catch (error) {
      return _remember(
        key,
        FileIntegrityResult(
          status: FileIntegrityStatus.readError,
          error: error,
        ),
      );
    }
  }

  FileIntegrityResult _remember(String key, FileIntegrityResult result) {
    _cache[key] = result;
    return result;
  }
}

FileIntegrityStatus classifyFileSystemError(FileSystemException error) {
  final code = error.osError?.errorCode;
  if (code == 5 || code == 13) {
    return FileIntegrityStatus.accessDenied;
  }
  if (code == 32 || code == 33) {
    return FileIntegrityStatus.inUse;
  }
  return FileIntegrityStatus.readError;
}

class IntegrityCancelledException implements Exception {
  const IntegrityCancelledException();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
