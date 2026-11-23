import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/pos_log.dart';

/// The back office signed this till out (`force_kick`). Unlike an account
/// lock, sign-in is allowed again; the card only says why it happened.
class KickNotice {
  /// SUBSCRIPTION_ENDED | ACCOUNT_DISABLED | ADMIN_KICK | UPDATE_REQUIRED, or
  /// whatever newer code the server sends.
  final String code;
  final String? message;
  final DateTime at;

  const KickNotice({required this.code, this.message, required this.at});

  Map<String, dynamic> toJson() => {
        'code': code,
        if (message != null) 'message': message,
        'at': at.toUtc().toIso8601String(),
      };

  factory KickNotice.fromJson(Map<dynamic, dynamic> json) => KickNotice(
        code: '${json['code'] ?? 'ADMIN_KICK'}',
        message: json['message'] as String?,
        at: DateTime.tryParse('${json['at']}')?.toLocal() ?? DateTime.now(),
      );
}

/// Persists the kick so the reason is still on screen after a restart. Cleared
/// by the next successful terminal sign-in.
class KickStore {
  final SharedPreferences _prefs;
  KickStore(this._prefs);

  static const _key = 'pos_kick_notice_json';

  // Static, like AccountStatusStore: short-lived ApiService instances share
  // the prefs, so a per-instance stream would reach nobody.
  static final _controller = StreamController<KickNotice?>.broadcast();
  static Stream<KickNotice?> get changes => _controller.stream;

  KickNotice? get current {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return KickNotice.fromJson(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> record(KickNotice notice) async {
    await _prefs.setString(_key, jsonEncode(notice.toJson()));
    posLog('Kicked by the back office: ${notice.code} ${notice.message ?? ''}');
    _controller.add(notice);
  }

  Future<void> clear() async {
    if (_prefs.getString(_key) == null) return;
    await _prefs.remove(_key);
    _controller.add(null);
  }
}
