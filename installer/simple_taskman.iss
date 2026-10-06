; ============================================================================
;  simple_taskman - Inno Setup script
;
;  Ships the finalized lean builds (no contracts) of the three targets:
;    taskman.exe         the window (simple_widgets on Win32, drawn with cairo)
;    taskman_cli.exe     snapshot, capabilities, trace, synthetic, clockwatch
;    taskman_stress.exe  known CPU, memory, and disk loads for testing
;  plus cairo.dll, taken from simple_cairo (ec.sh release rebuilds F_code
;  without it, so the build folder is not a reliable source).
;
;  Per-user install, no administrator rights: taskman runs as the user
;  (intent v3, D-1). The recording lives in %LOCALAPPDATA%\simple_taskman
;  and is the user's data: uninstall asks before removing it, and a silent
;  uninstall never removes it (Inno /SUPPRESSMSGBOXES answers Yes by itself).
;
;  Build:  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" simple_taskman.iss
;  Silent: simple_taskman-<version>-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
;          (launch it from PowerShell or cmd; Git-Bash rewrites /FLAGS)
; ============================================================================

#define AppName        "simple_taskman"
#define AppVersion     "0.2.0"
#define AppPublisher   "Larry Rix"
#define AppExeName     "taskman.exe"

[Setup]
AppId={{6A3D9B54-2C1E-4F87-9D0B-7E5A1C48F2D6}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/simple-eiffel/simple_taskman
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=.\output
OutputBaseFilename=simple_taskman-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}
CloseApplications=yes

PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\EIFGENs\taskman\F_code\simple_taskman_lean.exe";        DestDir: "{app}"; DestName: "taskman.exe";        Flags: ignoreversion
Source: "..\EIFGENs\taskman_cli\F_code\simple_taskman_lean.exe";    DestDir: "{app}"; DestName: "taskman_cli.exe";    Flags: ignoreversion
Source: "..\EIFGENs\taskman_stress\F_code\simple_taskman_lean.exe"; DestDir: "{app}"; DestName: "taskman_stress.exe"; Flags: ignoreversion
Source: "..\..\simple_cairo\cairo.dll";                              DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt";                                                DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\{#AppName}";                   Filename: "{app}\{#AppExeName}"
Name: "{group}\{#AppName} (do not record)";   Filename: "{app}\{#AppExeName}"; Parameters: "--no-record"
Name: "{group}\Uninstall {#AppName}";         Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";             Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The window's own soak log is ours. The recording (trace.db) is the user's
; history and is handled in [Code].
Type: files; Name: "{localappdata}\simple_taskman\logs\taskman-gui.log"

[Code]

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{localappdata}\simple_taskman');
    { Only after an explicit Yes in a real dialog. UninstallSilent comes first:
      under /VERYSILENT /SUPPRESSMSGBOXES a MsgBox returns its default (IDYES)
      without showing anything, and would delete the history unasked. }
    if DirExists(DataDir) and (not UninstallSilent) then
      if MsgBox('Remove the recorded history as well?' + #13#10#13#10 +
                'This deletes ' + DataDir + #13#10 +
                '(the trace of the last 30 days and the logs).' + #13#10#13#10 +
                'Choose No to keep it for a future reinstall.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(DataDir, True, True, True);
  end;
end;
