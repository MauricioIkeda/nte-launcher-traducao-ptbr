import 'dart:io';

import 'package:flutter/services.dart';

class TrustedHttpClientFactory {
  static const _certificateAsset = 'assets/certificates/cacert.pem';
  static Uint8List? _certificateBytes;

  static Future<void> initialize() async {
    final data = await rootBundle.load(_certificateAsset);
    _certificateBytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
  }

  static HttpClient create() {
    final bytes = _certificateBytes;
    if (bytes == null) {
      throw StateError('TrustedHttpClientFactory não foi inicializado.');
    }

    final context = SecurityContext(withTrustedRoots: true);
    context.setTrustedCertificatesBytes(bytes);
    final client = HttpClient(context: context);
    client.connectionTimeout = const Duration(seconds: 15);
    client.idleTimeout = const Duration(seconds: 30);
    client.userAgent = 'NTE-Translation-Launcher/2.0';
    return client;
  }
}
