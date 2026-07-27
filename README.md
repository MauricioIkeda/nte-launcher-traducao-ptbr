# NTE Translation Launcher

[![Flutter](https://img.shields.io/badge/Flutter-Windows-02569B?logo=flutter)](https://flutter.dev/)
[![Atualizar manifesto](https://github.com/MauricioIkeda/ntelauncher-traducao-2.0/actions/workflows/update-translation-manifest.yml/badge.svg)](https://github.com/MauricioIkeda/ntelauncher-traducao-2.0/actions/workflows/update-translation-manifest.yml)
[![Manifesto](https://img.shields.io/badge/downloads-SHA--256-22c55e)](#segurança)

Launcher comunitário para instalar, atualizar e remover a tradução PT-BR de
**Neverness to Everness** no Windows de maneira verificável e reversível.

O launcher foi projetado para não depender da API pública do GitHub nos
computadores dos jogadores. Ele lê um pequeno manifesto estático, baixa os
arquivos diretamente da release da tradução e valida cada download antes de
alterar a instalação do jogo.

> [!WARNING]
> Este é um projeto comunitário e não oficial. Ele não possui vínculo com os
> desenvolvedores ou distribuidores de Neverness to Everness. O uso de
> modificações pode estar sujeito aos termos do jogo; utilize por sua conta e
> risco.

## Destaques

- instalação, atualização e remoção pela mesma interface;
- manifesto estático, sem o limite anônimo de 60 chamadas por IP da API;
- certificados Mozilla/cURL incluídos para validação TLS consistente;
- downloads retomáveis com HTTP `Range`;
- validação obrigatória de tamanho e SHA-256;
- cache local e manifesto de emergência embutido no aplicativo;
- backup dos arquivos originais antes da instalação;
- escrita atômica e rollback automático em caso de falha;
- elevação UAC apenas quando a pasta do jogo realmente exige;
- log técnico persistente para facilitar diagnósticos.

## Como funciona

```text
GitHub Action
    │
    ├── consulta a release mais recente da tradução
    ├── valida nomes, URLs, tamanhos e SHA-256
    └── publica translation_manifest.json
                │
                ▼
Launcher ──► manifesto estático ──► downloads diretos da release
                │                             │
                └──────── validação ──────────┘
                              │
                              ▼
                   backup + instalação atômica
```

O GitHub Action concentra a única consulta à API. Todos os launchers consultam
o arquivo estático pelo `raw.githubusercontent.com`, evitando que usuários na
mesma operadora ou em uma rede CGNAT compartilhem um limite pequeno da API.

## Segurança

Antes de instalar qualquer arquivo, o launcher:

1. aceita apenas URLs HTTPS e caminhos relativos seguros;
2. rejeita caminhos absolutos e tentativas de escapar da pasta do jogo;
3. confere o tamanho exato informado no manifesto;
4. calcula e compara o SHA-256 do conteúdo baixado;
5. preserva os arquivos originais;
6. usa arquivos temporários e renomeação atômica;
7. restaura o estado anterior se uma etapa falhar.

O cliente HTTPS usa as raízes confiáveis do Windows junto do bundle oficial de
autoridades certificadoras mantido pelo projeto cURL/Mozilla.

## Usar o launcher

Quando houver uma versão publicada:

1. baixe o arquivo ZIP da seção **Releases** deste repositório;
2. extraia todo o conteúdo para uma pasta;
3. execute `NTE-Traducao-PTBR.exe`;
4. selecione a pasta que contém `NTEGlobalLauncher.exe`;
5. clique em **Instalar tradução**.

Para desfazer a instalação, use **Restaurar original**. O launcher recuperará
os arquivos preservados no backup.

## Desenvolvimento

### Requisitos

- Windows 10 ou 11;
- Flutter com suporte a desktop Windows;
- Visual Studio com **Desenvolvimento para desktop com C++**;
- Git;
- Python 3 apenas para executar localmente o gerador do manifesto.

### Executar

```powershell
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat run -d windows
```

Para testar a seleção de pasta sem instalar o jogo, crie uma pasta vazia,
adicione nela um arquivo chamado `NTEGlobalLauncher.exe` e selecione essa pasta
na interface.

### Gerar uma versão de produção

```powershell
C:\flutter\bin\flutter.bat build windows --release
```

O executável e suas dependências serão gerados em:

```text
build/windows/x64/runner/Release/
```

## Manifesto remoto

Por padrão, o aplicativo consulta:

```text
https://raw.githubusercontent.com/MauricioIkeda/ntelauncher-traducao-2.0/main/assets/manifest/translation_manifest.json
```

Para usar outro repositório ou endereço:

```powershell
C:\flutter\bin\flutter.bat build windows --release `
  --dart-define=NTE_MANIFEST_URL=https://exemplo/translation_manifest.json
```

A ordem de recuperação é:

1. manifesto remoto;
2. última cópia válida armazenada em cache;
3. manifesto incluído no executável.

O launcher nunca inclui token e nunca consulta `api.github.com`.

## Atualização automática

O workflow
[`update-translation-manifest.yml`](.github/workflows/update-translation-manifest.yml)
roda uma vez por hora e também aceita execução manual. Ele:

1. consulta a release mais recente de `Luxx34/nte-pt-br`;
2. exige os cinco arquivos conhecidos da tradução;
3. valida nome, URL e tamanho de cada asset;
4. usa o SHA-256 fornecido pelo GitHub ou baixa o arquivo para calculá-lo;
5. executa os testes do gerador;
6. cria um commit somente quando o manifesto muda.

O processo usa apenas o `GITHUB_TOKEN` temporário criado pelo GitHub Actions.
Nenhum segredo precisa ser cadastrado manualmente.

Se o commit automático for bloqueado, acesse **Settings > Actions > General >
Workflow permissions**, marque **Read and write permissions** e salve.

## Testes

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
C:\flutter\bin\flutter.bat test integration_test\end_to_end_download_test.dart -d windows
```

O teste de integração baixa os cinco arquivos reais, valida seus hashes, instala
em uma pasta de jogo simulada e confirma que a remoção restaura o arquivo
original.

O gerador do manifesto pode ser validado separadamente:

```powershell
python -m unittest discover -s tool -p "test_*.py"
```

## Créditos

- Tradução PT-BR: [`Luxx34/nte-pt-br`](https://github.com/Luxx34/nte-pt-br)
- Certificados: [cURL CA Extract](https://curl.se/docs/caextract.html)
- Interface e launcher: Flutter

Contribuições e relatos de problemas são bem-vindos.
