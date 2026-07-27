#ifndef MyAppVersion
  #define MyAppVersion "1.0.1"
#endif

#define MyAppName "NTE Launcher Tradução PT-BR"
#define MyAppExeName "NTE-Launcher-Traducao-PTBR.exe"
#define MyLegacyAppName "NTE Translation Launcher"
#define MyLegacyExeName "NTE-Traducao-PTBR.exe"
#define MyAppPublisher "Comunidade NTE PT-BR"
#define MyAppURL "https://github.com/MauricioIkeda/nte-launcher-traducao-ptbr"

[Setup]
AppId={{81100993-B692-4FCC-BA9D-0A1DC3A9C33E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\Programs\NTE Launcher Tradução PT-BR
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\build\installer
OutputBaseFilename=NTE-Launcher-Traducao-PTBR-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern dynamic
CloseApplications=yes
RestartApplications=yes
ChangesAssociations=no
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Instalador do launcher comunitário NTE PT-BR
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar um atalho na área de trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{app}\{#MyLegacyExeName}"
Type: files; Name: "{group}\{#MyLegacyAppName}.lnk"
Type: files; Name: "{autodesktop}\{#MyLegacyAppName}.lnk"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall
