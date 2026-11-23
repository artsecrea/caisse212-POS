import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/account_status.dart';
import '../utils/pos_log.dart';

/// Persists "the server says this account is disabled".
///
/// Persisted because the lock must survive a restart. Otherwise closing and
/// reopening the app, or pulling the network cable, would bypass it. Only the
/// server clears it: a successful login or refresh, `accountStatus.active:
/// true`, or a tenant switch.
class AccountStatusStore {
  final SharedPreferences _prefs;
  AccountStatusStore(this._prefs);

  static const _key = 'pos_account_block_json';

  // Static for the same reason as SubscriptionStore: short-lived ApiService
  // instances share the prefs, so a per-instance stream would reach nobody.
  static final _controller = StreamController<AccountBlock?>.broadcast();
  static Stream<AccountBlock?> get changes => _controller.stream;

  AccountBlock? get current {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AccountBlock.fromJson(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  bool get isBlocked => current != null;

  Future<void> block(AccountBlock block) async {
    final prev = current;
    // Keep the first "since" so the card says how long it has been locked,
    // not when the last refused call happened.
    final kept = prev == null
        ? block
        : AccountBlock(
            scope: block.scope,
            message: block.message ?? prev.message,
            reasonCode: block.reasonCode ?? prev.reasonCode,
            since: prev.since);
    await _prefs.setString(_key, jsonEncode(kept.toJson()));
    if (prev == null) {
      posLog('Account: BLOCKED (${block.scope.name}) ${block.message ?? ''}');
    }
    _controller.add(kept);
  }

  Future<void> clear() async {
    if (_prefs.getString(_key) == null) return;
    await _prefs.remove(_key);
    posLog('Account: active again');
    _controller.add(null);
  }

  /// Applies a parsed `accountStatus` value (see [parseAccountStatus]).
  Future<void> applyStatus(Object? parsed) async {
    if (parsed == true) {
      await clear();
    } else if (parsed is AccountBlock) {
      await block(parsed);
    }
  }
}
