import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  AppPaths._(this.root);

  static const _legacyStorageName = 'NTE Translation Launcher';

  final Directory root;

  factory AppPaths.forTesting(Directory root) => AppPaths._(root);

  static Future<AppPaths> create() async {
    final support = await getApplicationSupportDirectory();
    // Mantido para preservar backups e recibos criados pela versão 1.0.0.
    final root = Directory(p.join(support.path, _legacyStorageName));
    await root.create(recursive: true);
    return AppPaths._(root);
  }

  Directory get cache => Directory(p.join(root.path, 'cache'));
  Directory get downloads => Directory(p.join(root.path, 'downloads'));
  Directory get originals => Directory(p.join(root.path, 'originals'));
  Directory get transactions => Directory(p.join(root.path, 'transactions'));
  Directory get updates => Directory(p.join(root.path, 'updates'));
  File get cachedManifest =>
      File(p.join(cache.path, 'automatic-translation-v1.json'));
  File get updateInstaller =>
      File(p.join(updates.path, 'NTE-Launcher-Traducao-PTBR-Setup.exe'));
  File get installReceipt => File(p.join(root.path, 'install_receipt.json'));
  File get logFile => File(p.join(root.path, 'launcher.log'));
}
