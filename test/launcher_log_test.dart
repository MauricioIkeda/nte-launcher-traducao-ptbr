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

  test('redacts NTE player identity and local profile details', () {
    const roleLine =
        '23:59:05.254 [21092]: [DEBUG] '
        '[CHDGamePlayerMgr::setRoleInfo] '
        '{"appId":"3000001","uid":"2000714618",'
        '"token":"secret-token","roleName":"Sora",'
        '"roleId":"218211476267","extraInfo":'
        '"{\\"rolePosition\\":\\"-91161,132033,9535\\"}"}';
    const generic =
        'did:device-fingerprint token=plain-secret '
        'path=C:\\Users\\PrivateUser\\AppData\\Local\\HT\\Saved_Global '
        'linux=/home/private-user/.local/share/nte';

    final redactedRole = LauncherLog.redactSensitiveValues(roleLine);
    final redactedGeneric = LauncherLog.redactSensitiveValues(generic);

    expect(redactedRole, contains('[REDACTED_PLAYER_INFO]'));
    expect(redactedRole, isNot(contains('2000714618')));
    expect(redactedRole, isNot(contains('secret-token')));
    expect(redactedRole, isNot(contains('Sora')));
    expect(redactedRole, isNot(contains('218211476267')));
    expect(redactedRole, isNot(contains('-91161')));

    expect(redactedGeneric, contains('did:[REDACTED]'));
    expect(redactedGeneric, contains('token=[REDACTED]'));
    expect(redactedGeneric, contains(r'C:\Users\[REDACTED_USER]\AppData'));
    expect(redactedGeneric, contains('/home/[REDACTED_USER]/.local'));
    expect(redactedGeneric, isNot(contains('device-fingerprint')));
    expect(redactedGeneric, isNot(contains('plain-secret')));
    expect(redactedGeneric, isNot(contains('PrivateUser')));
    expect(redactedGeneric, isNot(contains('private-user'));
  });
}
