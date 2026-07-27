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

## O que o launcher faz

- instala, atualiza e remove a tradução PT-BR pela mesma interface;
- encontra instalações feitas pela Epic Games, Steam ou launcher oficial;
- abre o jogo pela plataforma correta, respeitando o fluxo da loja;
- consulta manifestos estáticos, sem depender da API pública do GitHub;
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
5. Confirme ou selecione a pasta do jogo.
6. Clique em **Instalar tradução**.

Quando a tradução estiver atualizada, a ação principal muda para **Jogar pela
Epic Games**, **Jogar pela Steam** ou **Jogar pelo launcher oficial**, conforme
a instalação detectada.

Para desfazer a modificação, clique em **Remover tradução**. O launcher
restaurará os arquivos originais preservados no backup.

> [!NOTE]
> O instalador ainda não possui assinatura Authenticode. O Windows pode exibir
> o SmartScreen ou identificar o publicador como desconhecido.

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

O GitHub Action concentra a consulta à API. Os computadores dos jogadores
baixam apenas arquivos estáticos pelo `raw.githubusercontent.com`. Isso evita
que usuários da mesma operadora ou rede CGNAT compartilhem o pequeno limite
anônimo da API do GitHub.

## Plataformas do jogo

O launcher tenta identificar a origem da instalação:

- **Epic Games:** lê o manifesto local da Epic e inicia o jogo pelo protocolo
  oficial da loja;
- **Steam:** localiza o `appmanifest` e usa o protocolo oficial da Steam;
- **Launcher oficial:** inicia o executável oficial encontrado na pasta do
  jogo.

O botão de jogo funciona como um atalho para a plataforma detectada. O launcher
não tenta falsificar login, conta, licença ou inicialização da loja.

## Segurança

Antes de modificar a instalação, o launcher:

1. aceita apenas downloads HTTPS;
2. rejeita caminhos absolutos e tentativas de sair da pasta do jogo;
3. confere o tamanho exato informado pelo manifesto;
4. calcula e compara o SHA-256 do arquivo;
5. preserva os arquivos originais;
6. escreve primeiro em arquivos temporários;
7. restaura o estado anterior se alguma etapa falhar.

O cliente HTTPS combina as raízes confiáveis do Windows com o bundle de
certificados do projeto cURL/Mozilla. Isso corrige ambientes em que a cadeia de
certificados apresentada ao Flutter não pode ser validada apenas pelo sistema.

## Atualização da tradução

O workflow
[`update-translation-manifest.yml`](.github/workflows/update-translation-manifest.yml)
é executado periodicamente e também pode ser iniciado manualmente. Ele:

1. consulta a release mais recente de
   [`MauricioIkeda/nte-ptbr-automatic-translation`](https://github.com/MauricioIkeda/nte-ptbr-automatic-translation);
2. exige os arquivos conhecidos da tradução;
3. valida nomes, URLs e tamanhos;
4. obtém ou calcula o SHA-256;
5. executa os testes do gerador;
6. atualiza o manifesto somente quando a tradução muda.

O launcher consulta, nesta ordem:

1. manifesto remoto;
2. última cópia válida armazenada em cache;
3. manifesto de emergência incluído no aplicativo.

Nenhum token do GitHub é distribuído com o launcher.

## Atualização do launcher

O arquivo
[`launcher_manifest.json`](assets/manifest/launcher_manifest.json) informa a
versão mais recente, o endereço do instalador, seu tamanho e SHA-256.

Quando existe uma versão semântica mais recente, o launcher oferece a
atualização na interface. Se a opção automática estiver habilitada, ele baixa,
valida e inicia o instalador silencioso, encerrando o processo atual antes de
substituir os arquivos.

### Compatibilidade com a versão 1.0.0

O nome público foi padronizado como **NTE Launcher Tradução PT-BR**, mas o
instalador conserva o mesmo `AppId` da versão 1.0.0. Assim, o Windows reconhece
as versões futuras como atualização do programa existente.

A primeira atualização com o nome padronizado também remove o executável e os
atalhos antigos. A pasta técnica de dados permanece compatível para preservar
configurações, recibos de instalação e backups necessários para remover a
tradução.

## Desenvolvimento

### Requisitos

- Windows 10 ou 11;
- Flutter 3.44.8 ou compatível, com desktop Windows habilitado;
- Visual Studio com **Desenvolvimento para desktop com C++**;
- Git;
- Python 3 para os geradores de manifesto;
- Inno Setup 6 para compilar o instalador localmente.

### Executar e testar

```powershell
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat run -d windows
```

Para simular uma instalação do jogo, crie uma pasta vazia, coloque nela um
arquivo chamado `NTEGlobalLauncher.exe` e selecione essa pasta na interface.

Validação do projeto:

```powershell
C:\flutter\bin\flutter.bat analyze
C:\flutter\bin\flutter.bat test
python -m unittest discover -s tool -p "test_*.py"
```

### Build para Windows

```powershell
C:\flutter\bin\flutter.bat build windows --release `
  --build-name 1.1.0 --build-number 3
```

O executável será criado em:

```text
build/windows/x64/runner/Release/NTE-Launcher-Traducao-PTBR.exe
```

### Instalador local

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" `
  "/DMyAppVersion=1.1.0" `
  "installer\NTE-Launcher-Traducao-PTBR.iss"
```

Resultado:

```text
build/installer/NTE-Launcher-Traducao-PTBR-Setup.exe
```

Novas instalações são feitas em
`%LOCALAPPDATA%\Programs\NTE Launcher Tradução PT-BR`, sem exigir privilégios
administrativos.

## Publicar uma versão

O workflow
[`release-launcher.yml`](.github/workflows/release-launcher.yml) pode ser
iniciado em **Actions > Release Windows launcher > Run workflow**.

Informe:

- uma versão no formato `MAJOR.MINOR.PATCH`, sem o prefixo `v`;
- notas curtas da versão;
- se a atualização deve ou não ser obrigatória.

O workflow executa testes, compila o launcher e o instalador, publica a GitHub
Release e atualiza o manifesto usado pelo atualizador automático.

Também é possível publicar por tag:

```powershell
git tag v1.1.0
git push origin v1.1.0
```

## Manifestos remotos

Tradução:

```text
https://raw.githubusercontent.com/MauricioIkeda/nte-launcher-traducao-ptbr/main/assets/manifest/translation_manifest.json
```

Launcher:

```text
https://raw.githubusercontent.com/MauricioIkeda/nte-launcher-traducao-ptbr/main/assets/manifest/launcher_manifest.json
```

Os endereços podem ser substituídos em builds personalizados com
`NTE_MANIFEST_URL` e `NTE_LAUNCHER_MANIFEST_URL`.

## Créditos

- Tradução PT-BR:
  [`Luxx34/nte-pt-br`](https://github.com/Luxx34/nte-pt-br)
- Certificados:
  [cURL CA Extract](https://curl.se/docs/caextract.html)
- Interface e launcher: Flutter

Contribuições e relatos de problemas são bem-vindos.
