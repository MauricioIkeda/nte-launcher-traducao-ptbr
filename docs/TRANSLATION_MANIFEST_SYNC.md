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

`publishedAt` é a versão lógica preparada pela pipeline. `published_at`,
devolvido pela API do GitHub, é somente metadata da publicação da release e
não participa da monotonicidade. Frações de segundo UTC são aceitas; a parte
até segundos deve coincidir com a data embutida na tag.

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

## Contrato instalado e compatibilidade

Uma nova publicação exige `sourceHash`, tag oficial e exatamente cinco arquivos
instaláveis nos destinos autorizados. O `gameBuildId` pode ser `null`; quando
presente, é uma string sem caracteres de controle e com até 200 caracteres.

O launcher mantém leitura compatível com o manifesto legado da `main`, que pode
não possuir `sourceHash` nem `gameBuildId`. Essa tolerância existe apenas para a
migração e para os fallbacks locais. O workflow nunca aceita uma nova release
sem a identidade completa.

Depois do parse, o launcher baixa em streaming, valida tamanho e SHA-256, instala
por uma transação com recibo e verifica novamente os arquivos reais no disco.
Cache e bundle não podem rebaixar um recibo válido mais novo. Reparo usa os
mesmos hashes do manifesto; remoção preserva arquivos alterados depois da
instalação.

## Limites e teste integrado

Respostas JSON da API são limitadas a 16 MiB, o manifesto a 1 MiB e o fallback
de validação de asset a 2 GiB. Assets sem digest fornecido pela API são
processados em streaming, sem carregar o arquivo inteiro em memória.

`tool/test_cross_repository_contract.py` usa diretamente a pipeline privada
quando os dois repositórios estão lado a lado. Ele prova LOCRES → identidade →
build manifest → manifesto público → release simulada → dispatch → candidato →
substituição atômica. O teste Flutter
`test/integrated_publication_installation_test.dart` completa o percurso no
cliente, incluindo estado atual, adulteração e reparo dos cinco arquivos.

## Fontes da verdade

- bytes do `Game.locres` original: fonte de `sourceHash`;
- `prepared-release.json`: identidade imutável da publicação em andamento;
- release pública validada: fonte dos sete assets distribuídos;
- manifesto estático validado na `main`: entrada remota do launcher;
- arquivos e recibo locais: fonte do estado real da instalação.

O launcher ainda não extrai o LOCRES dos containers do jogo para comparar o
`sourceHash` diretamente com a instalação. Quando disponível, `gameBuildId`
serve como pista oficial de compatibilidade, não como substituto da verificação
dos arquivos instalados.

## Validação de Pull Requests

O workflow `pull-request-validation.yml` executa somente em PRs destinados à
`main`, com `contents: read`. Um job Ubuntu valida as ferramentas Python, o
contrato, a sintaxe dos workflows, `actionlint` e whitespace. Um job Windows
usa Flutter 3.44.8 para formato, análise, testes unitários, teste integrado e
build Release.

O teste integrado usa artefatos locais determinísticos: ele prova instalação,
validação, backup, remoção e restauração sem consultar releases públicas nem
depender de uma sessão gráfica. Os testes específicos do serviço de download
continuam cobrindo retomada, respostas HTTP inválidas, limites e integridade.
O teste cruzado com a pipeline é explicitamente ignorado quando o repositório
privado não existe ao lado do checkout público.
