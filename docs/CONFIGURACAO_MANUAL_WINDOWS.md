# Guia manual do NTE Launcher Tradução PT-BR no Windows

Este documento separa claramente dois cenários:

1. **usar o launcher para instalar a tradução**;
2. **desenvolver, testar, compilar ou publicar o launcher**.

Um jogador comum não precisa instalar Flutter, Visual Studio, Python, Git ou GitHub CLI.

## Cenário A — somente usar o launcher

### Requisitos

- Windows 10 ou Windows 11 de 64 bits;
- Neverness to Everness instalado por Epic Games, Steam ou launcher oficial;
- acesso à internet para baixar manifestos, traduções e atualizações;
- espaço livre para backups dos arquivos originais.

### Instalação

1. Abra a página de releases:
   <https://github.com/MauricioIkeda/nte-launcher-traducao-ptbr/releases/latest>
2. Baixe:

```text
NTE-Launcher-Traducao-PTBR-Setup.exe
```

3. Execute o instalador.
4. Caso o Windows mostre o SmartScreen, confira se o arquivo veio da release oficial deste repositório. O instalador ainda não possui assinatura Authenticode.
5. Abra **NTE Launcher Tradução PT-BR** pelo menu Iniciar ou pelo atalho criado.
6. Confirme a pasta do NTE.
7. Clique em **Instalar tradução**.

O programa é instalado normalmente em:

```text
%LOCALAPPDATA%\Programs\NTE Launcher Tradução PT-BR
```

O executável principal fica em:

```text
%LOCALAPPDATA%\Programs\NTE Launcher Tradução PT-BR\NTE-Launcher-Traducao-PTBR.exe
```

### Pasta correta do jogo

Selecione a pasta principal que contém:

```text
NTEGlobalLauncher.exe
Client\
```

Exemplos possíveis:

```text
G:\EpicGamesLibrary\NTENevernesstoEvernezYbAx
D:\Games\NevernessToEverness
```

Não selecione `Client`, `Paks`, `Binaries` ou uma pasta de downloads.

### Dados locais

O launcher mantém preferências, logs, recibos, transações e backups em seu diretório de dados do usuário. Os arquivos não ficam no repositório GitHub e não são necessários para reinstalar o programa, mas os backups são úteis enquanto uma tradução está instalada.

Antes de apagar manualmente os dados do launcher, remova a tradução pela própria interface.

### Atualizações

O launcher possui atualização própria opcional. Ele também consulta o manifesto da tradução e informa quando existe uma tradução mais nova.

Nenhum token GitHub, Gemini API key ou AES key é distribuído no aplicativo.

## Cenário B — desenvolver o launcher

### O que cada ferramenta faz

| Ferramenta | Necessária para | Não é necessária para |
|---|---|---|
| Git | clonar, versionar e criar branches | apenas usar o instalador |
| VS Code | editar Dart, Flutter, Python e arquivos de configuração | apenas usar o instalador |
| Flutter 3.44.8 | executar e compilar o launcher | apenas usar o instalador |
| Dart | linguagem do launcher; já vem com Flutter | instalação separada |
| Visual Studio com C++ | compilador nativo usado pelo Flutter no Windows | editar Dart sem compilar |
| Python 3.12 | ferramentas, geradores e testes Python do repositório | executar o launcher compilado |
| Inno Setup 6 | gerar o instalador `.exe` | executar ou depurar pelo Flutter |
| GitHub CLI | enviar branches, abrir PRs e disparar releases | desenvolvimento local sem GitHub |

## 1. Instalar o Git

Página oficial: <https://git-scm.com/download/win>

Instalação opcional pelo WinGet:

```powershell
winget install --exact --id Git.Git --source winget
```

Verifique:

```powershell
git --version
```

## 2. Instalar o Visual Studio Code

Página oficial: <https://code.visualstudio.com/>

Instalação opcional pelo WinGet:

```powershell
winget install --exact --id Microsoft.VisualStudioCode --source winget
```

Extensões recomendadas:

```text
Dart-Code.flutter
Dart-Code.dart-code
ms-python.python
GitHub.vscode-pull-request-github
```

Instalação pelo terminal:

```powershell
code --install-extension Dart-Code.flutter
code --install-extension Dart-Code.dart-code
code --install-extension ms-python.python
code --install-extension GitHub.vscode-pull-request-github
```

## 3. Instalar o Flutter 3.44.8

O projeto e o CI usam Flutter `3.44.8`. Para evitar que uma atualização futura do canal stable altere o ambiente, instale essa versão pelo arquivo oficial:

<https://docs.flutter.dev/install/archive?tab=windows>

Procedimento recomendado:

1. Baixe o ZIP do Flutter 3.44.8 para Windows.
2. Crie `C:\dev`.
3. Extraia para `C:\dev\flutter`.
4. Adicione `C:\dev\flutter\bin` à variável de usuário `Path`.
5. Feche e abra novamente seus terminais.

Verifique:

```powershell
flutter --version
flutter config --enable-windows-desktop
```

O Dart correto já está dentro do Flutter:

```powershell
dart --version
```

## 4. Instalar o Visual Studio Community

Flutter Windows precisa do compilador, Windows SDK e ferramentas CMake da Microsoft.

Página oficial: <https://visualstudio.microsoft.com/downloads/>

No Visual Studio Installer, selecione:

```text
Desenvolvimento para desktop com C++
```

Mantenha os componentes recomendados, incluindo:

- MSVC x64/x86;
- Windows SDK;
- ferramentas CMake para Windows.

Depois execute:

```powershell
flutter doctor -v
```

A seção do Visual Studio deve estar aprovada. Avisos relacionados a Android ou Chrome podem ser ignorados para este projeto Windows.

> [!NOTE]
> O Visual Studio Community e o Visual Studio Code são programas diferentes. VS Code é o editor; Visual Studio fornece o compilador nativo usado pelo Flutter.

## 5. Instalar o Python 3.12

Página oficial: <https://www.python.org/downloads/windows/>

Instalação opcional:

```powershell
winget install --exact --id Python.Python.3.12 --source winget
```

Verifique:

```powershell
py -3.12 --version
```

Python é usado pelos scripts em `tool/` e por validações de contrato. Ele não participa da interface Flutter durante o uso normal do launcher.

## 6. Instalar o Inno Setup 6

Só é necessário para criar o instalador final.

Página oficial: <https://jrsoftware.org/isinfo.php>

Instalação opcional:

```powershell
winget install --exact --id JRSoftware.InnoSetup --source winget
```

Caminhos comuns do compilador:

```text
C:\Program Files (x86)\Inno Setup 6\ISCC.exe
%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
```

## 7. Instalar e autenticar a GitHub CLI

Só é necessária para operações remotas.

Página oficial: <https://cli.github.com/>

```powershell
winget install --exact --id GitHub.cli --source winget
```

Entre na conta:

```powershell
gh auth login --hostname github.com --git-protocol https --web
```

Confirme:

```powershell
gh auth status --hostname github.com
```

Para releases e workflows:

```powershell
gh auth refresh --hostname github.com --scopes "repo,workflow"
gh auth setup-git --hostname github.com
```

Configure sua identidade Git:

```powershell
git config --global user.name "SEU_NOME_OU_LOGIN"
git config --global user.email "SEU_EMAIL_DO_GIT"
git config --global core.longpaths true
```

## 8. Clonar o repositório

```powershell
$Projects = Join-Path $HOME "Documents\GitHub"
New-Item -ItemType Directory -Force -Path $Projects | Out-Null
Set-Location $Projects

git clone https://github.com/MauricioIkeda/nte-launcher-traducao-ptbr.git
Set-Location .\nte-launcher-traducao-ptbr
```

Confirme:

```powershell
git branch --show-current
git status --short
git pull --ff-only
```

A branch deve ser `main` e o status deve estar vazio.

## 9. Abrir no VS Code

```powershell
code .
```

Pastas principais:

```text
lib\                         código Dart do launcher
windows\                     host nativo Windows do Flutter
test\                        testes unitários
integration_test\            testes de integração
assets\manifest\             manifestos embutidos
installer\                   projeto Inno Setup
tool\                        scripts e testes Python
.github\workflows\           CI, sincronização e release
```

## 10. Resolver dependências

```powershell
flutter pub get
```

Não use `flutter pub upgrade` casualmente. Ele pode atualizar versões além do que o projeto e o CI já validaram.

## 11. Executar em modo desenvolvimento

```powershell
flutter run -d windows
```

Durante a execução:

```text
r = hot reload
R = reinício completo
q = encerrar
```

O executável Debug é temporário. Para teste manual, prefira `flutter run -d windows` ou um build Release comum.

## 12. Simular uma pasta do jogo

Para testes que não devem tocar sua instalação real:

1. Crie uma pasta temporária.
2. Crie dentro dela um arquivo vazio chamado:

```text
NTEGlobalLauncher.exe
```

3. Crie somente os subdiretórios necessários ao cenário testado.
4. Selecione essa pasta no launcher de desenvolvimento.

Não execute instalação real de tradução em uma simulação incompleta, salvo quando o teste estiver explicitamente preparado para isso.

## 13. Formatar, analisar e testar

Formatação:

```powershell
dart format .
```

Análise estática:

```powershell
flutter analyze
```

Testes unitários:

```powershell
flutter test
```

Teste de integração Windows:

```powershell
flutter test integration_test
```

Testes Python:

```powershell
py -3.12 -m unittest discover -s tool -p "test_*.py"
```

Validação de espaços e finais de linha:

```powershell
git diff --check
```

Antes de um PR, o conjunto recomendado é:

```powershell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test integration_test
py -3.12 -m unittest discover -s tool -p "test_*.py"
git diff --check
```

## 14. Criar um build Release

A versão padrão vem de `pubspec.yaml`:

```powershell
flutter build windows --release
```

Executável:

```text
build\windows\x64\runner\Release\NTE-Launcher-Traducao-PTBR.exe
```

Execute esse arquivo dentro da pasta `Release`; não mova somente o `.exe`, porque DLLs e dados que acompanham o runner também são necessários.

## 15. Criar o instalador local

Primeiro compile o Release. Depois localize `ISCC.exe`:

```powershell
$IsccCandidates = @(
  "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)

$Iscc = $IsccCandidates |
  Where-Object { Test-Path -LiteralPath $_ } |
  Select-Object -First 1

if (-not $Iscc) {
  throw "ISCC.exe não encontrado. Instale o Inno Setup 6."
}
```

Leia a versão atual:

```powershell
$PubspecVersion = Select-String `
  -LiteralPath .\pubspec.yaml `
  -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+' |
  Select-Object -First 1

if (-not $PubspecVersion) {
  throw "Versão não encontrada no pubspec.yaml."
}

$Version = $PubspecVersion.Matches[0].Groups[1].Value
```

Compile o instalador:

```powershell
& $Iscc `
  "/DMyAppVersion=$Version" `
  ".\installer\NTE-Launcher-Traducao-PTBR.iss"
```

Saída:

```text
build\installer\NTE-Launcher-Traducao-PTBR-Setup.exe
```

## 16. Criar uma branch para alterações

Nunca programe diretamente na `main`.

```powershell
git checkout main
git pull --ff-only
git checkout -b fix/descricao-curta
```

Antes de adicionar arquivos:

```powershell
git status --short
git diff
git diff --check
```

Adicione somente o escopo correto:

```powershell
git add lib\arquivo.dart test\arquivo_test.dart
```

Commit e push:

```powershell
git commit -m "fix: descrição objetiva"
git push --set-upstream origin HEAD
```

## 17. Atualizar a versão

O campo fica em:

```text
pubspec.yaml
```

Formato:

```yaml
version: MAJOR.MINOR.PATCH+BUILD
```

Exemplo:

```yaml
version: 1.1.1+6
```

- `MAJOR`: mudança incompatível;
- `MINOR`: nova funcionalidade compatível;
- `PATCH`: correção compatível;
- `BUILD`: número crescente usado no pacote.

Não reutilize uma tag ou número de versão já publicado.

## 18. Publicar uma release

O método recomendado é o workflow:

```text
Actions > Release Windows launcher > Run workflow
```

Informe:

- versão sem `v`, por exemplo `1.1.2`;
- notas da versão;
- se a atualização deve ser obrigatória.

O workflow:

1. valida a versão;
2. executa análise e testes;
3. compila o build Windows;
4. cria o instalador;
5. calcula tamanho e SHA-256;
6. publica a tag e a release;
7. atualiza `assets/manifest/launcher_manifest.json`.

Depois da publicação, valide:

- workflow concluído com sucesso;
- tag apontando para o commit compilado;
- release não marcada como draft ou prerelease;
- apenas o instalador esperado como asset;
- manifesto com versão, URL, tamanho e SHA-256 corretos;
- arquivo baixado novamente com o mesmo SHA-256.

Nunca dispare novamente uma publicação parcialmente concluída sem primeiro auditar tag, release, asset e manifesto.

## 19. O que não precisa ser salvo antes de formatar

Para desenvolver novamente, não é necessário copiar:

```text
build\
.dart_tool\
.flutter-plugins-dependencies
```

Esses arquivos são recriados por `flutter pub get` e `flutter build`.

O que deve estar no GitHub:

```text
lib\
test\
integration_test\
windows\
assets\
installer\
tool\
.github\
pubspec.yaml
pubspec.lock
```

Antes de formatar, confira:

```powershell
git status --short
git log -1 --oneline
git fetch origin
git rev-parse HEAD
git rev-parse origin/main
```

Se estiver na `main`, sem mudanças locais, e os dois SHAs forem iguais, o checkout local não contém código exclusivo não enviado.

## 20. Solução de problemas

### `flutter` não é reconhecido

- confirme `C:\dev\flutter\bin` no `Path`;
- feche e reabra o terminal;
- execute `where.exe flutter`.

### Flutter não encontra o Visual Studio

Abra o Visual Studio Installer, escolha **Modificar** e confirme a carga **Desenvolvimento para desktop com C++**. Depois execute `flutter doctor -v`.

### Plugins exigem symlink

Ative o **Modo de Desenvolvedor**:

```text
Configurações > Sistema > Para desenvolvedores > Modo de Desenvolvedor
```

Depois feche e reabra o terminal.

### O executável Debug não abre ao clicar

Use:

```powershell
flutter run -d windows
```

Ou compile um Release comum:

```powershell
flutter build windows --release
```

### O launcher seleciona a pasta errada

Selecione a pasta que contém `NTEGlobalLauncher.exe`, não seus subdiretórios.

## Checklist do ambiente de desenvolvimento

```powershell
git --version
flutter --version
dart --version
flutter doctor -v
py -3.12 --version
gh auth status
flutter pub get
flutter analyze
flutter test
```

Com esses itens aprovados, você pode editar, testar, compilar e publicar o launcher sem depender de um preparador automático.
