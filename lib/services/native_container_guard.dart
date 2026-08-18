import 'package:path/path.dart' as p;

import '../models/install_receipt.dart';
import '../models/translation_manifest.dart';
import 'file_integrity_service.dart';
import 'safe_path_service.dart';

/// Preflight que decide se um container de destino ainda pode ser tratado como
/// propriedade da tradução. Ele não escreve nada: qualquer colisão é detectada
/// antes da transação de instalação começar.
class NativeContainerGuard {
  const NativeContainerGuard._();

  static Future<List<String>> findCollisions({
    required TranslationManifest manifest,
    required String gameDirectory,
    required InstallReceipt? previousReceipt,
    required SafePathService safePaths,
    required FileIntegrityService integrity,
  }) async {
    final previous = <String, InstalledFileReceipt>{
      for (final entry
          in previousReceipt?.files ?? const <InstalledFileReceipt>[])
        _pathKey(entry.relativePath): entry,
    };
    final collisions = <String>[];

    for (final asset in manifest.files) {
      final relative = safePaths.normalizeRelative(asset.relativeDestination);
      if (!_isProtectedContainer(relative)) {
        continue;
      }

      final destination = await safePaths.resolveFile(gameDirectory, relative);
      final oldReceipt = previous[_pathKey(relative)];

      if (oldReceipt == null) {
        if (await destination.exists()) {
          collisions.add(relative);
        }
        continue;
      }

      // Se havia um original antes da tradução, o caminho nunca deve ser
      // considerado livre para substituição automática numa reinstalação.
      if (oldReceipt.originalExisted) {
        collisions.add(relative);
        continue;
      }

      // Ausência é segura: a tradução havia criado o arquivo e pode recriá-lo.
      if (!await destination.exists()) {
        continue;
      }

      // Um recibo histórico não prova propriedade atual. O arquivo em disco
      // ainda precisa ser exatamente o que aquela instalação registrou.
      final current = await integrity.startOperation().verify(
        file: destination,
        expectedSize: oldReceipt.installedSize,
        expectedSha256: oldReceipt.installedSha256,
      );
      if (!current.isValid) {
        collisions.add(relative);
      }
    }

    return collisions;
  }

  static bool _isProtectedContainer(String relativePath) {
    final normalized = _pathKey(relativePath);
    const paksRoot = 'client/windowsnoeditor/ht/content/paks/';
    if (!normalized.startsWith(paksRoot)) {
      return false;
    }
    return const {'.pak', '.utoc', '.ucas'}.contains(p.posix.extension(normalized));
  }

  static String _pathKey(String value) =>
      p.posix.normalize(value.replaceAll('\\', '/')).toLowerCase();
}