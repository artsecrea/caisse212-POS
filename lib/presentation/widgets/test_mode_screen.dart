import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/session_expiry.dart';
import '../../domain/models/subscription_info.dart';
import '../../providers/database_providers.dart';
import '../../providers/reauth_provider.dart';
import '../../providers/sse_provider.dart';
import '../../services/subscription_store.dart';
import '../../services/refund_policy_store.dart';
import '../../services/refund_sandbox.dart';
import '../../services/daily_summary_service.dart';
import '../../utils/escpos_text.dart';
import 'subscription_notice.dart';
import 'token_debug_panel.dart';

/// Bench for server-driven states that are slow or impossible to produce on
/// demand: a subscription two weeks from its end, an SSE command arriving.
///
/// Reachable only from a debug or profile build — the login screen gates the
/// entry on `kReleaseMode`, so the tree shaker drops it from what ships.
///
/// Everything here writes through the real code paths (SubscriptionStore, the
/// real PosCommandHandler), so what you see is what the server would cause.
/// A simulated subscription is stamped "checked today", so the daily check
/// will not overwrite it until tomorrow; a sync against a server that has the
/// endpoint will.
class TestModeScreen extends ConsumerStatefulWidget {
  const TestModeScreen({super.key});

  @override
  ConsumerState<TestModeScreen> createState() => _TestModeScreenState();
}

class _TestModeScreenState extends ConsumerState<TestModeScreen> {
  final _days = TextEditingController(text: '10');
  final _contact = TextEditingController(text: '+212 6 00 00 00 00');
  final _alert = TextEditingController(text: 'Test alert from the test screen');
  String _log = '';
  bool _autoRestore = true;
  Timer? _restoreTimer;

  // Refund sandbox.
  SandboxResult? _sandbox;
  bool _sandboxRunning = false;

  @override
  void dispose() {
    _restoreTimer?.cancel();
    _days.dispose();
    _contact.dispose();
    _alert.dispose();
    super.dispose();
  }

  SubscriptionStore get _store =>
      SubscriptionStore(ref.read(sharedPreferencesProvider));

  Future<void> _setEndingIn(Duration d, {String status = 'ACTIVE'}) async {
    final contact = _contact.text.trim();
    await _store.apply({
      'status': status,
      'endsAt': DateTime.now().add(d).toUtc().toIso8601String(),
      'planName': 'Test plan',
      if (contact.isNotEmpty) 'contact': contact,
    });
    _note('Subscription set: $status, ends ${DateTime.now().add(d)}');
  }

  Future<void> _command(Map<String, dynamic> cmd) async {
    _note('→ ${cmd['type']} …');
    try {
      final handled = await ref.read(posCommandHandlerProvider).handle(cmd);
      if (handled == 'display_alert') {
        ref.read(sseAlertProvider.notifier).state = cmd['message'] as String?;
      }
      _note('← ${cmd['type']}: ${handled ?? 'not recognised'}');
    } catch (e) {
      _note('← ${cmd['type']} threw: $e');
    }
  }

  /// Moves the client's idea of the session death to now + [d] and lets the
  /// notice and the gate react immediately, as the 60 s poll would.
  Future<void> _setSessionExpiry(Duration d, String label) async {
    final api = ref.read(apiServiceProvider);
    await api.debugSetRefreshExpiry(DateTime.now().add(d));
    ref.read(reauthRequiredProvider.notifier).reevaluate();
    _note('Sign-in now expires ${api.getRefreshExpiresAt()} ($label)');
    _armRestore(blocking: ref.read(reauthRequiredProvider));
  }

  /// The gate covers this screen too, so a blocking simulation has to undo
  /// itself (or be cleared by a real re-auth with the tenant password).
  void _armRestore({required bool blocking}) {
    _restoreTimer?.cancel();
    if (!blocking || !_autoRestore) return;
    _note('Gate is up — restoring the real expiry in 30 s '
        '(or sign in on the gate with the real password)');
    _restoreTimer = Timer(const Duration(seconds: 30), _restoreSession);
  }

  Future<void> _restoreSession() async {
    _restoreTimer?.cancel();
    final api = ref.read(apiServiceProvider);
    await api.debugSetRefreshExpiry(null);
    ref.read(reauthRequiredProvider.notifier).reevaluate();
    ref.read(reauthVoluntaryProvider.notifier).state = false;
    _note('Real sign-in expiry restored: ${api.getRefreshExpiresAt()}');
  }

  static String _tail(String? t) =>
      t == null ? 'none' : t.substring(t.length > 8 ? t.length - 8 : 0);

  Future<void> _runSandbox() async {
    setState(() => _sandboxRunning = true);
    final result = await RefundSandbox.run(
      printing: ref.read(printingServiceProvider),
      prefs: ref.read(sharedPreferencesProvider),
    );
    if (!mounted) return;
    setState(() {
      _sandbox = result;
      _sandboxRunning = false;
    });
    final passed = result.checks.where((c) => c.ok).length;
    _note('Refund test: $passed/${result.checks.length} checks passed');
  }

  /// Desktop when there is one (where the activity-log export goes too), else
  /// the app documents folder.
  Future<Directory> _exportDir() async {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final desktop = Directory(p.join(home, 'Desktop'));
      if (await desktop.exists()) return desktop;
    }
    return getApplicationDocumentsDirectory();
  }

  /// Saves [text] as a .txt next to the other exports and shows it.
  Future<void> _exportAndShow(String title, String text, String slug) async {
    String? path;
    try {
      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final file = File(p.join((await _exportDir()).path,
          'caisse212_X_${slug}_$stamp.txt'));
      await file.writeAsString(text);
      path = file.path;
      _note('X exported: $path');
    } catch (e) {
      _note('X export failed: $e');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (path != null)
                SelectableText(path,
                    style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.black),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// The real X of the cashier's open session, read-only — what the X button
  /// would print, as text.
  Future<void> _exportCurrentX() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      _note('No open session: sign in and open one (Test mode is also in the '
          'user menu)');
      return;
    }
    try {
      final report = await DailySummaryService(ref.read(databaseProvider))
          .generateSessionReport(session.id);
      final bytes =
          await ref.read(printingServiceProvider).buildDailySummaryReportBytes(
                report: report,
                reportType: 'X',
                businessName: ref
                    .read(sharedPreferencesProvider)
                    .getString('business_name'),
              );
      await _exportAndShow(
          'X — session ${session.code}', escPosToText(bytes), 'session');
    } catch (e) {
      _note('X of the current session failed: $e');
    }
  }

  void _note(String line) {
    if (!mounted) return;
    setState(() => _log = '${TimeOfDay.now().format(context)}  $line\n$_log');
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(subscriptionProvider);
    final api = ref.read(apiServiceProvider);
    final store = _store;
    final now = DateTime.now();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Test mode (debug only)')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const TokenDebugPanel(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.autorenew, size: 18),
                label: const Text('Run refresh_token here'),
                onPressed: () async {
                  final before = api.getRefreshToken();
                  await _command({'type': 'refresh_token'});
                  final after = api.getRefreshToken();
                  _note(after != before
                      ? 'ROTATED: refresh token …${_tail(before)} → …${_tail(after)}'
                      : 'NOT rotated — POST /pos/refresh failed (server '
                          '${api.getBaseUrl() ?? '?'} unreachable or refused); see app log');
                },
              ),
            ],
          ),
          const Divider(height: 40),
          Text('Subscription', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Stored: ${info == null ? 'none' : '${info.status} until ${info.endsAt}'}\n'
            'Level now: ${subscriptionLevel(info, now).name}   ·   '
            'Last checked: ${store.lastCheckedAt ?? 'never'}   ·   '
            'Daily check due: ${store.checkDue}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          // The real banner, exactly as the login screen draws it.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: const SubscriptionNotice(),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                  onPressed: () => _setEndingIn(const Duration(days: 13)),
                  child: const Text('Ends in 13 days')),
              OutlinedButton(
                  onPressed: () => _setEndingIn(const Duration(days: 1, hours: 2)),
                  child: const Text('Ends tomorrow')),
              OutlinedButton(
                  onPressed: () {
                    final end = DateTime(now.year, now.month, now.day, 23, 59);
                    _setEndingIn(end.difference(now));
                  },
                  child: const Text('Ends today')),
              OutlinedButton(
                  onPressed: () => _setEndingIn(const Duration(days: -3)),
                  child: const Text('Expired 3 days ago')),
              OutlinedButton(
                  onPressed: () => _setEndingIn(const Duration(days: 200),
                      status: 'EXPIRED'),
                  child: const Text('Status EXPIRED')),
              OutlinedButton(
                  onPressed: () => _setEndingIn(const Duration(days: 30)),
                  child: const Text('Ends in 30 days (no banner)')),
              OutlinedButton(
                  onPressed: () async {
                    await _store.apply(null);
                    _note('Subscription cleared (server sent null)');
                  },
                  child: const Text('Clear')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _days,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  decoration: const InputDecoration(labelText: 'Days from now'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _contact,
                  decoration: const InputDecoration(labelText: 'Contact (optional)'),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  final d = int.tryParse(_days.text.trim());
                  if (d != null) _setEndingIn(Duration(days: d));
                },
                child: const Text('Set'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () async {
                  final ok = await api.refreshSubscription();
                  _note('GET /pos/subscription → ${ok ? 'ok' : 'failed (kept stored copy)'}');
                },
                child: const Text('Check server now'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  final ok = await api.refreshSubscription(onlyIfDue: true);
                  _note('Daily check (only if due) → ${ok ? 'ok / not due' : 'failed'}');
                },
                child: const Text('Run daily check'),
              ),
            ],
          ),
          const Divider(height: 40),
          Text('Sign-in (token) expiry', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Notice level: ${sessionExpiryLevel(api.getRefreshExpiresAt(), now).name}'
            '   ·   gate up: ${ref.watch(reauthRequiredProvider)}'
            '   ·   live countdowns in the Tokens panel at the top',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            "Only the till's idea of the expiry moves; the tokens stay valid on "
            'the server. Any real refresh or re-login puts the true date back.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                  onPressed: () =>
                      _setSessionExpiry(const Duration(days: 6), 'login notice'),
                  child: const Text('Expires in 6 days (notice)')),
              OutlinedButton(
                  onPressed: () => _setSessionExpiry(
                      const Duration(days: 1, hours: 2), 'last notice day'),
                  child: const Text('Expires in 26 h')),
              OutlinedButton(
                  onPressed: () => _setSessionExpiry(
                      const Duration(hours: 20), 'inside 24 h → gate'),
                  child: const Text('Expires in 20 h (gate)')),
              OutlinedButton(
                  onPressed: () => _setSessionExpiry(
                      const Duration(minutes: -5), 'already expired → gate'),
                  child: const Text('Already expired (gate)')),
              OutlinedButton(
                  onPressed: () {
                    ref.read(apiServiceProvider).debugSimulateRefreshRejected();
                    _note('Simulated refresh rejected by the server (4xx)');
                    _armRestore(blocking: true);
                  },
                  child: const Text('Refresh rejected (4xx)')),
              FilledButton.tonal(
                  onPressed: _restoreSession,
                  child: const Text('Restore real expiry')),
            ],
          ),
          Row(
            children: [
              Checkbox(
                value: _autoRestore,
                onChanged: (v) => setState(() => _autoRestore = v ?? true),
              ),
              const Text('Auto-restore 30 s after the gate goes up'),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final api = ref.read(apiServiceProvider);
                  await api.debugSetAccessExpiry(
                      DateTime.now().subtract(const Duration(seconds: 1)));
                  _note('Access token marked expired');
                },
                child: const Text('Expire access token'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final api = ref.read(apiServiceProvider);
                  final before = api.getAccessExpiresAt();
                  // Any normal request takes the pre-emptive refresh path.
                  final ok = await api.refreshSubscription();
                  _note('API call ${ok ? 'ok' : 'failed'} — access expiry '
                      '$before → ${api.getAccessExpiresAt()}');
                },
                child: const Text('Make an API call'),
              ),
            ],
          ),
          const Divider(height: 40),
          Text('Refund test', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Runs a full refund and exchange scenario through the real refund, '
            'exchange, policy, Z and X code on a throwaway database: nothing '
            'is written to this till and nothing is sent to the server. '
            'Yesterday (closed Z): 2 Coca + 1 Tajine (non-refundable) paid by '
            'card. Today (float 200): 3 Coca, a T-shirt and a jean. Then 3 '
            'refunds, 2 refused over-refunds, 2 exchanges (one where the '
            'customer pays more, one where money goes back), the exchange '
            'ticket and the X.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _sandboxRunning ? null : _runSandbox,
                icon: _sandboxRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: const Text('Run refund test'),
              ),
              OutlinedButton.icon(
                onPressed: (_sandbox?.xText.isNotEmpty ?? false)
                    ? () => _exportAndShow(
                        'X — refund test', _sandbox!.xText, 'refund_test')
                    : null,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Export X (test)'),
              ),
              OutlinedButton.icon(
                onPressed: (_sandbox?.exchangeTicketText.isNotEmpty ?? false)
                    ? () => _exportAndShow('Exchange ticket — test',
                        _sandbox!.exchangeTicketText, 'exchange_ticket')
                    : null,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Export exchange ticket (test)'),
              ),
              OutlinedButton.icon(
                onPressed: _exportCurrentX,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Export X (my session)'),
              ),
            ],
          ),
          if (_sandbox != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_sandbox!.allOk ? Colors.green : theme.colorScheme.error)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: (_sandbox!.allOk
                            ? Colors.green
                            : theme.colorScheme.error)
                        .withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sandbox!.allOk
                        ? 'ALL ${_sandbox!.checks.length} CHECKS PASSED'
                        : '${_sandbox!.checks.where((c) => !c.ok).length} '
                            'CHECK(S) FAILED',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _sandbox!.allOk
                            ? Colors.green
                            : theme.colorScheme.error),
                  ),
                  const SizedBox(height: 6),
                  for (final c in _sandbox!.checks)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(c.ok ? Icons.check_circle : Icons.cancel,
                              size: 18,
                              color: c.ok
                                  ? Colors.green
                                  : theme.colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.label,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                SelectableText(c.detail,
                                    style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const Divider(height: 40),
          Text('Refund policy', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          SelectableText(
            const JsonEncoder.withIndent('  ')
                .convert(ref.watch(refundPolicyProvider).toJson()),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Written to the same cache the server fills; the next sync or a '
            'refund_policy_updated command replaces it with the real one.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  await RefundPolicyStore(ref.read(sharedPreferencesProvider))
                      .apply({
                    'windowDays': 7,
                    'closedZNeedsPermission': true,
                    'approvalAbove': 200,
                    'requireReason': true,
                    'reasons': [
                      {'code': 'DEFECTIVE', 'label': 'Produit défectueux'},
                      {'code': 'WRONG_ITEM', 'label': 'Erreur de commande'},
                      {'code': 'OTHER', 'label': 'Autre'},
                    ],
                    'allowedMethods': ['CASH', 'CARD'],
                    'methodMustMatchPayment': true,
                    'allowPartial': true,
                    'defaultRestock': true,
                  });
                  _note('Strict demo refund policy loaded');
                },
                child: const Text('Strict demo policy'),
              ),
              OutlinedButton(
                onPressed: () async {
                  await RefundPolicyStore(ref.read(sharedPreferencesProvider))
                      .apply({'enabled': false});
                  _note('Refunds switched off');
                },
                child: const Text('Refunds off'),
              ),
              OutlinedButton(
                onPressed: () async {
                  await RefundPolicyStore(ref.read(sharedPreferencesProvider))
                      .apply(null);
                  _note('Refund policy reset to the defaults');
                },
                child: const Text('Defaults (no policy)'),
              ),
              FilledButton.tonal(
                onPressed: () => _command({'type': 'refund_policy_updated'}),
                child: const Text('Fetch from server'),
              ),
            ],
          ),
          const Divider(height: 40),
          Text('SSE commands (run through the real handler)',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  await _command({'type': 'refresh_token'});
                  if (mounted) setState(() {});
                },
                child: const Text('refresh_token'),
              ),
              OutlinedButton(
                onPressed: () => _command({
                  'type': 'subscription_updated',
                  'subscription': {
                    'status': 'ACTIVE',
                    'endsAt': DateTime.now()
                        .add(const Duration(days: 365))
                        .toUtc()
                        .toIso8601String(),
                  },
                }),
                child: const Text('subscription_updated (renewed +1y)'),
              ),
              OutlinedButton(
                onPressed: () => _command({'type': 'subscription_updated'}),
                child: const Text('subscription_updated (no payload → GET)'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _alert,
                  decoration: const InputDecoration(labelText: 'Alert message'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () =>
                    _command({'type': 'display_alert', 'message': _alert.text}),
                child: const Text('display_alert'),
              ),
            ],
          ),
          const Divider(height: 40),
          Text('Log', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(_log.isEmpty ? '—' : _log,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ],
      ),
    );
  }
}
