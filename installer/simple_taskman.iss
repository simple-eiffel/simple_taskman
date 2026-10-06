; ============================================================================
;  simple_taskman - Inno Setup script
;
;  Ships the finalized lean builds (no contracts) of the four targets:
;    taskman.exe           the window
;    taskman_recorder.exe  the background recorder (no window; "Record from logon")
;    taskman_cli.exe       snapshot, capabilities, trace, synthetic, clockwatch
;    taskman_stress.exe    known CPU, memory, and disk loads for testing
;  plus cairo.dll, taken from simple_cairo (ec.sh release rebuilds F_code
;  without it, so the build folder is not a reliable source).
;
;  Per-user install, no administrator rights (intent v3, D-1). The recording
;  in %LOCALAPPDATA%\simple_taskman is the user's data: uninstall asks before
;  removing it, and a silent uninstall never removes it (Inno
;  /SUPPRESSMSGBOXES answers Yes by itself).
;
;  Safety: if Ctrl+Shift+Esc still opens this simple_taskman (the taskmgr.exe
;  Image File Execution Options "Debugger" value), uninstalling would leave
;  Ctrl+Shift+Esc opening nothing, so uninstall refuses until the switch is
;  turned off in Settings (which needs administrator rights).
;
;  Build:  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" simple_taskman.iss
;  Silent: simple_taskman-<version>-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
;          (launch it from PowerShell or cmd; Git-Bash rewrites /FLAGS)
; ============================================================================

#define AppName        "simple_taskman"
#define AppVersion     "0.3.0"
#define AppPublisher   "Larry Rix"
#define AppExeName     "taskman.exe"
#define RunKey         "Software\Microsoft\Windows\CurrentVersion\Run"
#define RecorderValue  "simple_taskman recorder"
#define IfeoKey        "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\taskmgr.exe"

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
Source: "..\EIFGENs\taskman\F_code\simple_taskman_lean.exe";          DestDir: "{app}"; DestName: "taskman.exe";          Flags: ignoreversion
Source: "..\EIFGENs\taskman_recorder\F_code\simple_taskman_lean.exe"; DestDir: "{app}"; DestName: "taskman_recorder.exe"; Flags: ignoreversion
Source: "..\EIFGENs\taskman_cli\F_code\simple_taskman_lean.exe";      DestDir: "{app}"; DestName: "taskman_cli.exe";      Flags: ignoreversion
Source: "..\EIFGENs\taskman_stress\F_code\simple_taskman_lean.exe";   DestDir: "{app}"; DestName: "taskman_stress.exe";   Flags: ignoreversion
Source: "..\..\simple_cairo\cairo.dll";                                DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt";                                                  DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\{#AppName}";                   Filename: "{app}\{#AppExeName}"
Name: "{group}\{#AppName} (do not record)";   Filename: "{app}\{#AppExeName}"; Parameters: "--no-record"
Name: "{group}\Uninstall {#AppName}";         Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";             Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; Restart the background recorder after an upgrade when the owner records from logon.
Filename: "{app}\taskman_recorder.exe"; Flags: nowait; Check: RecorderRegistered
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/IM taskman_recorder.exe /F"; Flags: runhidden; RunOnceId: "StopRecorder"

[UninstallDelete]
; The window's soak log is ours. The recording (trace.db) is the user's
; history and is handled in [Code].
Type: files; Name: "{localappdata}\simple_taskman\logs\taskman-gui.log"

[Code]

function RecorderRegistered: Boolean;
begin
  Result := RegValueExists(HKEY_CURRENT_USER, '{#RunKey}', '{#RecorderValue}');
end;

function CtrlShiftEscOpensThisCopy: Boolean;
var
  Target: String;
begin
  Result := False;
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, '{#IfeoKey}', 'Debugger', Target) then
    Result := Pos(Lowercase(ExpandConstant('{app}')), Lowercase(Target)) > 0;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  { The recorder has no window, so the Restart Manager cannot ask it to close:
    stop it before its file is replaced. [Run] starts it again. }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM taskman_recorder.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

function InitializeUninstall: Boolean;
begin
  Result := True;
  if CtrlShiftEscOpensThisCopy then
  begin
    Result := False;
    if not UninstallSilent then
      MsgBox('Ctrl+Shift+Esc still opens simple_taskman.' + #13#10#13#10 +
             'Uninstalling now would leave Ctrl+Shift+Esc opening nothing. Open simple_taskman, ' +
             'go to Settings, choose Restart as administrator, and turn off "Open simple_taskman ' +
             'on Ctrl+Shift+Esc". Then uninstall again.', mbError, MB_OK)
    else
      Log('Uninstall refused: Ctrl+Shift+Esc still opens this simple_taskman.');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RegDeleteValue(HKEY_CURRENT_USER, '{#RunKey}', '{#RecorderValue}');
    DataDir := ExpandConstant('{localappdata}\simple_taskman');
    { Only after an explicit Yes in a real dialog. UninstallSilent comes first:
      under /VERYSILENT /SUPPRESSMSGBOXES a MsgBox returns its default (IDYES)
      without showing anything, and would delete the history unasked. }
    if DirExists(DataDir) and (not UninstallSilent) then
      if MsgBox('Remove the recorded history and settings as well?' + #13#10#13#10 +
                'This deletes ' + DataDir + #13#10 +
                '(the trace of the last 30 days, settings, and logs).' + #13#10#13#10 +
                'Choose No to keep them for a future reinstall.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(DataDir, True, True, True);
  end;
end;
