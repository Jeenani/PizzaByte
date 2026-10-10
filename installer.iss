; Inno Setup Script for PizzaByte
; ---------------------------------
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "PizzaByte"
#define MyAppPublisher "Jeenani"
#define MyAppURL "https://github.com/Jeenani/PizzaByte"
#define MyAppExeName "PizzaByte.exe"

[Setup]
AppId={{E8F5C12A-94B2-4A8E-98D7-5678B12C3456}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=PizzaByte_Setup_v{#MyAppVersion}
SetupIconFile=app_ico.ico
UninstallDisplayIcon={app}\app_ico.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "build\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\PizzaByte.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "app_ico.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_ico.ico"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\app_ico.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
