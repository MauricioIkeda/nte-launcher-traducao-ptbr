[CmdletBinding()]
param(
    [string] $ProjectsRoot = "",
    [switch] $SkipNteConfiguration,
    [switch] $SkipBuild,
    [switch] $CheckOnly
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$FlutterVersion = "3.44.8"
$PipelineRepository = "MauricioIkeda/nte-ptbr-automatic-translation"
$LauncherRepository = "MauricioIkeda/nte-launcher-traducao-ptbr"

function Write-Step {
    param([string] $Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string] $Message)
    Write-Host "    OK: $Message" -ForegroundColor Green
}

function Refresh-ProcessPath {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Add-UserPath {
    param([string] $Directory)
    $normalized = [IO.Path]::GetFullPath($Directory).TrimEnd("\")
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @($current -split ";" | Where-Object { $_ })
    if ($entries | Where-Object {
        $_.TrimEnd("\").Equals(
            $normalized, [StringComparison]::OrdinalIgnoreCase
        )
    }) {
        return
    }
    [Environment]::SetEnvironmentVariable(
        "Path", (($entries + $normalized) -join ";"), "User"
    )
    Refresh-ProcessPath
}

function Test-CommandAvailable {
    param([string[]] $Names)
    foreach ($name in $Names) {
        if (Get-Command $name -ErrorAction SilentlyContinue) {
            return $true
        }
    }
    return $false
}

function Test-WingetPackage {
    param([string] $Id)
    $result = & winget.exe list --exact --id $Id `
        --accept-source-agreements 2>$null | Out-String
    return ($LASTEXITCODE -eq 0 -and $result -match [regex]::Escape($Id))
}

function Install-WingetPackage {
    param(
        [string] $Name,
        [string] $Id,
        [string[]] $Commands = @(),
        [string[]] $KnownPaths = @(),
        [string] $Override = ""
    )
    $present = $false
    if ($Commands.Count -gt 0) {
        $present = Test-CommandAvailable $Commands
    }
    if (-not $present) {
        foreach ($knownPath in $KnownPaths) {
            if (Test-Path -LiteralPath $knownPath) {
                $present = $true
                break
            }
        }
    }
    if (-not $present) {
        $present = Test-WingetPackage $Id
    }
    if ($present) {
        Write-Ok "$Name já está instalado"
        return
    }
    if ($CheckOnly) {
        Write-Host "    AUSENTE: $Name" -ForegroundColor Yellow
        return
    }

    Write-Host "    Instalando $Name..."
    $arguments = @(
        "install", "--exact", "--id", $Id, "--source", "winget",
        "--accept-package-agreements", "--accept-source-agreements"
    )
    if ($Override) {
        $arguments += @("--override", $Override)
    } else {
        $arguments += "--silent"
    }
    & winget.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "O WinGet não conseguiu instalar $Name ($Id)."
    }
    Refresh-ProcessPath
}

function Get-PythonExecutable {
    $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($launcher) {
        try {
            $resolved = & $launcher.Source -3.12 -c `
                "import sys; print(sys.executable)" 2>$null
        } catch {
            $resolved = ""
        }
        if ($LASTEXITCODE -eq 0 -and $resolved) {
            return $resolved.Trim()
        }
    }
    foreach ($name in @("python.exe", "python3.exe")) {
        $candidate = Get-Command $name -ErrorAction SilentlyContinue
        if (-not $candidate) {
            continue
        }
        try {
            $resolved = & $candidate.Source -c `
                "import sys; print(sys.executable)" 2>$null
        } catch {
            $resolved = ""
        }
        if ($LASTEXITCODE -eq 0 -and $resolved) {
            return $resolved.Trim()
        }
    }
    return ""
}

function Get-VisualStudioPath {
    param([switch] $RequireNativeDesktop)
    $vswhere = Join-Path ${env:ProgramFiles(x86)} `
        "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        return ""
    }
    $arguments = @("-latest", "-products", "*")
    if ($RequireNativeDesktop) {
        $arguments += @(
            "-requires", "Microsoft.VisualStudio.Workload.NativeDesktop"
        )
    }
    $arguments += @("-property", "installationPath")
    $path = & $vswhere @arguments
    if ($LASTEXITCODE -eq 0 -and $path) {
        return $path.Trim()
    }
    return ""
}

function Ensure-VisualStudio {
    $installation = Get-VisualStudioPath -RequireNativeDesktop
    if ($installation) {
        Write-Ok "Visual Studio com Desenvolvimento para desktop com C++"
        return
    }
    if ($CheckOnly) {
        Write-Host `
            "    AUSENTE: Visual Studio com Desenvolvimento para desktop com C++" `
            -ForegroundColor Yellow
        return
    }

    $existingInstallation = Get-VisualStudioPath
    if ($existingInstallation) {
        Write-Host "    Adicionando a carga de trabalho C++ ao Visual Studio..."
        $setup = Join-Path ${env:ProgramFiles(x86)} `
            "Microsoft Visual Studio\Installer\setup.exe"
        $arguments = @(
            "modify",
            "--installPath", "`"$existingInstallation`"",
            "--add", "Microsoft.VisualStudio.Workload.NativeDesktop",
            "--includeRecommended",
            "--passive",
            "--norestart"
        )
        $process = Start-Process -FilePath $setup -ArgumentList $arguments `
            -Verb RunAs -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "O Visual Studio Installer não concluiu a carga C++."
        }
    } else {
        Write-Host "    Instalando Visual Studio e a carga de trabalho C++..."
        $override = (
            "--wait --passive --norestart " +
            "--add Microsoft.VisualStudio.Workload.NativeDesktop " +
            "--includeRecommended"
        )
        Install-WingetPackage `
            -Name "Visual Studio Community" `
            -Id "Microsoft.VisualStudio.Community" `
            -Override $override
    }
    if (-not (Get-VisualStudioPath -RequireNativeDesktop)) {
        throw (
            "O Visual Studio foi instalado, mas a carga de trabalho " +
            "'Desenvolvimento para desktop com C++' não foi encontrada. " +
            "Execute este preparador novamente após concluir o instalador."
        )
    }
}

function Ensure-Flutter {
    if (Test-CommandAvailable @("flutter.bat", "flutter.exe")) {
        $versionLine = (& flutter --version 2>$null | Select-Object -First 1)
        Write-Ok "Flutter já está instalado ($versionLine)"
        return
    }
    if ($CheckOnly) {
        Write-Host "    AUSENTE: Flutter $FlutterVersion" -ForegroundColor Yellow
        return
    }

    $flutterRoot = Join-Path $env:LOCALAPPDATA "Programs\flutter"
    if (Test-Path -LiteralPath $flutterRoot) {
        throw (
            "$flutterRoot já existe, mas o Flutter não foi encontrado. " +
            "Corrija ou renomeie essa pasta e execute novamente."
        )
    }
    Write-Host "    Instalando Flutter $FlutterVersion..."
    New-Item -ItemType Directory -Force `
        -Path (Split-Path $flutterRoot -Parent) | Out-Null
    & git clone --branch $FlutterVersion --depth 1 `
        https://github.com/flutter/flutter.git $flutterRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível baixar o Flutter."
    }
    Add-UserPath (Join-Path $flutterRoot "bin")
    & flutter config --enable-windows-desktop
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível habilitar o Flutter para Windows."
    }
}

function Update-RepositorySafely {
    param([string] $Directory)
    if ($CheckOnly) {
        return
    }
    $changes = & git -C $Directory status --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível consultar o repositório $Directory."
    }
    if ($changes) {
        Write-Host `
            "    Alterações locais encontradas; atualização automática ignorada." `
            -ForegroundColor Yellow
        return
    }
    & git -C $Directory pull --ff-only | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível atualizar $Directory sem criar conflitos."
    }
}

function Ensure-Repository {
    param(
        [string] $Name,
        [string] $Repository,
        [string] $Destination
    )
    if (Test-Path -LiteralPath (Join-Path $Destination ".git")) {
        Write-Ok "$Name encontrado em $Destination"
        Update-RepositorySafely $Destination
        return $Destination
    }
    if (Test-Path -LiteralPath $Destination) {
        throw (
            "A pasta $Destination já existe, mas não é um repositório Git. " +
            "Escolha outro diretório ou renomeie a pasta."
        )
    }
    if ($CheckOnly) {
        Write-Host "    AUSENTE: $Name em $Destination" -ForegroundColor Yellow
        return $Destination
    }
    Write-Host "    Baixando $Name..."
    & gh repo clone $Repository $Destination | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível baixar $Repository."
    }
    return $Destination
}

function Restore-PrivateTranslationState {
    param(
        [string] $Pipeline,
        [string] $Repository
    )
    $database = Join-Path $Pipeline "workspace\workspace.sqlite3"
    if (Test-Path -LiteralPath $database) {
        Write-Ok "Memória de tradução local preservada"
        return
    }
    if ($CheckOnly) {
        Write-Host "    Memória local ausente; a restauração será procurada." `
            -ForegroundColor Yellow
        return
    }

    Write-Host "    Procurando o backup privado mais recente..."
    $releases = & gh api "repos/$Repository/releases?per_page=100" |
        ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível consultar os backups privados."
    }
    $release = @($releases |
        Where-Object { $_.tag_name -like "dev-state-*" } |
        Sort-Object -Property published_at -Descending |
        Select-Object -First 1)
    if ($release.Count -eq 0) {
        Write-Host (
            "    Nenhum backup privado encontrado. Uma memória nova será " +
            "criada na primeira extração."
        ) -ForegroundColor Yellow
        return
    }

    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) `
        "nte-private-restore-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        & gh release download $release[0].tag_name `
            --repo $Repository `
            --pattern "nte-workspace.sqlite3.zip" `
            --dir $temporaryRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Não foi possível baixar o backup privado."
        }
        $archive = Join-Path $temporaryRoot "nte-workspace.sqlite3.zip"
        $expanded = Join-Path $temporaryRoot "expanded"
        Expand-Archive -LiteralPath $archive -DestinationPath $expanded
        $restoredDatabase = Join-Path $expanded "workspace.sqlite3"
        if (-not (Test-Path -LiteralPath $restoredDatabase)) {
            throw "O backup privado não contém o banco esperado."
        }
        New-Item -ItemType Directory -Force `
            -Path (Split-Path $database -Parent) | Out-Null
        Copy-Item -LiteralPath $restoredDatabase -Destination $database
        Write-Ok "Memória restaurada de $($release[0].tag_name)"
    } finally {
        $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
        $resolvedSystemTemp = [IO.Path]::GetFullPath(
            [IO.Path]::GetTempPath()
        ).TrimEnd("\") + "\"
        if (
            $resolvedTemporaryRoot.StartsWith(
                $resolvedSystemTemp, [StringComparison]::OrdinalIgnoreCase
            ) -and
            (Test-Path -LiteralPath $resolvedTemporaryRoot)
        ) {
            Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
        }
    }
}

function Set-GitIdentityFromGitHub {
    & git config --global core.longpaths true
    $currentName = & git config --global user.name
    $currentEmail = & git config --global user.email
    if ($currentName -and $currentEmail) {
        Write-Ok "Identidade do Git configurada"
        return
    }
    if ($CheckOnly) {
        Write-Host "    AUSENTE: identidade global do Git" -ForegroundColor Yellow
        return
    }
    $login = (& gh api user --jq ".login").Trim()
    $id = (& gh api user --jq ".id").Trim()
    if (-not $currentName) {
        & git config --global user.name $login
    }
    if (-not $currentEmail) {
        & git config --global user.email "$id+$login@users.noreply.github.com"
    }
    Write-Ok "Identidade do Git configurada como $login"
}

function New-DevelopmentWorkspace {
    param(
        [string] $Root,
        [string] $Pipeline,
        [string] $Launcher
    )
    if ($CheckOnly) {
        return
    }
    $workspacePath = Join-Path $Root "NTE-PTBR.code-workspace"
    $workspace = [ordered]@{
        folders = @(
            [ordered]@{ name = "Pipeline privada"; path = $Pipeline },
            [ordered]@{ name = "Launcher"; path = $Launcher }
        )
        settings = [ordered]@{
            "files.encoding" = "utf8"
            "editor.formatOnSave" = $true
        }
    }
    $workspace | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $workspacePath -Encoding utf8

    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) {
        return
    }
    $shell = New-Object -ComObject WScript.Shell
    $studioShortcut = $shell.CreateShortcut(
        (Join-Path $desktop "NTE Translation Studio.lnk")
    )
    $studioShortcut.TargetPath = Join-Path $Pipeline "Abrir-Studio.cmd"
    $studioShortcut.WorkingDirectory = $Pipeline
    $studioShortcut.Save()

    $backupShortcut = $shell.CreateShortcut(
        (Join-Path $desktop "Salvar estado da tradução NTE.lnk")
    )
    $backupShortcut.TargetPath = Join-Path $Pipeline `
        "Salvar-Estado-Privado.cmd"
    $backupShortcut.WorkingDirectory = $Pipeline
    $backupShortcut.Save()

    $code = Get-Command code.cmd -ErrorAction SilentlyContinue
    if ($code) {
        $developmentShortcut = $shell.CreateShortcut(
            (Join-Path $desktop "Desenvolvimento NTE PT-BR.lnk")
        )
        $developmentShortcut.TargetPath = $code.Source
        $developmentShortcut.Arguments = "`"$workspacePath`""
        $developmentShortcut.WorkingDirectory = $Root
        $developmentShortcut.Save()
    }
}

Write-Host "Preparador inteligente do ambiente NTE PT-BR" `
    -ForegroundColor White
Write-Host (
    "O processo pode ser executado novamente: componentes existentes " +
    "serão preservados."
)

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw (
        "O WinGet não está disponível. Instale ou atualize o aplicativo " +
        "'Instalador de Aplicativo' da Microsoft Store e execute novamente."
    )
}

if (-not $ProjectsRoot) {
    $documents = [Environment]::GetFolderPath("MyDocuments")
    $ProjectsRoot = Join-Path $documents "GitHub"
}
$ProjectsRoot = [IO.Path]::GetFullPath($ProjectsRoot)
if (-not $CheckOnly) {
    New-Item -ItemType Directory -Force -Path $ProjectsRoot | Out-Null
}

Write-Step "Verificando programas essenciais"
Install-WingetPackage -Name "Git" -Id "Git.Git" -Commands @("git.exe")
Install-WingetPackage -Name "GitHub CLI" -Id "GitHub.cli" -Commands @("gh.exe")
Install-WingetPackage `
    -Name "GitHub Desktop" `
    -Id "GitHub.GitHubDesktop" `
    -KnownPaths @(
        (Join-Path $env:LOCALAPPDATA "GitHubDesktop\GitHubDesktop.exe")
    )
Install-WingetPackage `
    -Name "Visual Studio Code" `
    -Id "Microsoft.VisualStudioCode" `
    -Commands @("code.cmd", "code.exe")
$availablePython = Get-PythonExecutable
if ($availablePython) {
    Write-Ok "Python já está instalado em $availablePython"
} else {
    Install-WingetPackage `
        -Name "Python 3.12" `
        -Id "Python.Python.3.12"
}
Install-WingetPackage `
    -Name "Inno Setup 6" `
    -Id "JRSoftware.InnoSetup" `
    -KnownPaths @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe")
    )
Refresh-ProcessPath
Ensure-VisualStudio
Ensure-Flutter
Refresh-ProcessPath

if (-not $CheckOnly) {
    $python = Get-PythonExecutable
    if (-not $python) {
        throw "O Python foi instalado, mas não pôde ser executado."
    }
    Write-Ok "Python disponível em $python"
}

Write-Step "Configurando acesso seguro ao GitHub"
if ($CheckOnly) {
    & gh auth status --hostname github.com
} else {
    & gh auth status --hostname github.com *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host (
            "    O navegador será aberto para você entrar na conta GitHub " +
            "que possui acesso à pipeline privada."
        )
        & gh auth login --hostname github.com --git-protocol https `
            --web --scopes "repo,workflow"
        if ($LASTEXITCODE -ne 0) {
            throw "A autenticação no GitHub não foi concluída."
        }
    } else {
        Write-Ok "GitHub CLI já está autenticado"
    }
    $authData = (& gh auth status --hostname github.com --json hosts |
        ConvertFrom-Json)
    $activeAuth = @($authData.hosts."github.com" |
        Where-Object { $_.active -eq $true })[0]
    $scopes = @($activeAuth.scopes -split ",\s*")
    if ($scopes -notcontains "repo" -or $scopes -notcontains "workflow") {
        Write-Host "    Autorizando publicação nos repositórios do projeto..."
        & gh auth refresh --hostname github.com --scopes "repo,workflow"
        if ($LASTEXITCODE -ne 0) {
            throw "As permissões necessárias do GitHub não foram concedidas."
        }
    }
    & gh auth setup-git --hostname github.com
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível configurar o Git para usar o login seguro."
    }
    Set-GitIdentityFromGitHub
}

Write-Step "Preparando os repositórios"
$scriptLauncherRoot = Split-Path $PSScriptRoot -Parent
if (Test-Path -LiteralPath (Join-Path $scriptLauncherRoot ".git")) {
    $launcherRoot = $scriptLauncherRoot
} else {
    $launcherRoot = Join-Path $ProjectsRoot "nte-launcher-traducao-ptbr"
}
$pipelineCandidates = @(
    (Join-Path $ProjectsRoot "nte-translation-pipeline"),
    (Join-Path $ProjectsRoot "nte-ptbr-automatic-translation")
)
$pipelineRoot = $pipelineCandidates[0]
foreach ($candidate in $pipelineCandidates) {
    if (Test-Path -LiteralPath (Join-Path $candidate ".git")) {
        $pipelineRoot = $candidate
        break
    }
}
$launcherRoot = Ensure-Repository `
    -Name "Launcher público" `
    -Repository $LauncherRepository `
    -Destination $launcherRoot
$pipelineRoot = Ensure-Repository `
    -Name "Pipeline privada" `
    -Repository $PipelineRepository `
    -Destination $pipelineRoot
Restore-PrivateTranslationState `
    -Pipeline $pipelineRoot `
    -Repository $PipelineRepository

if (-not $CheckOnly) {
    Write-Step "Instalando extensões de desenvolvimento"
    foreach ($extension in @(
        "Dart-Code.flutter",
        "Dart-Code.dart-code",
        "ms-python.python",
        "GitHub.vscode-pull-request-github"
    )) {
        & code --install-extension $extension --force | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Não foi possível instalar a extensão $extension."
        }
    }

    if (-not $SkipNteConfiguration) {
        Write-Step "Configurando ferramentas e credenciais locais do NTE"
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $pipelineRoot "Configurar-NTE.ps1") `
            -PythonPath $python
        if ($LASTEXITCODE -ne 0) {
            throw "A configuração local da pipeline não foi concluída."
        }
    }

    if (-not $SkipBuild) {
        Write-Step "Preparando e validando o Translation Studio"
        Push-Location (Join-Path $pipelineRoot "studio")
        try {
            & flutter pub get
            if ($LASTEXITCODE -ne 0) { throw "flutter pub get falhou no Studio." }
            & flutter analyze
            if ($LASTEXITCODE -ne 0) { throw "flutter analyze falhou no Studio." }
            & flutter build windows --release
            if ($LASTEXITCODE -ne 0) { throw "O build do Studio falhou." }
        } finally {
            Pop-Location
        }

        Write-Step "Preparando e validando o launcher"
        Push-Location $launcherRoot
        try {
            & flutter pub get
            if ($LASTEXITCODE -ne 0) { throw "flutter pub get falhou no launcher." }
            & flutter analyze
            if ($LASTEXITCODE -ne 0) { throw "flutter analyze falhou no launcher." }
            & flutter test
            if ($LASTEXITCODE -ne 0) { throw "Os testes do launcher falharam." }
        } finally {
            Pop-Location
        }
    }

    New-DevelopmentWorkspace `
        -Root $ProjectsRoot `
        -Pipeline $pipelineRoot `
        -Launcher $launcherRoot

    Write-Step "Diagnóstico final"
    & flutter doctor -v
    Write-Host ""
    Write-Host "Ambiente preparado com sucesso." -ForegroundColor Green
    Write-Host "Studio:  $(Join-Path $pipelineRoot 'Abrir-Studio.cmd')"
    Write-Host "Projetos: $(Join-Path $ProjectsRoot 'NTE-PTBR.code-workspace')"
    Write-Host (
        "Os avisos do Flutter sobre Android ou Chrome podem ser ignorados: " +
        "estes projetos usam o Windows desktop."
    )
}
