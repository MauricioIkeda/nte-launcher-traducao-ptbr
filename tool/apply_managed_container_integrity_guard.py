from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "lib/services/installation_service.dart"
text = PATH.read_text(encoding="utf-8")

old = '''      final previous = previousByPath[_portablePathKey(relative)];
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
'''
new = '''      final previous = previousByPath[_portablePathKey(relative)];
      final destination = await safePaths.resolveFile(gameDirectory, relative);
      if (previous != null) {
        // Um arquivo gerenciado só continua pertencendo à tradução enquanto o
        // conteúdo no disco ainda for exatamente o que o recibo instalou. Uma
        // atualização do NTE pode passar a ocupar o mesmo caminho depois da
        // primeira instalação; nesse caso jamais sobrescrevemos o novo nativo.
        if (previous.originalExisted) {
          collisions.add(relative);
          continue;
        }
        if (!await destination.exists()) {
          continue;
        }
        final current = await integrity.startOperation().verify(
          file: destination,
          expectedSize: previous.installedSize,
          expectedSha256: previous.installedSha256,
        );
        if (!current.isValid) {
          collisions.add(relative);
        }
        continue;
      }
      if (await destination.exists()) {
        collisions.add(relative);
      }
'''
if text.count(old) != 1:
    raise RuntimeError(f"managed container guard anchor count={text.count(old)}")
PATH.write_text(text.replace(old, new), encoding="utf-8")
