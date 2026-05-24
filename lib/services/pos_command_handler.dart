import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../providers/database_providers.dart';
import '../providers/settings_provider.dart';

/// Dispatches `pos-command` events received via SSE.
///
/// Add new command types here as needed.
/// Command types are matched case-insensitively for robustness.
class PosCommandHandler {
  final Ref _ref;

  PosCommandHandler(this._ref);

  /// Handle one `pos-command` payload.
  /// Returns the command type string for callers that want to react in the UI.
  Future<String?> handle(Map<String, dynamic> command) async {
    final type = (command['type'] as String? ?? '').trim();
    Logger.instance.info('PosCommandHandler: received type=$type');

    switch (type.toLowerCase()) {
      // ── Data sync commands ──────────────────────────────────────────
      case 'update:db':
      case 'reload_all':
        await _syncAll();
        return type;

      case 'reload_products':
        await _syncAll(); // only syncAllData is public
        return type;

      case 'reload_menu':
        await _syncAll();
        return type;

      // ── Alert ───────────────────────────────────────────────────────
      case 'display_alert':
        // Caller (sse_provider) reads 'message' from the raw command map
        // and pushes it to the alert StateProvider — no action here.
        return type;

      // ── Session ─────────────────────────────────────────────────────
      case 'close_session':
        // TODO: call SessionService.endSession() when needed
        Logger.instance.info('PosCommandHandler: CLOSE_SESSION not yet wired');
        return type;

      // ── Custom / future ─────────────────────────────────────────────
      case 'custom':
        Logger.instance.info(
            'PosCommandHandler: CUSTOM payload=${command['data']}');
        return type;

      default:
        Logger.instance.info('PosCommandHandler: unknown type=$type, ignoring');
        return null;
    }
  }

  Future<void> _syncAll() async {
    try {
      Logger.instance.info('PosCommandHandler: triggering full data sync');
      final dataSyncService = _ref.read(dataSyncServiceProvider);
      final settings = _ref.read(settingsProvider);
      await dataSyncService.syncAllData(
        dataRetentionDays: settings.dataRetentionDays,
      );
      Logger.instance.info('PosCommandHandler: sync complete');
    } catch (e) {
      Logger.instance.error('PosCommandHandler: sync error: $e');
    }
  }
}
