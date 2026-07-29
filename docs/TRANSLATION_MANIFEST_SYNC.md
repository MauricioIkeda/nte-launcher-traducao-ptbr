# Sincronização segura do manifesto de tradução

O launcher não consulta releases diretamente nos computadores dos jogadores.
A ponte entre a pipeline privada, o repositório público de distribuição e o
launcher é o workflow `update-translation-manifest.yml`.

```text
pipeline valida fonte e tradução
→ publica uma release imutável em nte-ptbr-releases
→ envia repository_dispatch com a tag exata
→ workflow valida payload, release, manifesto e assets
→ workflow atualiza somente o manifesto estático da main
→ launcher baixa o manifesto estático
```

## Contrato do dispatch

O evento aceito é `translation-released`. O `client_payload` contém:

```json
{
  "repository": "MauricioIkeda/nte-ptbr-releases",
  "tag": "nte-auto-YYYYMMDD-HHMMSS-0123456789ab",
  "manifestAsset": "translation_manifest.json",
  "manifestSha256": "<SHA-256 dos bytes do manifesto>",
  "publishedAt": "2026-07-29T12:00:00Z",
  "gameBuildId": null,
  "sourceHash": "<SHA-256 do Game.locres original>"
}
```

O repositório e o nome do asset são constantes, a tag possui formato fechado,
as datas são UTC e os hashes têm 64 caracteres hexadecimais. O prefixo final da
tag deve ser igual aos primeiros 12 caracteres de `sourceHash`.

`sourceHash` significa exclusivamente o SHA-256 dos bytes do `Game.locres`
original extraído do jogo. O launcher ainda não extrai esse LOCRES dos
containers instalados para compará-lo diretamente com o jogo.

## Modo dispatch

No `repository_dispatch`, o workflow:

1. lê o JSON pelo arquivo de evento do GitHub, sem interpolar campos do payload
   em comandos shell;
2. valida o payload;
3. consulta `releases/tags/<tag>` e nunca `/releases/latest`;
4. rejeita draft, prerelease, tag divergente e lista de assets inesperada;
5. baixa exatamente `translation_manifest.json` pela API;
6. compara o SHA-256 dos bytes antes de interpretar o JSON;
7. compara tag, data, fonte e build com o payload;
8. reconstrói independentemente os cinco arquivos instaláveis a partir da
   release e compara nomes, destinos, URLs, tamanhos e hashes;
9. aplica as regras de monotonicidade antes de escrever.

## Modo de recuperação

No cron e na execução manual não existe payload. O workflow lista até 300
releases, ignora drafts, prereleases e tags que não seguem `nte-auto-*`, e
valida integralmente cada candidata. Releases de ferramentas nunca participam
da seleção.

A candidata válida com o `publishedAt` mais recente é escolhida. Releases
inválidas são diagnosticadas e ignoradas. Se nenhuma for válida, o workflow
termina sem alterar o repositório.

Esse modo recupera dispatch perdido, indisponibilidade temporária, execução
cancelada e releases publicadas antes da implantação do contrato.

## Imutabilidade e downgrade

Antes da escrita e novamente depois de atualizar a branch, o candidato é
comparado com o manifesto commitado:

- candidato mais novo: pode atualizar;
- mesma versão e mesmo conteúdo: sucesso idempotente, sem commit;
- mesma versão com conteúdo diferente: falha de imutabilidade;
- candidato mais antigo: downgrade bloqueado;
- mesma data com versões diferentes: falha por ambiguidade;
- manifesto atual inválido: diagnóstico e falha, sem substituição silenciosa.

A tag não é tratada como uma versão semântica. `publishedAt` determina a ordem,
e a data/hora embutida na tag deve corresponder a ele.

## Concorrência e commit

O workflow usa concorrência serial, mas também atualiza `main` antes do commit,
reaplica o candidato e repete a validação. Se o push for rejeitado, existe um
único retry: a nova `main` é carregada, a monotonicidade é reavaliada e um
candidato antigo não pode sobrescrever um novo.

Somente `assets/manifest/translation_manifest.json` é adicionado ao commit. A
escrita usa arquivo temporário, releitura, validação e substituição atômica. A
mensagem identifica a tag:

```text
chore: update translation manifest to <tag>
```

## Relação com o launcher instalado

O `ManifestRepository` continua baixando o manifesto estático da branch `main`
por `raw.githubusercontent.com`. Uma resposta remota válida é autoritativa.
Cache e manifesto embutido continuam sendo fallback offline e não provocam
downgrade automático.

O workflow utiliza apenas `github.token` com `contents: write`. Nenhum token,
payload completo ou URL temporária é incluído no manifesto ou no resumo.
