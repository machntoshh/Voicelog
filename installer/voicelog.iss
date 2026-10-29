; Instalador do VoiceLog para Windows (Inno Setup 6).
; Gerado por build_release.bat, que passa AppVersion e VCRedistDir via /D.
; Instala só para o usuário atual: não pede senha de administrador.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8C3D5E2A-6F41-4B7A-9E1C-2D7F0A5B4C93}
AppName=VoiceLog
AppVersion={#AppVersion}
AppVerName=VoiceLog {#AppVersion}
AppPublisher=Eric Marques
AppPublisherURL=https://github.com/machntoshh/Voicelog
AppSupportURL=https://github.com/machntoshh/Voicelog/issues
DefaultDirName={autopf}\VoiceLog
DefaultGroupName=VoiceLog
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile=..\LICENSE
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\voicelog.exe
UninstallDisplayName=VoiceLog
OutputDir=..\dist
OutputBaseFilename=VoiceLog-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Runtime do Visual C++, para o app abrir também em Windows recém-instalados.
Source: "{#VCRedistDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\VoiceLog"; Filename: "{app}\voicelog.exe"
Name: "{autodesktop}\VoiceLog"; Filename: "{app}\voicelog.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\voicelog.exe"; Description: "{cm:LaunchProgram,VoiceLog}"; Flags: nowait postinstall skipifsilent

; As gravações ficam em Documentos\VoiceLog e NÃO são apagadas ao desinstalar.
