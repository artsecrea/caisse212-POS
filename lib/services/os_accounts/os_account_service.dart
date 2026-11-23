import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../shared_storage.dart';
import 'linux_os_accounts.dart';
import 'windows_os_accounts.dart';

/// What a restricted OS account may not touch. Every flag means "blocked".
class OsRestrictions {
  final bool settings;
  final bool personalization;
  final bool printers;
  final bool time;
  final bool install;
  final bool tools;
  final bool drives;

  /// When set, the account may only start [allowedApps] (exe file names).
  final bool onlyAllowedApps;
  final List<String> allowedApps;

  const OsRestrictions({
    this.settings = false,
    this.personalization = false,
    this.printers = false,
    this.time = false,
    this.install = false,
    this.tools = false,
    this.drives = false,
    this.onlyAllowedApps = false,
    this.allowedApps = const [],
  });

  /// Everything locked down, the POS the only app: what a till cashier gets
  /// unless the owner unticks something.
  factory OsRestrictions.lockedDown(List<String> posApps) => OsRestrictions(
        settings: true,
        personalization: true,
        printers: true,
        time: true,
        install: true,
        tools: true,
        drives: true,
        onlyAllowedApps: true,
        allowedApps: posApps,
      );

  static const none = OsRestrictions();

  int get count =>
      [settings, personalization, printers, time, install, tools, drives,
              onlyAllowedApps]
          .where((b) => b)
          .length;

  OsRestrictions copyWith({
    bool? settings,
    bool? personalization,
    bool? printers,
    bool? time,
    bool? install,
    bool? tools,
    bool? drives,
    bool? onlyAllowedApps,
    List<String>? allowedApps,
  }) =>
      OsRestrictions(
        settings: settings ?? this.settings,
        personalization: personalization ?? this.personalization,
        printers: printers ?? this.printers,
        time: time ?? this.time,
        install: install ?? this.install,
        tools: tools ?? this.tools,
        drives: drives ?? this.drives,
        onlyAllowedApps: onlyAllowedApps ?? this.onlyAllowedApps,
        allowedApps: allowedApps ?? this.allowedApps,
      );

  Map<String, dynamic> toJson() => {
        'settings': settings,
        'personalization': personalization,
        'printers': printers,
        'time': time,
        'install': install,
        'tools': tools,
        'drives': drives,
        'onlyAllowedApps': onlyAllowedApps,
        'allowedApps': allowedApps,
      };

  factory OsRestrictions.fromJson(Map<String, dynamic> j) => OsRestrictions(
        settings: j['settings'] == true,
        personalization: j['personalization'] == true,
        printers: j['printers'] == true,
        time: j['time'] == true,
        install: j['install'] == true,
        tools: j['tools'] == true,
        drives: j['drives'] == true,
        onlyAllowedApps: j['onlyAllowedApps'] == true,
        allowedApps: [
          for (final a in (j['allowedApps'] as List? ?? const [])) '$a'
        ],
      );

  /// What the OS enforces when [onlyAllowedApps] is on: the owner's list plus
  /// the POS itself, which must never be locked out of its own till.
  List<String> effectiveAllowedApps(List<String> posApps) {
    final seen = <String>{};
    return [
      for (final a in [...posApps, ...allowedApps])
        if (a.trim().isNotEmpty && seen.add(a.trim().toLowerCase())) a.trim(),
    ];
  }
}

/// The restriction kinds, in display order.
enum OsRestriction {
  settings,
  personalization,
  printers,
  time,
  install,
  tools,
  drives,
}

class OsAccount {
  final String name;
  final String fullName;
  final bool isAdmin;
  final bool enabled;

  /// The account this POS is running under.
  final bool isCurrent;

  const OsAccount({
    required this.name,
    required this.fullName,
    required this.isAdmin,
    required this.enabled,
    required this.isCurrent,
  });

  String get label => fullName.trim().isEmpty ? name : fullName;
}

/// An OS-side failure, already worded for the operator.
class OsAccountException implements Exception {
  final String message;

  /// The operator declined the UAC / polkit prompt.
  final bool cancelled;
  const OsAccountException(this.message, {this.cancelled = false});
  @override
  String toString() => message;
}

/// Creates and locks down the machine's own sign-in accounts (Windows or
/// Linux), as opposed to the POS users that come from the back office.
abstract class OsAccountService {
  static OsAccountService? forPlatform() {
    if (Platform.isWindows) return WindowsOsAccounts();
    if (Platform.isLinux) return LinuxOsAccounts();
    return null;
  }

  /// Which [OsRestriction]s this OS can enforce.
  Set<OsRestriction> get supported;

  /// Whether the allowed-apps list can be enforced here.
  bool get supportsAllowedApps;

  /// Whether this process already has admin rights; when false every change
  /// asks the OS for them (UAC / polkit).
  Future<bool> isElevated();

  Future<List<OsAccount>> listAccounts();

  Future<void> createAccount({
    required String name,
    required String fullName,
    required String password,
    required bool admin,
    required OsRestrictions restrictions,
  });

  Future<void> updateAccount({
    required String name,
    required bool admin,
    required OsRestrictions restrictions,
  });

  Future<void> setPassword(String name, String password);

  /// The exe names that make up the POS, always allowed to run.
  List<String> get posApps {
    final exe = p.basename(Platform.resolvedExecutable);
    return {exe, if (Platform.isWindows) 'caisse212.exe'}.toList();
  }

  /// Last restrictions applied from this screen, per account. Kept next to
  /// the shared data so every account's POS shows the same thing. It records
  /// what was applied; the OS is what enforces it.
  static File get recordFile =>
      File(p.join(SharedStorage.root ?? Directory.systemTemp.path,
          'os_accounts.json'));

  static Map<String, OsRestrictions> readRecord() {
    try {
      final f = recordFile;
      if (!f.existsSync()) return {};
      final raw = f.readAsStringSync().replaceFirst('﻿', '');
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      return {
        for (final e in j.entries)
          if (e.value is Map)
            '${e.key}'.toLowerCase():
                OsRestrictions.fromJson(Map<String, dynamic>.from(e.value)),
      };
    } catch (_) {
      return {};
    }
  }

  /// [record] with [name] set to [r] (or dropped for an admin), as the
  /// elevated script will write it.
  static Map<String, dynamic> nextRecord(String name, OsRestrictions r,
      {required bool admin}) {
    final record = readRecord();
    if (admin || r.count == 0) {
      record.remove(name.toLowerCase());
    } else {
      record[name.toLowerCase()] = r;
    }
    return {for (final e in record.entries) e.key: e.value.toJson()};
  }
}

/// Windows and Linux both refuse these; checking first gives a clear message
/// instead of an OS error.
final RegExp kOsAccountNamePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$');
final RegExp kLinuxAccountNamePattern = RegExp(r'^[a-z_][a-z0-9_-]{0,31}$');
