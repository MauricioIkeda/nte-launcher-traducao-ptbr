import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  AppPaths._(this.root);

  final Directory root;

  factory AppPaths.forTesting(Directory root) => AppPaths._(root);

  static Future<AppPaths> create() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'NTE Translation Launcher'));
    await root.create(recursive: true);
    return AppPaths._(root);
  }

  Directory get cache => Directory(p.join(root.path, 'cache'));
  Directory get downloads => Directory(p.join(root.path, 'downloads'));
  Directory get originals => Directory(p.join(root.path, 'originals'));
  Directory get transactions => Directory(p.join(root.path, 'transactions'));
  Directory get updates => Directory(p.join(root.path, 'updates'));
  File get cachedManifest => File(p.join(cache.path, 'manifest.json'));
  File get updateInstaller =>
      File(p.join(updates.path, 'NTE-Translation-Launcher-Setup.exe'));
  File get installReceipt => File(p.join(root.path, 'install_receipt.json'));
  File get logFile => File(p.join(root.path, 'launcher.log'));
}
