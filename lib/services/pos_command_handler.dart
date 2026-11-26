import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../providers/admin_elevation_provider.dart';
import '../providers/database_providers.dart';
import 'local_cash_session_service.dart';
import 'activity_log_service.dart';
import 'data_sync_service.dart';
import 'session_service.dart';
import 'subscription_store.dart';

/// Dispatches `pos-command` SSE events to the appropriate service action.
///
/// Command shapes (all sent as `pos-command` SSE event, JSON body):
///
/// **Sync – full**
///   { "type": "sync_all" }          — full master-data + orders + upload
///   aliases: reload_all, update:db, reload_menu
///
/// **Sync – targeted (fast, no full-wipe)**
///   { "type": "sync_menu" }         — categories, products, variants, components
///   aliases: sync_products, reload_products
///   { "type": "sync_categories" }
///   { "type": "sync_users" }
///   { "type": "sync_areas" }        — areas + tables
///   { "type": "sync_orders" }       — upload orders + pull order deltas
///   { "type": "sync_sessions" }     — upload sessions bulk
///   { "type": "sync_customers" }
///   { "type": "sync_upload" }       — upload-only (orders, sessions, tickets…)
///
/// **Sessions**
///   { "type": "close_session" }     — close current user's active session
///   aliases: close_current_session
///   { "type": "close_all_sessions" }— close ALL active sessions
///
/// **Admin mode**
///   { "type": "open_admin_mode",  "adminId": 1, "adminUsername": "alice" }
///   { "type": "close_admin_mode" }
///   aliases: exit_admin_mode
///
/// **Display alert**
///   { "type": "display_alert", "message": "Kitchen is closed" }
///
/// **Auth / subscription**
///   { "type": "refresh_token" }     — rotate the token pair now (POST /pos/refresh)
///   aliases: refresh_tokens, rotate_token, renew_token
///   { "type": "subscription_updated", "subscription": {...} }
///                                   — store the pushed subscription; without the
///                                     object, re-read GET /pos/subscription
///   aliases: refresh_subscription, sync_subscription
///
/// **Order tags**
///   { "type": "order_tags_updated" } — re-read GET /pos/order-tags
///
/// **Refund policy**
///   { "type": "refund_policy_updated" } — re-read GET /pos/refund-policy
///   aliases: sync_refund_policy
///
/// **Logout**
///   { "type": "force_logout" }      — close session + signal UI to navigate
///   aliases: logout
///
/// **Kick**
///   { "type": "force_kick", "code": "ADMIN_KICK", "message": "...", "lock": false }
///                                   — pause the shift, sign the terminal out,
///                                     show why on the login screen; lock=true
///                                     also applies the account lock
///   aliases: kick
///
/// **Account deactivation**
///   { "type": "account_disabled", "scope": "TENANT|BUSINESS|TERMINAL", "message": "..." }
///                                   — lock the till; the cashier is sent to the
///                                     login screen (AccountBlockWatcher)
///   { "type": "account_enabled" }   — re-check GET /pos/account-status
class PosCommandHandler {
  final Ref _ref;
  final _logger = Logger.instance;

  PosCommandHandler(this._ref);

  /// Handle one `pos-command` payload.
  /// Returns the normalised command type string (lowercase) so callers
  /// can react in the UI layer if needed.
  Future<String?> handle(Map<String, dynamic> command) async {
    final raw = (command['type'] as String? ?? '').trim();
    final type = raw.toLowerCase();
    _logger.info('PosCommandHandler: received type=$type');

    // Extra context written to the activity log for commands that carry info.
    String? logDetails;
    // Whether this type is recognised (false → log nothing, return null).
    bool known = true;

    switch (type) {
      // ── Full sync ─────────────────────────────────────────────────────
      case 'sync_all':
      case 'reload_all':
      case 'update:db':
      case 'reload_menu':
        await _syncAll();

      // ── Menu / product sync ───────────────────────────────────────────
      case 'sync_menu':
      case 'sync_products':
      case 'reload_products':
        await _run('sync_menu', () => _dataSyncService.syncMenu());

      case 'sync_categories':
        await _run('sync_categories', () => _dataSyncService.syncMenu());

      case 'sync_users':
        await _run('sync_users', () => _dataSyncService.syncUsersOnly());

      case 'sync_areas':
        await _run('sync_areas', () => _dataSyncService.syncAreasOnly());

      // ── Upload-only sync ──────────────────────────────────────────────
      case 'sync_upload':
        await _run('sync_upload', () => _dataSyncService.syncUpload());

      // ── Order sync ────────────────────────────────────────────────────
      case 'sync_orders':
        await _run('sync_orders', () async {
          await _dataSyncService.syncOrdersBulk();
          await _dataSyncService.refreshOpenSessions();
        });

      // ── Session sync ──────────────────────────────────────────────────
      case 'sync_sessions':
        await _run('sync_sessions', () async {
          await _dataSyncService.syncPendingOperations();
          await _dataSyncService.syncSessionsBulk();
        });

      // ── Customer sync ─────────────────────────────────────────────────
      case 'sync_customers':
        await _run('sync_customers', () async {
          await _dataSyncService.syncPendingOperations();
          await _dataSyncService.syncCustomersBulk();
        });

      // ── Close current session ─────────────────────────────────────────
      case 'close_session':
      case 'close_current_session':
        await _closeCurrentSession();

      // ── Close all sessions ────────────────────────────────────────────
      case 'close_all_sessions':
        await _closeAllSessions();

      // ── Admin mode ────────────────────────────────────────────────────
      case 'open_admin_mode':
        final adminUsername =
            command['adminUsername'] as String? ?? 'Remote Admin';
        logDetails = 'granted by $adminUsername';
        _openAdminMode(command);

      case 'close_admin_mode':
      case 'exit_admin_mode':
        _ref.read(adminElevationProvider.notifier).state = null;
        _logger.info('PosCommandHandler: admin mode cleared');

      // ── Logout / force-logout ─────────────────────────────────────────
      case 'force_logout':
      case 'logout':
        await _closeCurrentSession();

      // ── Mandatory kick: pause the shift, sign the terminal out ────────
      // Unlike force_logout this ends the terminal's sign-in, not just the
      // session; unlike account_disabled it does not lock sign-in.
      case 'force_kick':
      case 'kick':
        await _kick(command);
        logDetails = '${command['code'] ?? ''}';

      // ── Account deactivated / reactivated in the back office ─────────
      case 'account_disabled':
      case 'account_deactivated':
        await _ref.read(apiServiceProvider).applyAccountDisabledPush(command);
        logDetails = '${command['scope'] ?? ''}';
      case 'account_enabled':
      case 'account_reactivated':
        await _ref.read(apiServiceProvider).checkAccountStatus();

      // ── Token rotation ────────────────────────────────────────────────
      // Pushes the refresh token's death date out on a till that sits idle
      // (no requests → no refresh), and re-reads scope + subscription with it.
      case 'refresh_token':
      case 'refresh_tokens':
      case 'rotate_token':
      case 'renew_token':
        final ok = await _ref
            .read(apiServiceProvider)
            .ensureFreshToken(force: true);
        logDetails = ok ? 'ok' : 'failed';
        _logger.info('PosCommandHandler: token refresh ${ok ? 'done' : 'failed'}');

      // ── Subscription ──────────────────────────────────────────────────
      case 'subscription_updated':
      case 'refresh_subscription':
      case 'sync_subscription':
        if (command.containsKey('subscription')) {
          await SubscriptionStore(_ref.read(sharedPreferencesProvider))
              .apply(command['subscription']);
        } else {
          await _ref.read(apiServiceProvider).refreshSubscription();
        }

      // ── Order tags ────────────────────────────────────────────────────
      // The catalogue changed in the back office (create/rename/delete).
      case 'order_tags_updated':
        await _run('order_tags', () => _dataSyncService.syncOrderTagCatalogue());

      // ── Refund policy ─────────────────────────────────────────────────
      case 'refund_policy_updated':
      case 'sync_refund_policy':
        await _run('refund_policy', () async {
          await _ref.read(apiServiceProvider).refreshRefundPolicy();
        });

      // ── Display alert ─────────────────────────────────────────────────
      case 'display_alert':
        final msg = (command['message'] as String? ?? '').trim();
        logDetails = msg.length > 80 ? '${msg.substring(0, 80)}…' : msg;

      // ── Custom ────────────────────────────────────────────────────────
      case 'custom':
        _logger.info(
            'PosCommandHandler: custom payload=${command['data']}');

      default:
        _logger.warning(
            'PosCommandHandler: unknown command type=$type — ignoring');
        known = false;
    }

    if (!known) return null;

    // Record to the activity log regardless of which command ran.
    await _ref
        .read(activityLogServiceProvider)
        .logPosCommand(type, details: logDetails);

    return type;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  DataSyncService get _dataSyncService => _ref.read(dataSyncServiceProvider);

  /// Run [action] with structured logging; errors are swallowed so a failed
  /// sync command never crashes the SSE loop.
  Future<void> _run(String label, Future<void> Function() action) async {
    try {
      _logger.info('PosCommandHandler[$label]: starting');
      await action();
      _logger.info('PosCommandHandler[$label]: done');
    } catch (e) {
      _logger.error('PosCommandHandler[$label]: error: $e');
    }
  }

  Future<void> _syncAll() =>
      _run('sync_all', () => _dataSyncService.syncAllData());

  Future<void> _closeCurrentSession() async {
    await _run('close_current_session', () async {
      final user = _ref.read(currentUserProvider);
      if (user == null) return;
      final db = _ref.read(databaseProvider);
      final session = await SessionService(db).getActiveSession(user.id);
      if (session == null) return;
      await SessionService(db).endSession(sessionId: session.id);
      _ref.read(currentSessionProvider.notifier).state = null;
      _logger.info('PosCommandHandler: session #${session.id} closed');
    });
  }

  Future<void> _kick(Map<String, dynamic> command) async {
    // Pausing first, while the cashier is still known. A paused shift resumes
    // at the next sign-in with nothing counted or closed.
    await _run('kick_pause_session', () async {
      final user = _ref.read(currentUserProvider);
      if (user == null) return;
      final db = _ref.read(databaseProvider);
      final service = SessionService(db);
      final session = await service.getActiveSession(user.id);
      if (session != null && session.status == 'active') {
        await _ref.read(cashSessionServiceProvider).pause(session.id);
      }
      await _ref
          .read(activityLogServiceProvider)
          .logLogout(userId: user.id, username: user.effectiveDisplayName);
    });
    await _ref.read(apiServiceProvider).applyKick(command);
  }

  Future<void> _closeAllSessions() async {
    await _run('close_all_sessions', () async {
      final db = _ref.read(databaseProvider);
      final sessions = await (db.select(db.cashSessions)
            ..where((s) => s.status.isIn(['active', 'paused'])))
          .get();
      final service = SessionService(db);
      for (final s in sessions) {
        await service.endSession(sessionId: s.id);
        _logger.info('PosCommandHandler: session #${s.id} closed');
      }
      final current = _ref.read(currentSessionProvider);
      if (current != null && sessions.any((s) => s.id == current.id)) {
        _ref.read(currentSessionProvider.notifier).state = null;
      }
    });
  }

  void _openAdminMode(Map<String, dynamic> command) {
    final adminId = (command['adminId'] as num?)?.toInt() ?? 0;
    final adminUsername =
        command['adminUsername'] as String? ?? 'Remote Admin';
    _ref.read(adminElevationProvider.notifier).state = AdminElevation(
      adminId: adminId,
      adminUsername: adminUsername,
    );
    _logger.info(
        'PosCommandHandler: admin mode opened by $adminUsername (#$adminId)');
  }
}
