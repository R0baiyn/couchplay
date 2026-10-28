; Installateur Windows, compilé par le workflow de release :
;   iscc /DAppVersion=0.1.0 /O<dossier> windows\installer.iss
; Installation par utilisateur, sans droits admin : les mises à jour
; silencieuses de l'app se font sans fenêtre UAC. Les données (comptes,
; favoris, cache) vivent dans %APPDATA%, hors du dossier installé : la
; désinstallation n'y touche pas.

#ifndef AppVersion
  #error Passer la version : iscc /DAppVersion=x.y.z
#endif

[Setup]
; Ne jamais changer : c'est ce qui relie les versions entre elles.
AppId={{750E13A9-D1E3-4452-BC46-8184551AAB79}
AppName=CouchPlay
AppVersion={#AppVersion}
AppPublisher=CouchPlay
AppPublisherURL=https://github.com/R0baiyn/couchplay
DefaultDirName={autopf}\couchplay
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=couchplay-{#AppVersion}-windows-setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\couchplay.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; L'app ouverte pendant une installation manuelle est fermée proprement.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Avant de copier une nouvelle version : les fichiers de l'ancienne qu'elle
; ne livre plus ne restent pas. Le dossier {app} n'appartient qu'à l'app ;
; le désinstalleur (unins000.*) est gardé.
Type: files; Name: "{app}\*.dll"
Type: filesandordirs; Name: "{app}\data"

[Files]
; Le marqueur « portable » n'appartient qu'au zip.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "portable"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\CouchPlay"; Filename: "{app}\couchplay.exe"
Name: "{autodesktop}\CouchPlay"; Filename: "{app}\couchplay.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\couchplay.exe"; Description: "{cm:LaunchProgram,CouchPlay}"; Flags: nowait postinstall skipifsilent
