import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'os_account_service.dart';

/// Local Windows accounts, through PowerShell's LocalAccounts module.
///
/// Restrictions are the per-user policy values Windows 10/11 Pro honours
/// (no AppLocker on Pro), written into the account's own registry hive. A
/// brand-new account has no hive until its first sign-in, so the script
/// creates the profile first. They take full effect at the account's next
/// sign-in.
class WindowsOsAccounts extends OsAccountService {
  bool? _elevated;

  @override
  Set<OsRestriction> get supported => OsRestriction.values.toSet();

  @override
  bool get supportsAllowedApps => true;

  @override
  Future<bool> isElevated() async {
    // `net session` needs an elevated token and nothing else.
    return _elevated ??= (await Process.run('net', ['session'])).exitCode == 0;
  }

  @override
  Future<List<OsAccount>> listAccounts() async {
    final data = await _run({'action': 'list'}, elevate: false);
    final list = data is List ? data : (data == null ? const [] : [data]);
    return [
      for (final a in list.cast<Map>())
        OsAccount(
          name: '${a['name']}',
          fullName: '${a['fullName'] ?? ''}',
          isAdmin: a['admin'] == true,
          enabled: a['enabled'] == true,
          isCurrent: a['current'] == true,
        ),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  @override
  Future<void> createAccount({
    required String name,
    required String fullName,
    required String password,
    required bool admin,
    required OsRestrictions restrictions,
  }) =>
      _run(_changePayload('create', name, admin, restrictions,
          fullName: fullName, password: password));

  @override
  Future<void> updateAccount({
    required String name,
    required bool admin,
    required OsRestrictions restrictions,
  }) =>
      _run(_changePayload('update', name, admin, restrictions));

  @override
  Future<void> setPassword(String name, String password) =>
      _run({'action': 'password', 'name': name, 'password': password});

  Map<String, dynamic> _changePayload(
    String action,
    String name,
    bool admin,
    OsRestrictions r, {
    String? fullName,
    String? password,
  }) {
    // An admin can lift any policy on itself, so restricting one is theatre.
    final applied = admin ? OsRestrictions.none : r;
    final record = OsAccountService.nextRecord(name, applied, admin: admin);
    return windowsChangePayload(
      action: action,
      name: name,
      admin: admin,
      restrictions: applied,
      posApps: posApps,
      record: record,
      recordPath: OsAccountService.recordFile.path,
      invoker: Platform.environment['USERNAME'] ?? '',
      fullName: fullName,
      password: password,
    );
  }

  Future<dynamic> _run(Map<String, dynamic> payload,
      {bool elevate = true}) async {
    final dir = await Directory.systemTemp.createTemp('c212-acct-');
    try {
      final script = File(p.join(dir.path, 'accounts.ps1'));
      await script.writeAsString(kWindowsAccountsScript);
      // The password travels in this file, never on a command line where
      // any process listing would show it. The script deletes it on read.
      await File(p.join(dir.path, 'payload.json'))
          .writeAsString(jsonEncode(payload));

      final args = ['-NoProfile', '-ExecutionPolicy', 'Bypass'];
      final ProcessResult run;
      if (!elevate || await isElevated()) {
        run = await Process.run('powershell',
            [...args, '-File', script.path, '-Dir', dir.path]);
      } else {
        String q(String s) => "'${s.replaceAll("'", "''")}'";
        final inner = [...args, '-File', '"${script.path}"', '-Dir', '"${dir.path}"']
            .map(q)
            .join(',');
        run = await Process.run('powershell', [
          ...args,
          '-Command',
          'Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden '
              '-ArgumentList $inner',
        ]);
        if (run.exitCode != 0) {
          throw const OsAccountException('Administrator rights were refused',
              cancelled: true);
        }
      }

      final resultFile = File(p.join(dir.path, 'result.json'));
      if (!resultFile.existsSync()) {
        throw OsAccountException(
            'PowerShell gave no answer: ${'${run.stderr}'.trim()}');
      }
      final res = jsonDecode(
          (await resultFile.readAsString()).replaceFirst('﻿', ''));
      if (res['ok'] != true) {
        throw OsAccountException('${res['error'] ?? 'unknown error'}');
      }
      return res['data'];
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// The request the PowerShell script receives for a create / update.
/// Pure so the mapping from the screen to the script stays testable.
Map<String, dynamic> windowsChangePayload({
  required String action,
  required String name,
  required bool admin,
  required OsRestrictions restrictions,
  required List<String> posApps,
  required Map<String, dynamic> record,
  required String recordPath,
  required String invoker,
  String? fullName,
  String? password,
}) {
  final r = restrictions;
  return {
    'action': action,
    'name': name,
    if (fullName != null) 'fullName': fullName,
    if (password != null) 'password': password,
    'admin': admin,
    'invoker': invoker,
    'restrictions': {
      ...r.toJson(),
      'allowedApps':
          r.onlyAllowedApps ? r.effectiveAllowedApps(posApps) : <String>[],
    },
    'record': record,
    'recordPath': recordPath,
    // Time zone is a machine-wide right, not a per-user policy: it is taken
    // from standard users while any account on file asks for it.
    'anyTimeBlock': record.values.any((v) => v is Map && v['time'] == true),
  };
}

/// Runs as `powershell -File accounts.ps1 -Dir <dir>`; reads payload.json,
/// writes result.json `{ok, error, data}`.
const String kWindowsAccountsScript = r'''
param([Parameter(Mandatory = $true)][string]$Dir)
$ErrorActionPreference = 'Stop'
$result = @{ ok = $false }

function Get-AdminNames {
  $g = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
  $names = @()
  foreach ($m in ([ADSI]"WinNT://./$g,group").psbase.Invoke('Members')) {
    $names += $m.GetType().InvokeMember('Name', 'GetProperty', $null, $m, $null)
  }
  , $names
}

function Get-Accounts {
  $admins = Get-AdminNames
  $me = $env:USERNAME
  $out = @()
  foreach ($u in Get-LocalUser) {
    $rid = $u.SID.Value.Split('-')[-1]
    # Guest, DefaultAccount, WDAGUtilityAccount; the built-in Administrator
    # only when someone switched it on.
    if (@('501', '503', '504') -contains $rid) { continue }
    if ($rid -eq '500' -and -not $u.Enabled) { continue }
    $out += @{
      name = $u.Name; fullName = [string]$u.FullName; enabled = [bool]$u.Enabled
      admin = ($admins -contains $u.Name); current = ($u.Name -eq $me)
    }
  }
  , $out
}

function ConvertTo-Secure([string]$s) { ConvertTo-SecureString -String $s -AsPlainText -Force }

function Ensure-Key([string]$path) {
  # Never New-Item -Force on an existing key: for the registry it wipes it.
  if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
}

function Set-Flag([string]$path, [string]$name, $on, [int]$value = 1) {
  if ($on) {
    Ensure-Key $path
    New-ItemProperty -LiteralPath $path -Name $name -PropertyType DWord -Value $value -Force | Out-Null
  } elseif (Test-Path -LiteralPath $path) {
    Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
  }
}

function Set-List([string]$path, [string]$name, $items) {
  $items = @($items | Where-Object { $_ })
  $sub = "$path\$name"
  if (Test-Path -LiteralPath $sub) { Remove-Item -LiteralPath $sub -Recurse -Force }
  if ($items.Count -gt 0) {
    Ensure-Key $sub
    $i = 1
    foreach ($x in $items) {
      New-ItemProperty -LiteralPath $sub -Name "$i" -PropertyType String -Value $x -Force | Out-Null
      $i++
    }
  }
  Set-Flag $path $name ($items.Count -gt 0)
}

function New-UserProfile([string]$name, [string]$sid) {
  if (-not ('C212Profile' -as [type])) {
    Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class C212Profile {
  [DllImport("userenv.dll", CharSet = CharSet.Unicode)]
  public static extern int CreateProfile(string sid, string name, StringBuilder path, uint len);
}
"@
  }
  $sb = New-Object Text.StringBuilder 260
  $hr = [C212Profile]::CreateProfile($sid, $name, $sb, 260)
  # 0x800700B7: the profile already exists.
  if ($hr -ne 0 -and $hr -ne -2147024713) { throw ("Could not create the profile of $name (0x{0:X8})" -f $hr) }
}

function Mount-UserHive([string]$name, [string]$sid) {
  if (Test-Path -LiteralPath "Registry::HKEY_USERS\$sid") { return @{ key = $sid; loaded = $false } }
  $profKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
  if (-not (Test-Path -LiteralPath $profKey)) { New-UserProfile $name $sid }
  $profile = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty -LiteralPath $profKey).ProfileImagePath)
  $key = "c212_$sid"
  & reg.exe load "HKU\$key" (Join-Path $profile 'NTUSER.DAT') | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Could not open the settings of $name (is it signed in elsewhere?)" }
  @{ key = $key; loaded = $true }
}

function Dismount-UserHive($h) {
  if (-not $h.loaded) { return }
  for ($i = 0; $i -lt 5; $i++) {
    [gc]::Collect(); [gc]::WaitForPendingFinalizers()
    & reg.exe unload "HKU\$($h.key)" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return }
    Start-Sleep -Milliseconds 400
  }
}

function Set-Restrictions($p) {
  $r = $p.restrictions
  $sid = (Get-LocalUser -Name $p.name).SID.Value
  $h = Mount-UserHive $p.name $sid
  try {
    $base = "Registry::HKEY_USERS\$($h.key)"
    $pol = "$base\Software\Microsoft\Windows\CurrentVersion\Policies"
    # Settings app and Control Panel, which also covers the date, printer
    # and network pages.
    Set-Flag "$pol\Explorer" 'NoControlPanel' $r.settings
    Set-Flag "$pol\ActiveDesktop" 'NoChangingWallPaper' $r.personalization
    Set-Flag "$pol\Explorer" 'NoAddPrinter' $r.printers
    Set-Flag "$pol\Explorer" 'NoDeletePrinter' $r.printers
    Set-Flag "$pol\System" 'DisableTaskMgr' $r.tools
    Set-Flag "$pol\System" 'DisableRegistryTools' $r.tools
    Set-Flag "$pol\Explorer" 'NoRun' $r.tools
    # 2 = no interactive prompt, but batch files still run: the POS updater
    # is one.
    Set-Flag "$base\Software\Policies\Microsoft\Windows\System" 'DisableCMD' $r.tools 2
    Set-Flag "$base\Software\Policies\Microsoft\WindowsStore" 'RemoveWindowsStore' $r.install
    # All 26 drive letters hidden from Explorer and blocked from browsing.
    Set-Flag "$pol\Explorer" 'NoDrives' $r.drives 0x03FFFFFF
    Set-Flag "$pol\Explorer" 'NoViewOnDrive' $r.drives 0x03FFFFFF
    $deny = @()
    if ($r.install) { $deny += 'WinStore.App.exe', 'msiexec.exe', 'winget.exe', 'AppInstaller.exe' }
    if ($r.tools) { $deny += 'cmd.exe', 'powershell.exe', 'powershell_ise.exe', 'pwsh.exe', 'regedit.exe', 'mmc.exe', 'taskmgr.exe' }
    Set-List "$pol\Explorer" 'DisallowRun' $deny
    Set-List "$pol\Explorer" 'RestrictRun' @($r.allowedApps)
  } finally {
    Dismount-UserHive $h
  }
}

function Set-Admin([string]$name, [bool]$admin, [string]$invoker) {
  $admins = Get-AdminNames
  $isAdmin = $admins -contains $name
  if ($admin -and -not $isAdmin) { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $name }
  if (-not $admin -and $isAdmin) {
    if ($name -eq $invoker) { throw 'You cannot remove administrator rights from the account you are using.' }
    $others = @(Get-LocalUser | Where-Object { $_.Enabled -and $_.Name -ne $name -and ($admins -contains $_.Name) })
    if ($others.Count -eq 0) { throw "$name is the last administrator account." }
    Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member $name
  }
}

function Set-TimeZoneRight([bool]$block) {
  # LOCAL SERVICE and Administrators always; Users only while no restricted
  # account asks for the time to be locked.
  $holders = if ($block) { '*S-1-5-19,*S-1-5-32-544' } else { '*S-1-5-19,*S-1-5-32-544,*S-1-5-32-545' }
  $inf = Join-Path $Dir 'tz.inf'
  @('[Unicode]', 'Unicode=yes', '[Version]', 'signature="$CHICAGO$"', 'Revision=1',
    '[Privilege Rights]', "SeTimeZonePrivilege = $holders") | Set-Content -LiteralPath $inf -Encoding Unicode
  & secedit.exe /configure /db (Join-Path $Dir 'tz.sdb') /cfg $inf /areas USER_RIGHTS /quiet | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "secedit failed ($LASTEXITCODE)" }
}

function Save-Record($p) {
  $folder = Split-Path -Parent $p.recordPath
  if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
  $json = $p.record | ConvertTo-Json -Depth 6 -Compress
  [IO.File]::WriteAllText($p.recordPath, $json, (New-Object Text.UTF8Encoding $false))
}

try {
  $payloadPath = Join-Path $Dir 'payload.json'
  $p = [IO.File]::ReadAllText($payloadPath) | ConvertFrom-Json
  Remove-Item -LiteralPath $payloadPath -Force
  switch ($p.action) {
    'list' { $result.data = Get-Accounts }
    'create' {
      New-LocalUser -Name $p.name -Password (ConvertTo-Secure $p.password) -FullName ([string]$p.fullName) `
        -Description 'caisse212' -PasswordNeverExpires -AccountNeverExpires | Out-Null
      # New-LocalUser leaves the account out of Users: no sign-in tile.
      Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $p.name
      Set-Admin $p.name ([bool]$p.admin) $p.invoker
      Set-Restrictions $p
      Set-TimeZoneRight ([bool]$p.anyTimeBlock)
      Save-Record $p
    }
    'update' {
      Set-Admin $p.name ([bool]$p.admin) $p.invoker
      Set-Restrictions $p
      Set-TimeZoneRight ([bool]$p.anyTimeBlock)
      Save-Record $p
    }
    'password' { Set-LocalUser -Name $p.name -Password (ConvertTo-Secure $p.password) }
    default { throw "Unknown action $($p.action)" }
  }
  $result.ok = $true
} catch {
  $result.error = $_.Exception.Message
}
[IO.File]::WriteAllText((Join-Path $Dir 'result.json'), ($result | ConvertTo-Json -Depth 6 -Compress), (New-Object Text.UTF8Encoding $false))
''';
