import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/core/launcher_log.dart';
import 'package:path/path.dart' as p;

void main() {
  test('rotates launcher logs and keeps the configured history', () async {
    final sandbox = await Directory.systemTemp.createTemp('nte-log-');
    addTearDown(() => sandbox.delete(recursive: true));
    final file = File(p.join(sandbox.path, 'launcher.log'));
    final log = LauncherLog(file, maxBytes: 100, retainedFiles: 2);

    await log.info('A' * 70);
    await log.info('B' * 70);
    await log.info('C' * 70);
    await log.info('D' * 70);

    expect(await file.exists(), isTrue);
    expect(await File('${file.path}.1').exists(), isTrue);
    expect(await File('${file.path}.2').exists(), isTrue);
    expect(await File('${file.path}.3').exists(), isFalse);
  });

  test('exports bounded recent logs and redacts common secrets', () async {
    final sandbox = await Directory.systemTemp.createTemp('nte-log-export-');
    addTearDown(() => sandbox.delete(recursive: true));
    final file = File(p.join(sandbox.path, 'launcher.log'));
    final log = LauncherLog(file, maxBytes: 1000, retainedFiles: 2);

    await log.info('tentativa anterior');
    await log.error('api_key=segredo-que-nao-pode-sair');
    await log.error(
      '{"access_token":"token-json", '
      '"refresh-token":"refresh-json", '
      '"Authorization":"Bearer token-http"}',
    );

    final excerpts = await log.diagnosticExcerpts(maxTotalBytes: 4096);

    expect(excerpts, hasLength(1));
    expect(excerpts.single['file'], 'launcher.log');
    expect(excerpts.single['content'], contains('tentativa anterior'));
    expect(excerpts.single['content'], contains('api_key=[REDACTED]'));
    expect(
      excerpts.single['content'],
      isNot(contains('segredo-que-nao-pode-sair')),
    );
    expect(excerpts.single['content'], isNot(contains('token-json')));
    expect(excerpts.single['content'], isNot(contains('refresh-json')));
    expect(excerpts.single['content'], isNot(contains('token-http')));
  });
}
