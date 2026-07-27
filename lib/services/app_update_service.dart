import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_paths.dart';
import '../core/launcher_log.dart';
import '../core/trusted_http_client.dart';
import '../models/app_update_manifest.dart';

typedef UpdateProgress = void Function(int received, int total);

class AppUpdateService {
  AppUpdateService(
    this.paths,
    this.log, {
    String? manifestUrl,
    String? currentVersion,
  }) : _manifestUrl = manifestUrl ?? _defaultManifestUrl,
       _currentVersionOverride = currentVersion;

  static const _defaultManifestUrl = String.fromEnvironment(
    'NTE_LAUNCHER_MANIFEST_URL',
    defaultValue:
        'https://raw.githubusercontent.com/MauricioIkeda/'
        'ntelauncher-traducao-2.0/main/assets/manifest/'
        'launcher_manifest.json',
  );

  final AppPaths paths;
  final LauncherLog log;
  final String _manifestUrl;
  final String? _currentVersionOverride;

  Future<String> currentVersion() async {
    return _currentVersionOverride ??
        (await PackageInfo.fromPlatform()).version;
  }

  Future<AppUpdateManifest?> check() async {
    final current = await currentVersion();
    final client = TrustedHttpClientFactory.create();
    try {
      final uri = Uri.parse(_manifestUrl);
      if (uri.scheme != 'https') {
        throw const FormatException(
          'O manifesto do launcher precisa usar HTTPS.',
        );
      }
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Manifesto do launcher retornou HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 256 * 1024) {
          throw const FormatException('Manifesto do launcher muito grande.');
        }
      }
      final manifest = AppUpdateManifest.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
      await log.info(
        'Versão do launcher: instalada=$current, '
        'disponível=${manifest.version}.',
      );
      return manifest.isNewerThan(current) ? manifest : null;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> downloadInstaller(
    AppUpdateManifest manifest, {
    required UpdateProgress onProgress,
  }) async {
    await paths.updates.create(recursive: true);
    final destination = paths.updateInstaller;
    final partial = File('${destination.path}.partial');
    if (await partial.exists()) {
      await partial.delete();
    }

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _downloadOnce(manifest, partial, onProgress);
        await verifyInstaller(partial, manifest);
        if (await destination.exists()) {
          await destination.delete();
        }
        await partial.rename(destination.path);
        await log.info('Instalador ${manifest.version} validado.');
        return destination;
      } catch (error, stackTrace) {
        lastError = error;
        await log.error(
          'Falha ao baixar atualização, tentativa $attempt/3.',
          error: error,
          stackTrace: stackTrace,
        );
        if (await partial.exists()) {
          await partial.delete();
        }
      }
    }
    throw AppUpdateException(
      'Não foi possível baixar o instalador após 3 tentativas: $lastError',
    );
  }

  Future<void> startInstaller(File installer) async {
    if (!await installer.exists()) {
      throw const AppUpdateException(
        'O instalador validado não foi encontrado.',
      );
    }
    await Process.start(installer.path, const [
      '/SP-',
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/RESTARTAPPLICATIONS',
    ], mode: ProcessStartMode.detached);
  }

  Future<void> verifyInstaller(
    File installer,
    AppUpdateManifest manifest,
  ) async {
    final size = await installer.length();
    if (size != manifest.installerSize) {
      throw AppUpdateException(
        'O instalador possui $size bytes; '
        'eram esperados ${manifest.installerSize}.',
      );
    }
    final digest = await sha256.bind(installer.openRead()).first;
    if (digest.toString() != manifest.installerSha256) {
      throw const AppUpdateException(
        'O SHA-256 do instalador não corresponde ao manifesto.',
      );
    }
  }

  Future<void> _downloadOnce(
    AppUpdateManifest manifest,
    File partial,
    UpdateProgress onProgress,
  ) async {
    final client = TrustedHttpClientFactory.create();
    try {
      final request = await client.getUrl(manifest.installerUrl);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Download do instalador retornou HTTP ${response.statusCode}.',
          uri: manifest.installerUrl,
        );
      }
      var received = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          received += chunk.length;
          if (received > manifest.installerSize) {
            throw const AppUpdateException(
              'O instalador excedeu o tamanho esperado.',
            );
          }
          sink.add(chunk);
          onProgress(received, manifest.installerSize);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}
