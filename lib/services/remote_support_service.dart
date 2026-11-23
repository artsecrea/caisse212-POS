import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'os_accounts/os_account_service.dart' show OsAccountException;

/// Where the support tool connects. Empty fields fall back to the defaults
/// baked into the build (remoteaccess.caisse212.com). An empty relay follows
/// the host.
class RemoteSupportConfig {
  final String host;
  final String key;
  final String relay;
  final String api;
  const RemoteSupportConfig(
      {this.host = '', this.key = '', this.relay = '', this.api = ''});

  bool get isDefault =>
      host.trim().isEmpty &&
      key.trim().isEmpty &&
      relay.trim().isEmpty &&
      api.trim().isEmpty;

  Map<String, String> toJson() => {
        'host': host.trim(),
        'key': key.trim(),
        'relay': relay.trim(),
        'api': api.trim(),
      };

  factory RemoteSupportConfig.fromJson(Map<String, dynamic> j) =>
      RemoteSupportConfig(
        host: '${j['host'] ?? ''}',
        key: '${j['key'] ?? ''}',
        relay: '${j['relay'] ?? ''}',
        api: '${j['api'] ?? ''}',
      );
}

/// Launches the bundled remote-support tool (a rebranded RustDesk build,
/// shipped in its own `support` folder next to the POS and run as a separate
/// program — never linked into the POS).
///
/// Two names for one build: the client copy runs incoming-only (it shows an
/// ID and a one-time password for the technician), the tech copy may also
/// connect out. The build decides which from its own file name.
class RemoteSupportService {
  static const clientExe = 'caisse212-support.exe';
  static const techExe = 'caisse212-tech.exe';
  static const defaultHost = 'remoteaccess.caisse212.com';

  static Directory get folder => Directory(
      p.join(File(Platform.resolvedExecutable).parent.path, 'support'));

  static File _exe(String name) => File(p.join(folder.path, name));

  /// Read by the tool at start-up and forced over its own settings. Kept in
  /// the install folder (Program Files) so only an administrator can change
  /// it — a cashier cannot re-point the tool at someone else's server.
  static File get configFile => File(p.join(folder.path, 'server.json'));

  static bool get available =>
      Platform.isWindows && _exe(clientExe).existsSync();

  static bool get techAvailable =>
      Platform.isWindows && _exe(techExe).existsSync();

  /// Starts the tool detached, so closing or updating the POS never cuts a
  /// support session. False when it is not installed.
  static Future<bool> launch({bool tech = false}) async {
    final exe = _exe(tech ? techExe : clientExe);
    if (!Platform.isWindows || !exe.existsSync()) return false;
    await Process.start(exe.path, const [],
        workingDirectory: folder.path, mode: ProcessStartMode.detached);
    return true;
  }

  /// Installs the bundled tool as a service and sets a fresh permanent
  /// password — the same steps the POS installer runs, but on demand, so a
  /// till deployed before remote support existed can be brought in without a
  /// reinstall. One UAC prompt; meant to be triggered by the super admin, who
  /// has the rights (a cashier account usually does not).
  ///
  /// The password is generated and stored inside the elevated process; this
  /// process never sees it. After a success the POS pushes it to the back
  /// office on the next SSE connect (or call the reporter with force).
  /// Returns true once the service is present. A no-op true if already
  /// installed.
  static Future<bool> install() async {
    if (!Platform.isWindows) return false;
    if (installed) return true;
    if (!_exe(clientExe).existsSync()) return false; // nothing shipped
    final tmp = await Directory.systemTemp.createTemp('c212-support-install-');
    try {
      final script = File(p.join(tmp.path, 'setup_remote_access.ps1'))
        ..writeAsStringSync(_setupScript);
      String q(String s) => "'${s.replaceAll("'", "''")}'";
      final inner = '-NoProfile -ExecutionPolicy Bypass -File '
          '"${script.path}" -SupportDir "${folder.path}"';
      final run = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden '
            '-ArgumentList ${q(inner)}',
      ]);
      if (run.exitCode != 0) return false; // UAC refused / elevation failed
      // --silent-install returns before the service is fully up.
      for (var i = 0; i < 15 && !installed; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      return installed;
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// The installer's setup, run elevated by [install]. Kept byte-for-byte the
  /// same as `installer/setup_remote_access.ps1`; change both together.
  static const _setupScript = r'''
param([Parameter(Mandatory = $true)][string]$SupportDir)
$ErrorActionPreference = 'Stop'
$log = Join-Path $env:ProgramData 'caisse212\remote_access_setup.log'
function Note([string]$m) {
    try { Add-Content -LiteralPath $log -Value ("[{0:s}] {1}" -f (Get-Date), $m) } catch {}
}
try {
    $portable = Join-Path $SupportDir 'caisse212-support.exe'
    if (-not (Test-Path -LiteralPath $portable)) { Note 'no support tool shipped, skipped'; exit 0 }
    $installed = Join-Path $env:ProgramFiles 'Caisse212-Support\Caisse212-Support.exe'
    Start-Process -FilePath $portable -ArgumentList '--silent-install' -Wait -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Path -LiteralPath $installed) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
    if (-not (Test-Path -LiteralPath $installed)) { Note 'install did not complete'; exit 0 }
    $cfg = Join-Path $SupportDir 'server.json'
    if (Test-Path -LiteralPath $cfg) {
        Copy-Item -LiteralPath $cfg -Destination (Split-Path $installed) -Force
    }
    Start-Sleep -Seconds 5
    $bytes = New-Object byte[] 18
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $pw = [Convert]::ToBase64String($bytes).Replace('+', 'A').Replace('/', 'b').Replace('=', '')
    $ok = $false
    for ($i = 0; $i -lt 10 -and -not $ok; $i++) {
        $out = (& $installed --password $pw 2>&1 | Out-String)
        if ($out -match 'Done') { $ok = $true } else { Start-Sleep -Seconds 3 }
    }
    if (-not $ok) { Note 'permanent password was not accepted'; exit 0 }
    Add-Type -AssemblyName System.Security
    $enc = [Security.Cryptography.ProtectedData]::Protect(
        [Text.Encoding]::UTF8.GetBytes($pw), $null,
        [Security.Cryptography.DataProtectionScope]::LocalMachine)
    $dir = Join-Path $env:ProgramData 'caisse212'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $dir 'remote_access.pending'), $enc)
    $pw = $null
    Note 'service installed, password set and handed to the POS'
} catch {
    Note ("failed: " + $_.Exception.Message)
}
exit 0
''';

  // ── Unattended access (service installed by the POS installer) ──────────

  /// Where `--silent-install` puts the tool. Its service carries the ID and
  /// the permanent password; the portable copy above only serves a technician
  /// on the phone with someone at the till.
  static File get installedExe => File(p.join(
      Platform.environment['ProgramFiles'] ?? r'C:\Program Files',
      'Caisse212-Support',
      'Caisse212-Support.exe'));

  static const serviceName = 'Caisse212-Support';

  /// The installer's one-time hand-over of the permanent password, DPAPI
  /// (LocalMachine) protected. Deleted once the back office has it.
  static File get pendingPasswordFile => File(p.join(
      Platform.environment['ProgramData'] ?? r'C:\ProgramData',
      'caisse212',
      'remote_access.pending'));

  static bool get installed => Platform.isWindows && installedExe.existsSync();

  /// The RustDesk ID, or null when the tool is not installed or not up yet.
  static Future<String?> readId() async {
    final exe = installed ? installedExe : _exe(clientExe);
    if (!Platform.isWindows || !exe.existsSync()) return null;
    try {
      final r = await Process.run(exe.path, const ['--get-id'])
          .timeout(const Duration(seconds: 15));
      final id = '${r.stdout}'.trim().split(RegExp(r'\s+')).last;
      return RegExp(r'^\d{6,12}$').hasMatch(id) ? id : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> serviceRunning() async {
    if (!Platform.isWindows) return false;
    try {
      final r = await Process.run('sc.exe', ['query', serviceName])
          .timeout(const Duration(seconds: 10));
      return '${r.stdout}'.contains('RUNNING');
    } catch (_) {
      return false;
    }
  }

  static Future<String?> version() async {
    final exe = installed ? installedExe : _exe(clientExe);
    if (!Platform.isWindows || !exe.existsSync()) return null;
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "(Get-Item -LiteralPath '${exe.path.replaceAll("'", "''")}').VersionInfo.ProductVersion",
      ]).timeout(const Duration(seconds: 15));
      final v = '${r.stdout}'.trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// Starts the service when it is installed but stopped. Without admin
  /// rights `sc start` is refused; the service is set to start on its own, so
  /// that only matters after someone stopped it by hand.
  static Future<void> ensureServiceStarted() async {
    if (!installed || await serviceRunning()) return;
    try {
      await Process.run('sc.exe', ['start', serviceName])
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Decrypts the installer's hand-over, or null when there is none.
  static Future<String?> readPendingPassword() async {
    final f = pendingPasswordFile;
    if (!Platform.isWindows || !f.existsSync()) return null;
    try {
      final path = f.path.replaceAll("'", "''");
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Add-Type -AssemblyName System.Security; '
            "\$b = [IO.File]::ReadAllBytes('$path'); "
            '[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect('
            "\$b, \$null, [Security.Cryptography.DataProtectionScope]::LocalMachine))",
      ]).timeout(const Duration(seconds: 15));
      final pw = '${r.stdout}'.trim();
      return pw.isEmpty ? null : pw;
    } catch (_) {
      return null;
    }
  }

  static void dropPendingPassword() {
    try {
      pendingPasswordFile.deleteSync();
    } catch (_) {}
  }

  static RemoteSupportConfig readConfig() {
    try {
      final f = configFile;
      if (!f.existsSync()) return const RemoteSupportConfig();
      final j = jsonDecode(f.readAsStringSync().replaceFirst('﻿', ''));
      return j is Map
          ? RemoteSupportConfig.fromJson(Map<String, dynamic>.from(j))
          : const RemoteSupportConfig();
    } catch (_) {
      return const RemoteSupportConfig();
    }
  }

  /// Writes (or, for the defaults, removes) [configFile], and the installed
  /// service's copy when there is one; asks for UAC when the install folder is
  /// protected. The tool picks it up at its next start.
  static Future<void> saveConfig(RemoteSupportConfig c) async {
    final target = configFile;
    final serviceCopy = installed
        ? File(p.join(installedExe.parent.path, 'server.json'))
        : null;
    try {
      for (final f in [target, if (serviceCopy != null) serviceCopy]) {
        if (c.isDefault) {
          if (f.existsSync()) f.deleteSync();
        } else {
          f.writeAsStringSync(jsonEncode(c.toJson()));
        }
      }
      return;
    } on FileSystemException {
      // Program Files: fall through to an elevated copy.
    }
    final tmp = await Directory.systemTemp.createTemp('c212-support-');
    try {
      final src = File(p.join(tmp.path, 'server.json'));
      String q(String s) => "'${s.replaceAll("'", "''")}'";
      final targets = [target.path, if (serviceCopy != null) serviceCopy.path];
      final String command;
      if (c.isDefault) {
        command = targets
            .map((t) => 'Remove-Item -LiteralPath ${q(t)} -Force -ErrorAction SilentlyContinue')
            .join('; ');
      } else {
        src.writeAsStringSync(jsonEncode(c.toJson()));
        command = targets
            .map((t) => 'Copy-Item -LiteralPath ${q(src.path)} -Destination ${q(t)} -Force')
            .join('; ');
      }
      final run = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden '
            '-ArgumentList ${q('-NoProfile -Command "$command"')}',
      ]);
      if (run.exitCode != 0) {
        throw const OsAccountException('Administrator rights were refused',
            cancelled: true);
      }
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }
}
