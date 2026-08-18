# Reconstrução clean-room — proteção pré-1.3 do Launcher

Baseline deliberado: `560308883a5395ba9ef764ff9bb2f7bce87bda67` (launcher 1.4.2 antes das alterações de 18/08/2026).

Esta branch não deve receber cherry-picks dos PRs criados em 18/08/2026. A implementação é guiada por invariantes de segurança.

## Invariantes

1. A instalação nunca pode sobrescrever silenciosamente um `.pak`, `.utoc` ou `.ucas` nativo do NTE dentro de `Client/WindowsNoEditor/HT/Content/Paks`.
2. Um destino inexistente pode ser criado pela tradução.
3. Um destino já existente e sem recibo confiável deve bloquear a instalação antes de qualquer transação que substitua arquivos.
4. Um recibo anterior com `originalExisted=true` prova que aquele caminho já pertenceu ao jogo; uma reinstalação deve bloquear em vez de substituir o original.
5. Um recibo anterior com `originalExisted=false` não basta para provar propriedade atual. Se o arquivo ainda existir, o conteúdo atual precisa coincidir exatamente com `installedSize` + `installedSha256` registrados. Divergência significa que o jogo ou outro agente tomou o caminho depois da instalação e deve bloquear a substituição.
6. Se um arquivo previamente gerenciado estiver ausente, a reinstalação pode recriá-lo.
7. O bloqueio precisa ocorrer antes da criação de um novo recibo e deve preservar bytes nativos/existentes.
8. A proteção deve ser limitada aos containers do diretório de Paks; os demais assets continuam seguindo a transação existente.
9. Comparação de caminhos deve ser portável/case-insensitive no Windows e normalizar `\\`/`/`.
10. O contrato de localização 1.4.2 (`en -> pt-BR` hospedado em `fr`), rollback, remoção e Play não devem ser alterados por esta reconstrução.

## Casos mínimos de regressão

- container nativo sem recibo: bloqueia e preserva bytes;
- container novo exclusivo da tradução: instala;
- container criado pela tradução, depois substituído por bytes do NTE: reinstalação bloqueia e preserva os bytes novos;
- container criado pela tradução e ainda íntegro: reinstalação permitida;
- container criado pela tradução e removido: reinstalação permitida;
- recibo que registra `originalExisted=true`: reinstalação bloqueia;
- extensão não-container fora de Paks: comportamento anterior preservado.

Nenhuma release, manifesto público ou bump de versão faz parte desta branch de reconstrução.