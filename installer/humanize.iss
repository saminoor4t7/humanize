; Inno Setup script for Humanize. Build with: iscc installer\humanize.iss
; Run "flutter build windows --release" first.
#define AppName "Humanize"
#define AppVersion "1.0.0"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{6B1F6C2E-4C0E-4C58-9E3F-5C3E0B2A7A11}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputBaseFilename=HumanizeSetup
OutputDir=output
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\humanize.exe

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\humanize.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\humanize.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
; Firewall: private networks, local subnet only.
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""Humanize TCP"" dir=in action=allow protocol=TCP localport=52525 program=""{app}\humanize.exe"" profile=private remoteip=localsubnet"; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""Humanize Discovery"" dir=in action=allow protocol=UDP localport=52526 program=""{app}\humanize.exe"" profile=private remoteip=localsubnet"; Flags: runhidden
Filename: "{app}\humanize.exe"; Description: "Launch Humanize"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""Humanize TCP"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""Humanize Discovery"""; Flags: runhidden
