import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/os_accounts/linux_os_accounts.dart';
import '../../services/os_accounts/os_account_service.dart';
import '../../services/remote_access_reporter.dart';
import '../../services/remote_support_service.dart';
import '../../services/shared_storage.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import '../widgets/adaptive_text_field.dart';
import 'diagnostics_panel.dart';

/// Manages the machine's own sign-in accounts (Windows / Ubuntu): create
/// them, reset their passwords, and lock down what a till cashier can change.
class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen>
    with SingleTickerProviderStateMixin {
  final OsAccountService? _service = OsAccountService.forPlatform();
  late Future<_ScreenData> _data;
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });

  @override
  void initState() {
    super.initState();
    if (_service != null) _data = _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<_ScreenData> _load() async {
    final s = _service!;
    final results = await Future.wait([s.listAccounts(), s.isElevated()]);
    return _ScreenData(
      accounts: results[0] as List<OsAccount>,
      elevated: results[1] as bool,
      record: OsAccountService.readRecord(),
    );
  }

  void _refresh() {
    final next = _load();
    setState(() {
      _data = next;
    });
  }

  /// Runs an OS change, reporting the outcome; true when it went through.
  Future<bool> _apply(Future<void> Function() change, String doneKey) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await change();
      SnackBarHelper.showToast(l10n.translate(doneKey), kind: ToastKind.success);
      _refresh();
      return true;
    } on OsAccountException catch (e) {
      SnackBarHelper.showToast(
          e.cancelled ? l10n.translate('os_admin_refused') : e.message,
          kind: e.cancelled ? ToastKind.warning : ToastKind.error);
      return false;
    }
  }

  Future<void> _openEditor([OsAccount? account, OsRestrictions? current]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OsAccountEditorDialog(
        service: _service!,
        account: account,
        current: current,
        apply: _apply,
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _changePassword(OsAccount account) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OsPasswordDialog(
        account: account,
        onSave: (pw) => _apply(
            () => _service!.setPassword(account.name, pw), 'password_changed_successfully'),
      ),
    );
  }

  Future<void> _launchSupport({required bool tech}) async {
    final missing =
        AppLocalizations.of(context)!.translate('remote_support_missing');
    if (!await RemoteSupportService.launch(tech: tech)) {
      SnackBarHelper.showToast(missing, kind: ToastKind.error);
    }
  }

  /// Installs the support service on a till that never had it (deployed before
  /// remote support shipped), so it can be reached without a full reinstall.
  /// One UAC prompt; the super admin has the rights a cashier does not.
  Future<void> _installSupport() async {
    final l10n = AppLocalizations.of(context)!;
    SnackBarHelper.showToast(l10n.translate('remote_support_installing'),
        kind: ToastKind.info);
    final ok = await RemoteSupportService.install();
    if (!mounted) return;
    if (ok) {
      // Push the fresh password to the back office now, not only on the next
      // reconnect.
      try {
        await ProviderScope.containerOf(context, listen: false)
            .read(remoteAccessReporterProvider)
            .report(force: true);
      } catch (_) {}
      SnackBarHelper.showToast(l10n.translate('remote_support_installed'),
          kind: ToastKind.success);
      setState(() {});
    } else {
      SnackBarHelper.showToast(l10n.translate('remote_support_install_failed'),
          kind: ToastKind.error);
    }
  }

  Future<void> _setupLinuxShared() async {
    final done = await _apply(
        () => (_service as LinuxOsAccounts).setupSharedFolder(),
        'os_shared_ready');
    if (done && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.errorContainer,
        foregroundColor: scheme.onErrorContainer,
        title: Row(children: [
          const Icon(Icons.admin_panel_settings),
          const SizedBox(width: 8),
          Text(l10n.translate('super_admin_mode')),
        ]),
        actions: [
          if (RemoteSupportService.available && !RemoteSupportService.installed)
            IconButton(
              icon: const Icon(Icons.install_desktop),
              tooltip: l10n.translate('remote_support_install'),
              onPressed: _installSupport,
            ),
          if (RemoteSupportService.available)
            IconButton(
              icon: const Icon(Icons.support_agent),
              tooltip: l10n.translate('remote_support'),
              onPressed: () => _launchSupport(tech: false),
            ),
          if (RemoteSupportService.available)
            IconButton(
              icon: const Icon(Icons.dns),
              tooltip: l10n.translate('remote_support_server'),
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => SupportServerDialog(apply: _apply),
              ),
            ),
          if (RemoteSupportService.techAvailable)
            IconButton(
              icon: const Icon(Icons.connected_tv),
              tooltip: l10n.translate('remote_support_tech'),
              onPressed: () => _launchSupport(tech: true),
            ),
          if (_tabs.index == 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.translate('refresh'),
              onPressed: _service == null ? null : _refresh,
            ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: scheme.onErrorContainer,
          unselectedLabelColor: scheme.onErrorContainer.withValues(alpha: 0.7),
          indicatorColor: scheme.onErrorContainer,
          tabs: [
            Tab(
                icon: const Icon(Icons.manage_accounts),
                text: l10n.translate('os_accounts')),
            Tab(
                icon: const Icon(Icons.health_and_safety),
                text: l10n.translate('diagnostics')),
          ],
        ),
      ),
      floatingActionButton: _service == null || _tabs.index != 0
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.person_add),
              label: Text(l10n.translate('os_create_account')),
            ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _accountsTab(l10n, scheme),
          const DiagnosticsPanel(),
        ],
      ),
    );
  }

  Widget _accountsTab(AppLocalizations l10n, ColorScheme scheme) {
    return _service == null
          ? Center(child: Text(l10n.translate('os_accounts_unsupported')))
          : FutureBuilder<_ScreenData>(
              future: _data,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                      child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('${snap.error}',
                        style: TextStyle(color: scheme.error)),
                  ));
                }
                final data = snap.data!;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    _StatusBar(
                      elevated: data.elevated,
                      onSetupShared: Platform.isLinux &&
                              SharedStorage.active == null
                          ? _setupLinuxShared
                          : null,
                    ),
                    const SizedBox(height: 12),
                    for (final a in data.accounts) ...[
                      _AccountCard(
                        account: a,
                        restrictions:
                            data.record[a.name.toLowerCase()] ?? OsRestrictions.none,
                        onPassword: () => _changePassword(a),
                        onEdit: () =>
                            _openEditor(a, data.record[a.name.toLowerCase()]),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            );
  }
}

class _ScreenData {
  final List<OsAccount> accounts;
  final bool elevated;
  final Map<String, OsRestrictions> record;
  _ScreenData(
      {required this.accounts, required this.elevated, required this.record});
}

class _StatusBar extends StatelessWidget {
  final bool elevated;
  final VoidCallback? onSetupShared;
  const _StatusBar({required this.elevated, required this.onSetupShared});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final shared = SharedStorage.active;
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: TextStyle(color: scheme.onSurfaceVariant))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(elevated ? Icons.verified_user : Icons.shield_outlined,
              l10n.translate(elevated ? 'os_running_elevated' : 'os_will_ask_admin')),
          line(
              shared != null ? Icons.folder_shared : Icons.folder_off,
              shared != null
                  ? l10n.translate('os_shared_data').replaceAll('{path}', shared)
                  : l10n.translate('os_shared_data_off')),
          if (onSetupShared != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onSetupShared,
                icon: const Icon(Icons.create_new_folder),
                label: Text(l10n.translate('os_setup_shared')),
              ),
            ),
          line(Icons.info_outline, l10n.translate('os_next_sign_in_hint')),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final OsAccount account;
  final OsRestrictions restrictions;
  final VoidCallback onPassword;
  final VoidCallback onEdit;

  const _AccountCard({
    required this.account,
    required this.restrictions,
    required this.onPassword,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String label, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: strong ? scheme.tertiaryContainer : scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: strong
                      ? scheme.onTertiaryContainer
                      : scheme.onSecondaryContainer)),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          CircleAvatar(
            backgroundColor:
                account.isAdmin ? scheme.primaryContainer : scheme.surfaceContainerHigh,
            foregroundColor:
                account.isAdmin ? scheme.onPrimaryContainer : scheme.onSurface,
            child: Icon(account.isAdmin ? Icons.shield : Icons.person),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(account.name,
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                    chip(l10n.translate(
                        account.isAdmin ? 'os_role_admin' : 'os_role_standard')),
                    if (account.isCurrent)
                      chip(l10n.translate('os_current_account'), strong: true),
                    if (!account.enabled)
                      chip(l10n.translate('os_account_disabled')),
                    if (!account.isAdmin && restrictions.count > 0)
                      chip(l10n
                          .translate('os_restrictions_count')
                          .replaceAll('{count}', '${restrictions.count}')),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.password),
            tooltip: l10n.translate('change_password'),
            onPressed: onPassword,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.translate('os_edit_account'),
            onPressed: onEdit,
          ),
        ]),
      ),
    );
  }
}

typedef ApplyChange = Future<bool> Function(
    Future<void> Function() change, String doneKey);

/// Create an account, or change an existing one's role and restrictions.
class OsAccountEditorDialog extends StatefulWidget {
  final OsAccountService service;
  final OsAccount? account;
  final OsRestrictions? current;
  final ApplyChange apply;

  const OsAccountEditorDialog({
    super.key,
    required this.service,
    required this.apply,
    this.account,
    this.current,
  });

  @override
  State<OsAccountEditorDialog> createState() => _OsAccountEditorDialogState();
}

class _OsAccountEditorDialogState extends State<OsAccountEditorDialog> {
  final _name = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _newApp = TextEditingController();
  bool _admin = false;
  late OsRestrictions _r;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.account == null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a == null) {
      _r = OsRestrictions.lockedDown(const []);
    } else {
      _name.text = a.name;
      _fullName.text = a.fullName;
      _admin = a.isAdmin;
      _r = widget.current ?? OsRestrictions.none;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _fullName, _password, _confirm, _newApp]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(AppLocalizations l10n) {
    final name = _name.text.trim();
    if (_isNew) {
      final pattern =
          Platform.isLinux ? kLinuxAccountNamePattern : kOsAccountNamePattern;
      if (!pattern.hasMatch(name)) return l10n.translate('os_invalid_name');
      if (_fullName.text.contains(':')) return l10n.translate('os_invalid_name');
      if (_password.text.isEmpty) return l10n.translate('password_required');
      if (_password.text.contains('\n')) return l10n.translate('os_invalid_name');
      if (_password.text != _confirm.text) {
        return l10n.translate('passwords_do_not_match');
      }
    }
    return null;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final error = _validate(l10n);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final s = widget.service;
    final ok = await widget.apply(
      () => _isNew
          ? s.createAccount(
              name: _name.text.trim(),
              fullName: _fullName.text.trim(),
              password: _password.text,
              admin: _admin,
              restrictions: _r,
            )
          : s.updateAccount(
              name: widget.account!.name,
              admin: _admin,
              restrictions: _r,
            ),
      _isNew ? 'os_account_created' : 'os_account_updated',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String labelKey,
      {bool obscure = false, bool enabled = true}) {
    final l10n = AppLocalizations.of(context)!;
    return AdaptiveKeyboardTextField(
      controller: c,
      obscureText: obscure,
      enabled: enabled && !_saving,
      decoration: InputDecoration(
        labelText: l10n.translate(labelKey),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  bool _get(OsRestriction k) => switch (k) {
        OsRestriction.settings => _r.settings,
        OsRestriction.personalization => _r.personalization,
        OsRestriction.printers => _r.printers,
        OsRestriction.time => _r.time,
        OsRestriction.install => _r.install,
        OsRestriction.tools => _r.tools,
        OsRestriction.drives => _r.drives,
      };

  void _set(OsRestriction k, bool v) => setState(() => _r = switch (k) {
        OsRestriction.settings => _r.copyWith(settings: v),
        OsRestriction.personalization => _r.copyWith(personalization: v),
        OsRestriction.printers => _r.copyWith(printers: v),
        OsRestriction.time => _r.copyWith(time: v),
        OsRestriction.install => _r.copyWith(install: v),
        OsRestriction.tools => _r.copyWith(tools: v),
        OsRestriction.drives => _r.copyWith(drives: v),
      });

  void _addApp() {
    final app = _newApp.text.trim();
    if (app.isEmpty) return;
    final name = app.toLowerCase().endsWith('.exe') ? app : '$app.exe';
    setState(() {
      _r = _r.copyWith(allowedApps: [..._r.allowedApps, name]);
      _newApp.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final s = widget.service;
    final account = widget.account;
    final posApps = s.posApps;
    final canDemote = account == null || !account.isCurrent;
    return AlertDialog(
      title: Text(_isNew
          ? l10n.translate('os_create_account')
          : '${l10n.translate('os_edit_account')} — ${account!.label}'),
      content: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: ListView(
          children: [
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: _field(_name, 'os_account_name', enabled: _isNew)),
              const SizedBox(width: 12),
              Expanded(child: _field(_fullName, 'os_full_name', enabled: _isNew)),
            ]),
            if (_isNew) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _field(_password, 'password', obscure: true)),
                const SizedBox(width: 12),
                Expanded(
                    child: _field(_confirm, 'confirm_password', obscure: true)),
              ]),
            ],
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.person),
                    label: Text(l10n.translate('os_role_standard'))),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.shield),
                    label: Text(l10n.translate('os_role_admin'))),
              ],
              selected: {_admin},
              onSelectionChanged: _saving || (!canDemote && _admin)
                  ? null
                  : (v) => setState(() => _admin = v.first),
            ),
            const SizedBox(height: 16),
            if (_admin)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(l10n.translate('os_admin_unrestricted')),
              )
            else ...[
              Text(l10n.translate('os_restrictions'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final k in OsRestriction.values)
                SwitchListTile(
                  dense: true,
                  title: Text(l10n.translate('os_block_${k.name}')),
                  subtitle: Text(
                      s.supported.contains(k)
                          ? l10n.translate('os_block_${k.name}_hint')
                          : l10n.translate('os_windows_only'),
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  value: s.supported.contains(k) && _get(k),
                  onChanged: _saving || !s.supported.contains(k)
                      ? null
                      : (v) => _set(k, v),
                ),
              const Divider(),
              SwitchListTile(
                dense: true,
                title: Text(l10n.translate('os_only_allowed_apps')),
                subtitle: Text(
                    s.supportsAllowedApps
                        ? l10n.translate('os_only_allowed_apps_hint')
                        : l10n.translate('os_windows_only'),
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                value: s.supportsAllowedApps && _r.onlyAllowedApps,
                onChanged: _saving || !s.supportsAllowedApps
                    ? null
                    : (v) => setState(() => _r = _r.copyWith(onlyAllowedApps: v)),
              ),
              if (s.supportsAllowedApps && _r.onlyAllowedApps) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final app in posApps)
                        Chip(
                            avatar: const Icon(Icons.lock, size: 16),
                            label: Text(app)),
                      for (final app in _r.allowedApps)
                        if (!posApps.any(
                            (x) => x.toLowerCase() == app.toLowerCase()))
                          InputChip(
                            label: Text(app),
                            onDeleted: _saving
                                ? null
                                : () => setState(() => _r = _r.copyWith(
                                    allowedApps: [
                                      for (final x in _r.allowedApps)
                                        if (x != app) x
                                    ])),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(child: _field(_newApp, 'os_add_app')),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add),
                      onPressed: _saving ? null : _addApp,
                    ),
                  ]),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.translate('cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.translate('save')),
        ),
      ],
    );
  }
}

/// New password for any account, without knowing the old one.
class OsPasswordDialog extends StatefulWidget {
  final OsAccount account;
  final Future<bool> Function(String password) onSave;
  const OsPasswordDialog(
      {super.key, required this.account, required this.onSave});

  @override
  State<OsPasswordDialog> createState() => _OsPasswordDialogState();
}

class _OsPasswordDialogState extends State<OsPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (_password.text.isEmpty) {
      setState(() => _error = l10n.translate('password_required'));
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = l10n.translate('passwords_do_not_match'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onSave(_password.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
          '${l10n.translate('change_password')} — ${widget.account.label}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.account.isCurrent) ...[
              Text(l10n.translate('os_current_password_hint'),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
            ],
            AdaptiveKeyboardTextField(
              controller: _password,
              obscureText: true,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: l10n.translate('new_password'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            AdaptiveKeyboardTextField(
              controller: _confirm,
              obscureText: true,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: l10n.translate('confirm_password'),
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.translate('cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.translate('save')),
        ),
      ],
    );
  }
}

/// Where the support tool connects; forced over its own settings.
class SupportServerDialog extends StatefulWidget {
  final ApplyChange apply;
  const SupportServerDialog({super.key, required this.apply});

  @override
  State<SupportServerDialog> createState() => _SupportServerDialogState();
}

class _SupportServerDialogState extends State<SupportServerDialog> {
  final _host = TextEditingController();
  final _key = TextEditingController();
  final _api = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = RemoteSupportService.readConfig();
    _host.text = c.host;
    _key.text = c.key;
    _api.text = c.api;
  }

  @override
  void dispose() {
    _host.dispose();
    _key.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _save(RemoteSupportConfig c) async {
    setState(() => _saving = true);
    final ok = await widget.apply(
        () => RemoteSupportService.saveConfig(c), 'remote_support_server_saved');
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String labelKey, {String? hint}) {
    final l10n = AppLocalizations.of(context)!;
    return AdaptiveKeyboardTextField(
      controller: c,
      enabled: !_saving,
      decoration: InputDecoration(
        labelText: l10n.translate(labelKey),
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.translate('remote_support_server')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.translate('remote_support_server_hint'),
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            _field(_host, 'remote_support_host',
                hint: RemoteSupportService.defaultHost),
            const SizedBox(height: 12),
            _field(_key, 'remote_support_key'),
            const SizedBox(height: 12),
            _field(_api, 'remote_support_api'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => _save(const RemoteSupportConfig()),
          child: Text(l10n.translate('remote_support_reset')),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.translate('cancel')),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () => _save(RemoteSupportConfig(
                  host: _host.text, key: _key.text, api: _api.text)),
          child: Text(l10n.translate('save')),
        ),
      ],
    );
  }
}
