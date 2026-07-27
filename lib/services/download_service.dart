import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/launcher_log.dart';
import '../core/trusted_http_client.dart';
import '../models/translation_manifest.dart';

typedef DownloadProgressCallback =
    void Function(int receivedBytes, int totalBytes, String currentFile);

class DownloadService {
  DownloadService(this.paths, this.log);

  final AppPaths paths;
  final LauncherLog log;

  Future<Directory> download(
    TranslationManifest manifest, {
    required DownloadProgressCallback onProgress,
    required bool Function() isCancelled,
  }) async {
    final stage = Directory(
      p.join(paths.downloads.path, manifest.translationVersion),
    );
    await stage.create(recursive: true);

    var completedBytes = 0;
    for (final asset in manifest.files) {
      if (isCancelled()) {
        throw const DownloadCancelledException();
      }

      final completedFile = File(p.join(stage.path, asset.name));
      if (await _isValid(completedFile, asset)) {
        completedBytes += asset.size;
        onProgress(completedBytes, manifest.totalBytes, asset.name);
        continue;
      }
      if (await completedFile.exists()) {
        await completedFile.delete();
      }

      await _downloadAsset(
        asset,
        completedFile,
        completedBytes: completedBytes,
        totalBytes: manifest.totalBytes,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      completedBytes += asset.size;
    }
    return stage;
  }

  Future<void> _downloadAsset(
    TranslationFile asset,
    File destination, {
    required int completedBytes,
    required int totalBytes,
    required DownloadProgressCallback onProgress,
    required bool Function() isCancelled,
  }) async {
    final partial = File('${destination.path}.part');
    Object? lastError;

    for (var attempt = 1; attempt <= 3; attempt++) {
      if (isCancelled()) {
        throw const DownloadCancelledException();
      }
      try {
        await partial.parent.create(recursive: true);
        var existingBytes = await partial.exists() ? await partial.length() : 0;
        if (existingBytes > asset.size) {
          await partial.delete();
          existingBytes = 0;
        }

        await log.info(
          'Baixando ${asset.name}, tentativa $attempt, '
          'retomando em $existingBytes bytes.',
        );

        final client = TrustedHttpClientFactory.create();
        try {
          final request = await client.getUrl(asset.url);
          if (existingBytes > 0) {
            request.headers.set(
              HttpHeaders.rangeHeader,
              'bytes=$existingBytes-',
            );
          }
          final response = await request.close().timeout(
            const Duration(seconds: 30),
          );

          if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
            if (await partial.exists()) {
              await partial.delete();
            }
            throw const _RestartDownloadException();
          }
          if (response.statusCode != HttpStatus.ok &&
              response.statusCode != HttpStatus.partialContent) {
            throw HttpException(
              'Download retornou HTTP ${response.statusCode}.',
              uri: asset.url,
            );
          }

          final append =
              existingBytes > 0 &&
              response.statusCode == HttpStatus.partialContent;
          if (!append) {
            existingBytes = 0;
          }
          final sink = partial.openWrite(
            mode: append ? FileMode.append : FileMode.write,
          );
          var receivedForFile = existingBytes;
          try {
            await for (final chunk in response.timeout(
              const Duration(minutes: 2),
            )) {
              if (isCancelled()) {
                throw const DownloadCancelledException();
              }
              sink.add(chunk);
              receivedForFile += chunk.length;
              onProgress(
                completedBytes + receivedForFile,
                totalBytes,
                asset.name,
              );
            }
          } finally {
            await sink.flush();
            await sink.close();
          }
        } finally {
          client.close(force: true);
        }

        final actualSize = await partial.length();
        if (actualSize != asset.size) {
          throw DownloadIntegrityException(
            '${asset.name} incompleto: $actualSize de ${asset.size} bytes.',
          );
        }
        final actualHash = await _sha256(partial);
        if (actualHash != asset.sha256) {
          await partial.delete();
          throw DownloadIntegrityException(
            'SHA-256 inválido para ${asset.name}.',
          );
        }

        if (await destination.exists()) {
          await destination.delete();
        }
        await partial.rename(destination.path);
        await log.info('${asset.name} validado e concluído.');
        return;
      } on DownloadCancelledException {
        rethrow;
      } on HttpException {
        rethrow;
      } catch (error, stackTrace) {
        lastError = error;
        await log.error(
          'Falha ao baixar ${asset.name}, tentativa $attempt.',
          error: error,
          stackTrace: stackTrace,
        );
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }

    throw DownloadException(
      'Não foi possível baixar ${asset.name} após 3 tentativas.',
      cause: lastError,
    );
  }

  Future<bool> _isValid(File file, TranslationFile asset) async {
    if (!await file.exists() || await file.length() != asset.size) {
      return false;
    }
    return await _sha256(file) == asset.sha256;
  }

  Future<String> _sha256(File file) async {
    return (await sha256.bind(file.openRead()).first).toString();
  }
}

class DownloadException implements Exception {
  const DownloadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class DownloadIntegrityException extends DownloadException {
  const DownloadIntegrityException(super.message);
}

class DownloadCancelledException extends DownloadException {
  const DownloadCancelledException() : super('Download cancelado.');
}

class _RestartDownloadException implements Exception {
  const _RestartDownloadException();
}
