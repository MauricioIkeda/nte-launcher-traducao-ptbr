import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/app_paths.dart';
import '../core/launcher_log.dart';
import '../core/trusted_http_client.dart';
import '../models/translation_manifest.dart';

class ManifestRepository {
  ManifestRepository(this.paths, this.log);

  static const _bundledManifest = 'assets/manifest/translation_manifest.json';
  static const _remoteManifestUrl = String.fromEnvironment(
    'NTE_MANIFEST_URL',
    defaultValue:
        'https://raw.githubusercontent.com/MauricioIkeda/'
        'nte-launcher-traducao-ptbr/main/assets/manifest/'
        'translation_manifest.json',
  );

  final AppPaths paths;
  final LauncherLog log;

  Future<TranslationManifest> load() async {
    if (_remoteManifestUrl.isNotEmpty) {
      try {
        final remote = await _downloadRemoteManifest();
        await _writeCache(remote.source);
        await log.info(
          'Manifesto remoto carregado: '
          '${remote.manifest.translationVersion}.',
        );
        return remote.manifest;
      } catch (error, stackTrace) {
        await log.error(
          'Falha no manifesto remoto; tentando cache.',
          error: error,
          stackTrace: stackTrace,
        );
      }

      final cached = await _loadCache();
      if (cached != null) {
        await log.info('Manifesto em cache carregado.');
        return cached;
      }
    }

    final bundledText = await rootBundle.loadString(_bundledManifest);
    final bundled = _decode(bundledText);
    await log.info(
      'Manifesto embutido carregado: ${bundled.translationVersion}.',
    );
    return bundled;
  }

  Future<({TranslationManifest manifest, String source})>
  _downloadRemoteManifest() async {
    final uri = Uri.parse(_remoteManifestUrl);
    if (uri.scheme != 'https') {
      throw const FormatException('O manifesto remoto precisa usar HTTPS.');
    }

    final client = TrustedHttpClientFactory.create();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Manifesto retornou HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('Manifesto remoto muito grande.');
        }
      }
      final source = utf8.decode(bytes);
      return (manifest: _decode(source), source: source);
    } finally {
      client.close(force: true);
    }
  }

  Future<TranslationManifest?> _loadCache() async {
    try {
      if (!await paths.cachedManifest.exists()) {
        return null;
      }
      return _decode(await paths.cachedManifest.readAsString());
    } catch (error, stackTrace) {
      await log.error(
        'Cache de manifesto inválido.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _writeCache(String source) async {
    await paths.cache.create(recursive: true);
    final temporary = File('${paths.cachedManifest.path}.tmp');
    await temporary.writeAsString(source, flush: true);
    if (await paths.cachedManifest.exists()) {
      await paths.cachedManifest.delete();
    }
    await temporary.rename(paths.cachedManifest.path);
  }

  TranslationManifest _decode(String source) {
    return TranslationManifest.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }
}
