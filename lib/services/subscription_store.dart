import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/subscription_info.dart';
import '../utils/pos_log.dart';

/// Persists the last subscription the server told us about.
///
/// It arrives on several channels — login, token refresh, catalogue sync, the
/// daily check, an SSE push — and all of them funnel through [applyResponse] /
/// [apply], so the "when did we last hear" stamp is honest whichever one won.
class SubscriptionStore {
  final SharedPreferences _prefs;
  SubscriptionStore(this._prefs);

  static const _infoKey = 'pos_subscription_json';
  static const _checkedKey = 'pos_subscription_checked_ms';

  // Static for the same reason as the category scope stream: the login screens
  // build short-lived ApiService instances over the same prefs, and a
  // per-instance stream would announce to nobody.
  static final _controller = StreamController<SubscriptionInfo?>.broadcast();
  static Stream<SubscriptionInfo?> get changes => _controller.stream;

  SubscriptionInfo? get current {
    final raw = _prefs.getString(_infoKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return SubscriptionInfo.fromJson(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  DateTime? get lastCheckedAt {
    final ms = _prefs.getInt(_checkedKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get checkDue =>
      subscriptionCheckDue(current, lastCheckedAt, DateTime.now());

  /// Forget everything — on a tenant switch the old shop's renewal date must
  /// not greet the new one.
  Future<void> clear() async {
    await _prefs.remove(_infoKey);
    await _prefs.remove(_checkedKey);
    _controller.add(null);
  }

  /// Picks the subscription out of a login/refresh body: `posTerminal.subscription`
  /// first, then a top-level `subscription`.
  ///
  /// The key being ABSENT means an older server that knows nothing about
  /// subscriptions — keep what we have. Present-but-null means the server says
  /// there is nothing to track — clear it, so a stale warning cannot outlive
  /// the subscription it was about.
  Future<void> applyResponse(dynamic body) async {
    if (body is! Map) return;
    final terminal = body['posTerminal'];
    if (terminal is Map && terminal.containsKey('subscription')) {
      await apply(terminal['subscription']);
    } else if (body.containsKey('subscription')) {
      await apply(body['subscription']);
    }
  }

  /// Stores [raw] (a subscription object, or null to clear) and stamps the
  /// check time. A non-map, non-null value is ignored rather than trusted.
  Future<void> apply(dynamic raw) async {
    SubscriptionInfo? info;
    if (raw is Map) {
      info = SubscriptionInfo.fromJson(raw);
      await _prefs.setString(_infoKey, jsonEncode(info.toJson()));
    } else if (raw == null) {
      await _prefs.remove(_infoKey);
    } else {
      return;
    }
    await _prefs.setInt(_checkedKey, DateTime.now().millisecondsSinceEpoch);
    posLog('Subscription: ${info == null ? 'none' : '${info.status} until ${info.endsAt}'}');
    _controller.add(info);
  }
}
