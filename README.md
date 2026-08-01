<p align="center">
  <img src="assets/images/app_icon.png" alt="Ícone do NTE Launcher Tradução PT-BR" width="112">
</p>

<h1 align="center">NTE Launcher Tradução PT-BR</h1>

<p align="center">
  Launcher comunitário para instalar, atualizar, remover e manter a tradução
  brasileira de <strong>Neverness to Everness</strong> no Windows.
</p>

<p align="center">
  <a href="https://github.com/MauricioIkeda/nte-launcher-traducao-ptbr/releases/latest">
    <strong>Baixar a versão mais recente</strong>
  </a>
</p>

<p align="center">
  <a href="https://flutter.dev/"><img alt="Flutter para Windows" src="https://img.shields.io/badge/Flutter-Windows-02569B?logo=flutter"></a>
  <a href="https://github.com/MauricioIkeda/nte-launcher-traducao-ptbr/actions/workflows/update-translation-manifest.yml"><img alt="Atualizar manifesto" src="https://github.com/MauricioIkeda/nte-launcher-traducao-ptbr/actions/workflows/update-translation-manifest.yml/badge.svg"></a>
  <a href="#segurança"><img alt="Downloads verificados com SHA-256" src="https://img.shields.io/badge/downloads-SHA--256-22c55e"></a>
</p>

> [!WARNING]
> Este é um projeto comunitário e não oficial. Ele não possui vínculo com a
> Hotta Studio, Perfect World Games, Steam ou Epic Games. O uso de modificações
> pode estar sujeito aos termos do jogo. Utilize por sua conta e risco.

## Escolha o seu objetivo

### Quero somente instalar e usar a tradução

Você não precisa instalar Git, Flutter, Dart, Python, Visual Studio, VS Code, Inno Setup ou GitHub CLI.

Siga apenas a seção [Instalação](#instalação) deste README ou a primeira parte do [guia manual para Windows](docs/CONFIGURACAO_MANUAL_WINDOWS.md#cenário-a--somente-usar-o-launcher).

### Quero desenvolver, corrigir bugs ou publicar o launcher

Use o manual completo:

**[Guia manual do NTE Launcher Tradução PT-BR no Windows](docs/CONFIGURACAO_MANUAL_WINDOWS.md)**

Ele explica para uma pessoa sem ambiente preparado:

- para que serve cada programa;
- quais programas são obrigatórios e quais são opcionais;
- como instalar exatamente o Flutter 3.44.8;
- por que Dart não precisa ser instalado separadamente;
- como configurar o Visual Studio com desenvolvimento C++;
- como instalar Python e Inno Setup;
- como autenticar a GitHub CLI;
- como clonar e abrir o projeto;
- como executar, testar e simular uma pasta do jogo;
- como criar build Release e instalador;
- como trabalhar com branches;
- como preparar e auditar uma release;
- o que precisa ou não ser salvo antes de formatar.

## O que o launcher faz

- instala, atualiza e remove a tradução PT-BR pela mesma interface;
- encontra instalações feitas pela Epic Games, Steam ou launcher oficial;
- abre o jogo pela plataforma correta, respeitando o fluxo da loja;
- consulta manifestos estáticos, sem depender da API pública do GitHub no computador do jogador;
- valida tamanho e SHA-256 de todos os downloads;
- preserva os arquivos originais antes de aplicar a tradução;
- usa instalação atômica e rollback quando uma operação falha;
- mantém um log técnico local para facilitar diagnósticos;
- verifica atualizações do próprio launcher;
- oferece atualização automática opcional, desativada por padrão;
- possui instalador, atalhos e desinstalador nativos para Windows.

## Instalação

1. Abra a página de [Releases](https://github.com/MauricioIkeda/nte-launcher-traducao-ptbr/releases/latest).
2. Baixe `NTE-Launcher-Traducao-PTBR-Setup.exe`.
3. Execute o instalador.
4. Abra **NTE Launcher Tradução PT-BR**.
5. Confirme ou selecione a pasta principal do jogo.
6. Clique em **Instalar tradução**.

A pasta correta normalmente contém:

```text
NTEGlobalLauncher.exe
Client\
```

Não selecione `Client`, `Paks`, `Binaries` ou uma pasta de downloads.

Quando a tradução estiver atualizada, a ação principal muda para **Jogar pela Epic Games**, **Jogar pela Steam** ou **Jogar pelo launcher oficial**, conforme a instalação detectada.

Para desfazer a modificação, clique em **Remover tradução**. O launcher restaurará os arquivos originais preservados no backup.

> [!NOTE]
> O instalador ainda não possui assinatura Authenticode. O Windows pode exibir o SmartScreen ou identificar o publicador como desconhecido. Confirme que o arquivo veio da release oficial deste repositório.

## Onde o programa é instalado

Instalação padrão:

```text
%LOCALAPPDATA%\Programs\NTE Launcher Tradução PT-BR
```

Executável:

```text
%LOCALAPPDATA%\Programs\NTE Launcher Tradução PT-BR\NTE-Launcher-Traducao-PTBR.exe
```

O launcher mantém preferências, logs, recibos, transações e backups no diretório de dados do usuário. Antes de apagar manualmente esses dados, remova a tradução pela interface.

## Como funciona

```text
Repositório da tradução
          │
          ▼
GitHub Action ── valida release, nomes, tamanhos e hashes
          │
          ▼
translation_manifest.json
          │
          ▼
Launcher ── baixa arquivos diretamente da release
          │
          ├── valida HTTPS, tamanho e SHA-256
          ├── preserva os originais
          └── instala com rollback protegido
```

O GitHub Action concentra a consulta à API. Os computadores dos jogadores baixam arquivos estáticos. Isso evita que usuários da mesma operadora ou rede CGNAT compartilhem o pequeno limite anônimo da API pública do GitHub.

## Plataformas do jogo

O launcher tenta identificar a origem da instalação:

- **Epic Games:** lê o manifesto local da Epic e inicia o jogo pelo protocolo oficial da loja;
- **Steam:** localiza o `appmanifest` e usa o protocolo oficial da Steam;
- **Launcher oficial:** inicia o executável oficial encontrado na pasta do jogo.

O botão de jogo funciona como um atalho para a plataforma detectada. O launcher não tenta falsificar login, conta, licença ou inicialização da loja.

## Segurança

Antes de modificar a instalação, o launcher:

1. aceita apenas downloads HTTPS;
2. rejeita caminhos absolutos e tentativas de sair da pasta do jogo;
3. confere o tamanho exato informado pelo manifesto;
4. calcula e compara o SHA-256 do arquivo;
5. preserva os arquivos originais;
6. escreve primeiro em arquivos temporários;
7. restaura o estado anterior se alguma etapa falhar.

O cliente HTTPS combina as raízes confiáveis do Windows com o bundle de certificados do projeto cURL/Mozilla.

Nenhum token do GitHub, Gemini API key ou AES key é distribuído com o launcher.

### Estado local, recibos e backups

O estado exibido vem dos arquivos reais encontrados no diretório selecionado. A versão salva nas preferências é apenas metadado de migração e não comprova que a tradução continua instalada.

Cada instalação do NTE recebe um identificador SHA-256 derivado do caminho canônico e mantém dados independentes:

```text
installations/
  <installation-id>/
    receipt.json
    originals/
    transactions/
```

O recibo registra hashes do que foi instalado e dos originais. Instalação, atualização e reparo usam uma transação com validação final; o recibo só é confirmado depois que todos os destinos passam por tamanho e SHA-256.

Na remoção, um arquivo ainda igual ao instalado é restaurado ou excluído. Se ele tiver sido alterado posteriormente, o launcher o preserva, informa uma remoção parcial e mantém recibo e backups para diagnóstico. Dados de outra pasta nunca são reutilizados.

## Atualização da tradução

O workflow [`update-translation-manifest.yml`](.github/workflows/update-translation-manifest.yml) possui dois modos:

1. **dispatch:** recebe da pipeline a tag e o hash exatos;
2. **recuperação:** no cron ou acionamento manual, procura a candidata pública válida mais recente.

Antes de atualizar, o workflow cruza o manifesto publicado com os assets instaláveis, restringe URLs e destinos e bloqueia downgrade, tag mutável ou datas ambíguas.

O launcher consulta, nesta ordem:

1. manifesto remoto;
2. última cópia válida armazenada em cache;
3. manifesto embutido.

Somente um manifesto remoto válido e comprovadamente mais novo pode iniciar atualização automática. Cache e bundle permitem uso offline, mas nunca provocam downgrade.

O contrato está documentado em [`docs/TRANSLATION_MANIFEST_SYNC.md`](docs/TRANSLATION_MANIFEST_SYNC.md).

## Atualização do próprio launcher

O arquivo [`launcher_manifest.json`](assets/manifest/launcher_manifest.json) informa versão, URL do instalador, tamanho e SHA-256.

Quando existe uma versão semântica mais recente, o launcher oferece a atualização. Se a opção automática estiver habilitada, ele baixa, valida e inicia o instalador silencioso, encerrando o processo atual antes da substituição.

O instalador conserva o mesmo `AppId` das versões anteriores para que o Windows reconheça novas releases como atualização do mesmo aplicativo.

## Desenvolvimento

O desenvolvimento é manual e consciente; não existe necessidade de executar um preparador automático.

Consulte:

**[Guia manual de desenvolvimento no Windows](docs/CONFIGURACAO_MANUAL_WINDOWS.md#cenário-b--desenvolver-o-launcher)**

Resumo do ambiente validado:

```text
Windows 10 ou 11
Flutter 3.44.8
Dart incluído no Flutter
Visual Studio com Desenvolvimento para desktop com C++
Git
Python 3.12 para ferramentas e testes
Inno Setup 6 somente para o instalador
GitHub CLI somente para operações remotas
```

Comandos essenciais depois de preparar o ambiente:

```powershell
flutter pub get
flutter run -d windows
flutter analyze
flutter test
flutter test integration_test
py -3.12 -m unittest discover -s tool -p "test_*.py"
flutter build windows --release
```

O executável Release fica em:

```text
build\windows\x64\runner\Release\NTE-Launcher-Traducao-PTBR.exe
```

Não mova apenas o `.exe`; execute-o dentro da pasta `Release`, junto de seus arquivos auxiliares.

## Publicar uma versão

O método recomendado é:

```text
Actions > Release Windows launcher > Run workflow
```

Informe:

- versão `MAJOR.MINOR.PATCH`, sem `v`;
- notas curtas;
- se a atualização deve ser obrigatória.

O workflow executa testes, compila o launcher e o instalador, publica a release e atualiza o manifesto do atualizador automático.

O processo completo de versão, build, Inno Setup, GitHub CLI e auditoria está no [guia manual](docs/CONFIGURACAO_MANUAL_WINDOWS.md#18-publicar-uma-release).

## Manifestos remotos

Tradução:

```text
https://raw.githubusercontent.com/MauricioIkeda/nte-launcher-traducao-ptbr/main/assets/manifest/translation_manifest.json
```

Launcher:

```text
https://raw.githubusercontent.com/MauricioIkeda/nte-launcher-traducao-ptbr/main/assets/manifest/launcher_manifest.json
```

Os endereços podem ser substituídos em builds personalizados com `NTE_MANIFEST_URL` e `NTE_LAUNCHER_MANIFEST_URL`.

## Documentação

- [Guia manual do launcher no Windows](docs/CONFIGURACAO_MANUAL_WINDOWS.md)
- [Sincronização do manifesto da tradução](docs/TRANSLATION_MANIFEST_SYNC.md)

## Créditos

- Tradução PT-BR e pipeline automática: MauricioIkeda / NTE Translation Studio
- Certificados: [cURL CA Extract](https://curl.se/docs/caextract.html)
- Carregamento técnico: [UniversalSigBypasser](https://github.com/rm-NoobInCoding/UniversalSigBypasser) e [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader)
- Desenvolvimento do launcher: [MauricioIkeda](https://github.com/MauricioIkeda)
- Interface: Flutter

Contribuições e relatos de problemas são bem-vindos.
