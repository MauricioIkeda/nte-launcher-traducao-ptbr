import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/bootstrap_diagnostics.dart';

void main() {
  test('standalone bootstrap diagnostic is valid JSON', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nte-bootstrap-diagnostic-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    BootstrapDiagnostics.recordSync(
      'bootstrap_test_event',
      details: {'stage': 'test'},
    );
    final file = await BootstrapDiagnostics.exportStandalone(
      File('${directory.path}${Platform.pathSeparator}diagnostico.json'),
    );
    expect(await file.exists(), isTrue);

    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], 1);
    expect(decoded['reportType'], 'bootstrap-diagnostic');
    expect(decoded['currentSessionId'], isNotEmpty);
    expect(decoded['bootstrapHistory'], isA<List<dynamic>>());
  });
}
