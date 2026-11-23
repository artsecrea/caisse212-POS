import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/refund_policy.dart';
import '../utils/pos_log.dart';

/// Caches the refund policy the server last sent, so a till refunding offline
/// still applies it.
///
/// Same shape as [SubscriptionStore]: a static change stream, because short-
/// lived ApiService/DataSyncService instances write it and the provider that
/// the refund dialog reads must hear about it.
class RefundPolicyStore {
  final SharedPreferences _prefs;
  RefundPolicyStore(this._prefs);

  static const _key = 'pos_refund_policy_json';

  static final _controller = StreamController<RefundPolicy>.broadcast();
  static Stream<RefundPolicy> get changes => _controller.stream;

  /// The cached policy, or [RefundPolicy.defaults] when none was ever stored
  /// (or the server said nothing is configured).
  RefundPolicy get current {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return RefundPolicy.defaults;
    try {
      return RefundPolicy.fromJson(jsonDecode(raw) as Map);
    } catch (_) {
      return RefundPolicy.defaults;
    }
  }

  /// [raw] = the server's policy object, or null for "nothing configured"
  /// (204), which resets to the defaults.
  Future<RefundPolicy> apply(Map<dynamic, dynamic>? raw) async {
    final policy = raw == null ? RefundPolicy.defaults : RefundPolicy.fromJson(raw);
    if (raw == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, jsonEncode(policy.toJson()));
    }
    posLog('Refund policy: ${raw == null ? 'defaults' : jsonEncode(policy.toJson())}');
    _controller.add(policy);
    return policy;
  }

  /// Tenant switch: the old shop's policy must not govern the new one.
  Future<void> clear() async {
    await _prefs.remove(_key);
    _controller.add(RefundPolicy.defaults);
  }
}
