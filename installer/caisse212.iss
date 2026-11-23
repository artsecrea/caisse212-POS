; Inno Setup script for the CAISSE212 Windows installer.
;
; Normally compiled by build_windows.ps1, which passes the defines below:
;   ISCC.exe /DAppVersion=1.2.0 /DAppBuild=8 /DSourceDir=<staged bundle> /DOutputDir=<out> caisse212.iss
;
; Running the installer over an existing install upgrades it in place: the
; running POS is closed, files are replaced, and the POS is started again.
; The database and settings live in C:\ProgramData\caisse212, shared by every
; Windows account on the till, and neither an upgrade nor an uninstall touches
; them.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppBuild
  #define AppBuild "0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\release\bundle"
#endif
#ifndef OutputDir
  #define OutputDir "..\build\release"
#endif
; The VC++ 2015-2022 x64 redistributable shipped inside the setup, and its
; version: it is only run when the PC has an older runtime (or none).
#ifndef VcRedist
  #define VcRedist "..\build\redist\vc_redist.x64.exe"
#endif
#ifndef VcMajor
  #define VcMajor "14"
#endif
#ifndef VcMinor
  #define VcMinor "44"
#endif
#ifndef VcBld
  #define VcBld "35211"
#endif

#define AppName "CAISSE212"
#define AppExe "caisse212.exe"
; Pre-rename builds shipped this exe; it is closed and removed on upgrade.
#define LegacyExe "posecrea.exe"
#define AppPublisher "artecrea"

[Setup]
; Never change AppId: it is how Windows recognises an upgrade of the same app.
AppId={{DD01BD8F-1902-449C-9FEA-D39C9043165B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}.{#AppBuild}
VersionInfoProductName={#AppName}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; All users: the restricted cashier accounts made in super admin mode must be
; able to run the same POS. The in-app updater asks for UAC to write here.
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=caisse212-setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
WizardImageFile=wizard_100.bmp,wizard_250.bmp
WizardSmallImageFile=wizard_small_100.bmp,wizard_small_250.bmp
Compression=lzma2/ultra64
SolidCompression=yes
CloseApplications=force
RestartApplications=no

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ar"; MessagesFile: "compiler:Languages\Arabic.isl"

[CustomMessages]
fr.StartupGroup=Démarrage :
fr.StartWithWindows=Lancer {#AppName} au démarrage de Windows
fr.InstallingVcRedist=Installation de Microsoft Visual C++ Redistributable...
fr.VcRedistFailed=L'installation de Microsoft Visual C++ Redistributable a échoué (code %1). {#AppName} risque de ne pas démarrer : installez vc_redist.x64.exe manuellement.
en.StartupGroup=Startup:
en.StartWithWindows=Start {#AppName} when Windows starts
en.InstallingVcRedist=Installing Microsoft Visual C++ Redistributable...
en.VcRedistFailed=Installing Microsoft Visual C++ Redistributable failed (code %1). {#AppName} may not start: install vc_redist.x64.exe manually.
ar.StartupGroup=بدء التشغيل:
ar.StartWithWindows=تشغيل {#AppName} عند بدء تشغيل Windows
ar.InstallingVcRedist=جارٍ تثبيت Microsoft Visual C++ Redistributable...
ar.VcRedistFailed=فشل تثبيت Microsoft Visual C++ Redistributable (الرمز %1). قد لا يعمل {#AppName}: قم بتثبيت vc_redist.x64.exe يدويًا.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "{cm:StartWithWindows}"; GroupDescription: "{cm:StartupGroup}"

[InstallDelete]
Type: files; Name: "{app}\{#LegacyExe}"

[Dirs]
; Every account must write the shared database, not just the one that made it.
Name: "{commonappdata}\caisse212"; Permissions: users-modify; Flags: uninsneveruninstall

[Files]
Source: "{#VcRedist}"; Flags: dontcopy
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.db,*.db-wal,*.db-shm,logs.txt,error_log.txt"
Source: "setup_remote_access.ps1"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Registry]
; HKA = this user for a per-user install, every user for an all-users install.
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExe}"""; Flags: uninsdeletevalue; Tasks: startup

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Unattended remote support: service + a fresh permanent password, handed to
; the POS once (see setup_remote_access.ps1). Runs elevated, before the POS.
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\setup_remote_access.ps1"" -SupportDir ""{app}\support"""; Flags: runhidden waituntilterminated; Check: FileExists(ExpandConstant('{app}\support\caisse212-support.exe')); StatusMsg: "Remote support..."
; No skipifsilent: a silent upgrade (/VERYSILENT) must bring the POS back up too.
; runasoriginaluser: the POS must not inherit the setup's admin token.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall runasoriginaluser

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe}"; Flags: runhidden; RunOnceId: "KillApp"
Filename: "{commonpf}\Caisse212-Support\Caisse212-Support.exe"; Parameters: "--uninstall"; Flags: runhidden skipifdoesntexist; RunOnceId: "RemoveSupport"

[Code]
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  VcKey = 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';

var
  VcNeedsRestart: Boolean;

function VcRuntimeIsCurrent(RootKey: Integer): Boolean;
var
  Installed, Major, Minor, Bld: Cardinal;
begin
  Result := False;
  if not RegQueryDWordValue(RootKey, VcKey, 'Installed', Installed) or (Installed <> 1) then Exit;
  if not RegQueryDWordValue(RootKey, VcKey, 'Major', Major) then Exit;
  if not RegQueryDWordValue(RootKey, VcKey, 'Minor', Minor) then Exit;
  if not RegQueryDWordValue(RootKey, VcKey, 'Bld', Bld) then Exit;
  // The app needs a runtime at least as new as the toolset it was built with.
  if Major <> {#VcMajor} then Result := Major > {#VcMajor}
  else if Minor <> {#VcMinor} then Result := Minor > {#VcMinor}
  else Result := Bld >= {#VcBld};
end;

procedure InstallVcRedist;
var
  ResultCode: Integer;
begin
  if VcRuntimeIsCurrent(HKLM64) or VcRuntimeIsCurrent(HKLM32) then Exit;

  WizardForm.StatusLabel.Caption := CustomMessage('InstallingVcRedist');
  ExtractTemporaryFile('vc_redist.x64.exe');
  // ShellExec, not Exec: the redist installs machine-wide and asks for UAC
  // itself when this setup runs per-user.
  if not ShellExec('', ExpandConstant('{tmp}\vc_redist.x64.exe'), '/install /quiet /norestart', '',
                   SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    ResultCode := -1;
  // 1638: a newer runtime is already there. 3010: installed, reboot pending.
  if ResultCode = 3010 then
    VcNeedsRestart := True
  else if (ResultCode <> 0) and (ResultCode <> 1638) then
    SuppressibleMsgBox(FmtMessage(CustomMessage('VcRedistFailed'), [IntToStr(ResultCode)]), mbError, MB_OK, IDOK);
end;

// Older builds installed per-user under AppData. That copy would keep its
// own autostart entry and could win the race at boot with a stale version,
// so it goes once the all-users copy is in place. Data never lived in it.
procedure RemovePerUserInstall;
var
  Uninst: String;
  ResultCode: Integer;
begin
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{DD01BD8F-1902-449C-9FEA-D39C9043165B}_is1',
                         'UninstallString', Uninst) then
    Exec(RemoveQuotes(Uninst), '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    InstallVcRedist
  else if CurStep = ssPostInstall then
  begin
    RemovePerUserInstall;
    // [Registry] only ever adds the value, so unticking the task on a
    // reinstall has to remove it here.
    if not WizardIsTaskSelected('startup') then
      RegDeleteValue(HKA, RunKey, '{#AppName}');
  end;
end;

function NeedRestart(): Boolean;
begin
  // Never on a silent run: /VERYSILENT would reboot the till without asking.
  Result := VcNeedsRestart and not WizardSilent;
end;

procedure KillApp(const ExeName: String);
var
  ResultCode: Integer;
begin
  // Polite close first so the app can flush; force it if it is still there.
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM ' + ExeName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1500);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM ' + ExeName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  KillApp('{#AppExe}');
  KillApp('{#LegacyExe}');
  // Give Windows a moment to release the exe/dll handles before copying.
  Sleep(1000);
  Result := '';
end;
