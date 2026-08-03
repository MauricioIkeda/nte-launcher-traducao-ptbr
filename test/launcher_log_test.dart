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
}
