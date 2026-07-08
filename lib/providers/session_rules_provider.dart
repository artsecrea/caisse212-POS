import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/session_rules.dart';
import 'database_providers.dart' show sharedPreferencesProvider;

const _kSessionRulesKey = 'session_rules_json';

class SessionRulesNotifier extends StateNotifier<SessionRules> {
  final SharedPreferences _prefs;

  SessionRulesNotifier(this._prefs) : super(_load(_prefs));

  static SessionRules _load(SharedPreferences prefs) {
    final raw = prefs.getString(_kSessionRulesKey);
    if (raw == null) return SessionRules.empty;
    try {
      return SessionRules.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return SessionRules.empty;
    }
  }

  Future<void> updateRules(SessionRules rules) async {
    await _prefs.setString(_kSessionRulesKey, jsonEncode(rules.toJson()));
    state = rules;
  }

  Future<void> clearRules() async {
    await _prefs.remove(_kSessionRulesKey);
    state = SessionRules.empty;
  }
}

final sessionRulesProvider =
    StateNotifierProvider<SessionRulesNotifier, SessionRules>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SessionRulesNotifier(prefs);
});
