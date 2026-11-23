import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../shared_storage.dart';
import 'os_account_service.dart';

/// Ubuntu / Debian accounts: useradd + chpasswd, admin = the sudo group.
///
/// Restrictions are polkit rules, the one mechanism that both the GNOME
/// panels and the command-line tools ask before changing the clock,
/// printers, packages or system settings. Written in both polkit formats,
/// since Ubuntu before 23.10 still reads only the old .pkla files.
/// Wallpaper, drives, tools and the allowed-apps list have no equivalent
/// that a user cannot undo from their own home folder, so they are not
/// offered here.
class LinuxOsAccounts extends OsAccountService {
  @override
  Set<OsRestriction> get supported => const {
        OsRestriction.settings,
        OsRestriction.printers,
        OsRestriction.time,
        OsRestriction.install,
      };

  @override
  bool get supportsAllowedApps => false;

  @override
  Future<bool> isElevated() async =>
      '${(await Process.run('id', ['-u'])).stdout}'.trim() == '0';

  @override
  Future<List<OsAccount>> listAccounts() async {
    final me = Platform.environment['USER'] ?? '';
    return parseLinuxAccounts(
      await File('/etc/passwd').readAsString(),
      await File('/etc/group').readAsString(),
      currentUser: me,
    );
  }

  @override
  Future<void> createAccount({
    required String name,
    required String fullName,
    required String password,
    required bool admin,
    required OsRestrictions restrictions,
  }) =>
      _run(_payload('create', name, admin, restrictions,
          fullName: fullName, password: password));

  @override
  Future<void> updateAccount({
    required String name,
    required bool admin,
    required OsRestrictions restrictions,
  }) =>
      _run(_payload('update', name, admin, restrictions));

  @override
  Future<void> setPassword(String name, String password) =>
      _run({'action': 'password', 'name': name, 'password': password});

  /// Creates /var/lib/caisse212 for every account's POS to share.
  Future<void> setupSharedFolder() => _run({
        'action': 'shared',
        'invoker': Platform.environment['USER'] ?? '',
        'shared': SharedStorage.linuxRoot,
      });

  Map<String, dynamic> _payload(
    String action,
    String name,
    bool admin,
    OsRestrictions r, {
    String? fullName,
    String? password,
  }) {
    final applied = admin ? OsRestrictions.none : r;
    return {
      'action': action,
      'name': name,
      if (fullName != null) 'fullName': fullName,
      if (password != null) 'password': password,
      'admin': admin,
      'invoker': Platform.environment['USER'] ?? '',
      'shared': SharedStorage.linuxRoot,
      'denied': linuxDeniedActions(applied),
      'printers': applied.printers,
      'record': OsAccountService.nextRecord(name, applied, admin: admin),
      'recordPath': OsAccountService.recordFile.path,
    };
  }

  Future<void> _run(Map<String, dynamic> payload) async {
    final dir = await Directory.systemTemp.createTemp('c212-acct-');
    try {
      final script = File(p.join(dir.path, 'accounts.py'));
      await script.writeAsString(kLinuxAccountsScript);
      await File(p.join(dir.path, 'payload.json'))
          .writeAsString(jsonEncode(payload));
      final run = await isElevated()
          ? await Process.run('python3', [script.path, dir.path])
          : await Process.run(
              'pkexec', ['/usr/bin/python3', script.path, dir.path]);
      // pkexec: 126 = dialog dismissed, 127 = not authorised.
      if (run.exitCode == 126 || run.exitCode == 127) {
        throw const OsAccountException('Administrator rights were refused',
            cancelled: true);
      }
      final resultFile = File(p.join(dir.path, 'result.json'));
      if (!resultFile.existsSync()) {
        throw OsAccountException('No answer: ${'${run.stderr}'.trim()}');
      }
      final res = jsonDecode(await resultFile.readAsString());
      if (res['ok'] != true) {
        throw OsAccountException('${res['error'] ?? 'unknown error'}');
      }
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// polkit action-id prefixes refused to a restricted account.
List<String> linuxDeniedActions(OsRestrictions r) => [
      if (r.time) 'org.freedesktop.timedate1.',
      if (r.printers) ...[
        'org.opensuse.cupspkhelper.mechanism.',
        'org.freedesktop.cups.',
      ],
      if (r.install) ...[
        'org.freedesktop.packagekit.',
        'io.snapcraft.snapd.',
        'org.freedesktop.Flatpak.',
        'com.ubuntu.softwareproperties.',
      ],
      if (r.settings) ...[
        'org.freedesktop.NetworkManager.settings.modify.',
        'org.freedesktop.accounts.',
        'org.freedesktop.hostname1.',
        'org.freedesktop.locale1.',
        'org.freedesktop.udisks2.',
        'org.gnome.controlcenter.',
      ],
    ];

/// Human accounts from /etc/passwd: uid 1000-59999 with a login shell.
List<OsAccount> parseLinuxAccounts(String passwd, String group,
    {required String currentUser}) {
  final sudoers = <String>{};
  for (final line in const LineSplitter().convert(group)) {
    final f = line.split(':');
    if (f.length >= 4 && (f[0] == 'sudo' || f[0] == 'admin' || f[0] == 'wheel')) {
      sudoers.addAll(f[3].split(',').where((s) => s.isNotEmpty));
    }
  }
  final out = <OsAccount>[];
  for (final line in const LineSplitter().convert(passwd)) {
    final f = line.split(':');
    if (f.length < 7) continue;
    final uid = int.tryParse(f[2]) ?? -1;
    if (uid < 1000 || uid >= 60000) continue;
    final shell = f[6];
    final locked = shell.endsWith('nologin') || shell.endsWith('/false');
    out.add(OsAccount(
      name: f[0],
      fullName: f[4].split(',').first,
      isAdmin: sudoers.contains(f[0]),
      enabled: !locked,
      isCurrent: f[0] == currentUser,
    ));
  }
  out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return out;
}

/// Runs as root: `python3 accounts.py <dir>`; reads payload.json, writes
/// result.json `{ok, error}`.
const String kLinuxAccountsScript = r'''
import grp, json, os, pwd, re, shutil, subprocess, sys

d = sys.argv[1]
res = {'ok': False}
GROUP = 'caisse212'
NAME_RE = re.compile(r'^[a-z_][a-z0-9_-]{0,31}$')

def run(*args, stdin=None, check=True):
    r = subprocess.run(list(args), input=stdin, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError('%s: %s' % (args[0], (r.stderr or r.stdout).strip() or r.returncode))
    return r

def members(group):
    try:
        return set(grp.getgrnam(group).gr_mem)
    except KeyError:
        return set()

def ensure_shared(path, users):
    run('groupadd', '-f', GROUP)
    os.makedirs(path, exist_ok=True)
    run('chgrp', '-R', GROUP, path)
    run('chmod', '2770', path)
    run('chmod', '-R', 'g+rwX', path)
    # SQLite creates its -wal/-shm files with the creator's umask; the
    # default ACL keeps them writable for the other accounts.
    if shutil.which('setfacl'):
        run('setfacl', '-R', '-m', 'g:%s:rwX' % GROUP, path)
        run('setfacl', '-R', '-d', '-m', 'g:%s:rwX' % GROUP, path)
    for u in users:
        if u and u != 'root':
            run('usermod', '-aG', GROUP, u)

def set_admin(name, admin, invoker):
    is_admin = name in members('sudo')
    if admin and not is_admin:
        run('usermod', '-aG', 'sudo,lpadmin', name)
    if not admin and is_admin:
        if name == invoker:
            raise RuntimeError('You cannot remove administrator rights from the account you are using.')
        if not (members('sudo') - {name}):
            raise RuntimeError('%s is the last administrator account.' % name)
        run('gpasswd', '-d', name, 'sudo')

def set_rules(name, denied, printers):
    js = '/etc/polkit-1/rules.d/60-caisse212-%s.rules' % name
    pkla_dir = '/etc/polkit-1/localauthority/50-local.d'
    pkla = os.path.join(pkla_dir, '60-caisse212-%s.pkla' % name)
    if printers:
        run('gpasswd', '-d', name, 'lpadmin', check=False)
    if not denied:
        for f in (js, pkla):
            if os.path.exists(f):
                os.remove(f)
        return
    # ES5 only: Ubuntu's polkit runs these on duktape.
    with open(js, 'w') as f:
        f.write('// caisse212 super admin mode: restrictions for %s\n' % name)
        f.write('polkit.addRule(function(action, subject) {\n')
        f.write('  if (subject.user !== %s) return;\n' % json.dumps(name))
        f.write('  var denied = %s;\n' % json.dumps(denied))
        f.write('  for (var i = 0; i < denied.length; i++) {\n')
        f.write('    if (action.id.indexOf(denied[i]) === 0) return polkit.Result.NO;\n')
        f.write('  }\n});\n')
    os.chmod(js, 0o644)
    if os.path.isdir(os.path.dirname(pkla_dir)):
        os.makedirs(pkla_dir, exist_ok=True)
        with open(pkla, 'w') as f:
            f.write('[caisse212 %s]\nIdentity=unix-user:%s\nAction=%s\n'
                    'ResultAny=no\nResultInactive=no\nResultActive=no\n'
                    % (name, name, ';'.join(x + '*' for x in denied)))

def save_record(p):
    os.makedirs(os.path.dirname(p['recordPath']), exist_ok=True)
    with open(p['recordPath'], 'w') as f:
        json.dump(p['record'], f)

try:
    path = os.path.join(d, 'payload.json')
    with open(path) as f:
        p = json.load(f)
    os.remove(path)
    action = p['action']
    name = p.get('name', '')
    if action != 'shared' and not NAME_RE.match(name):
        raise RuntimeError('Invalid account name')
    if action == 'shared':
        ensure_shared(p['shared'], [p.get('invoker')])
    elif action == 'create':
        ensure_shared(p['shared'], [p.get('invoker')])
        run('useradd', '-m', '-s', '/bin/bash', '-c', p.get('fullName', ''), '-G', GROUP, name)
        run('chpasswd', stdin='%s:%s\n' % (name, p['password']))
        set_admin(name, p['admin'], p.get('invoker'))
        set_rules(name, p['denied'], p['printers'])
        save_record(p)
    elif action == 'update':
        pwd.getpwnam(name)
        set_admin(name, p['admin'], p.get('invoker'))
        set_rules(name, p['denied'], p['printers'])
        save_record(p)
    elif action == 'password':
        pwd.getpwnam(name)
        run('chpasswd', stdin='%s:%s\n' % (name, p['password']))
    else:
        raise RuntimeError('Unknown action %s' % action)
    res['ok'] = True
except Exception as e:
    res['error'] = str(e)
with open(os.path.join(d, 'result.json'), 'w') as f:
    json.dump(res, f)
# The caller's POS reads the answer as itself, not root.
os.chmod(os.path.join(d, 'result.json'), 0o644)
''';
