from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "lib/services/installation_service.dart"
text = PATH.read_text(encoding="utf-8")

old = """      final previousReceipt = receiptRead.receipt;
      await storage.transactions.create(recursive: true);
"""
new = """      final previousReceipt = receiptRead.receipt;
      await _protectExistingGameContainers(
        manifest,
        gameDirectory,
        previousReceipt,
      );
      await storage.transactions.create(recursive: true);
"""
if text.count(old) != 1:
    raise RuntimeError(f"install preflight anchor count={text.count(old)}")
text = text.replace(old, new)

marker = """  Future<void> _rollback(
"""
if text.count(marker) != 1:
    raise RuntimeError(f"rollback anchor count={text.count(marker)}")
methods = r'''  Future<void> _protectExistingGameContainers(
    TranslationManifest manifest,
    String gameDirectory,
    InstallReceipt? previousReceipt,
  ) async {
    final previousByPath = {
      for (final entry
          in previousReceipt?.files ?? const <InstalledFileReceipt>[])
        _portablePathKey(entry.relativePath): entry,
    };
    final collisions = <String>[];
    for (final asset in manifest.files) {
      final relative = safePaths.normalizeRelative(asset.relativeDestination);
      if (!_isGameContainer(relative)) {
        continue;
      }
      final previous = previousByPath[_portablePathKey(relative)];
      if (previous != null) {
        // Um arquivo já gerenciado pela tradução só é seguro quando não havia
        // container original sob ele antes da primeira instalação.
        if (previous.originalExisted) {
          collisions.add(relative);
        }
        continue;
      }
      final destination = await safePaths.resolveFile(gameDirectory, relative);
      if (await destination.exists()) {
        collisions.add(relative);
      }
    }
    if (collisions.isEmpty) {
      return;
    }
    throw InstallationException(
      'A instalação foi bloqueada para proteger arquivos originais do jogo. '
      'Os seguintes contêineres já pertenciam a esta instalação: '
      '${collisions.join(', ')}. '
      'Se a tradução já estiver instalada, use "Remover tradução" para '
      'restaurar os originais. Caso contrário, exporte o diagnóstico e não '
      'apague esses arquivos manualmente.',
    );
  }

  static bool _isGameContainer(String relativePath) {
    final normalized = _portablePathKey(relativePath);
    if (!normalized.startsWith(
      'client/windowsnoeditor/ht/content/paks/',
    )) {
      return false;
    }
    return const {'.pak', '.utoc', '.ucas'}.contains(
      p.posix.extension(normalized),
    );
  }

  static String _portablePathKey(String relativePath) => p.posix
      .normalize(relativePath.replaceAll('\\', '/'))
      .toLowerCase();

'''
text = text.replace(marker, methods + marker)
PATH.write_text(text, encoding="utf-8")
