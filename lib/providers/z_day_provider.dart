import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/z_day_state.dart';
import 'database_providers.dart' show sharedPreferencesProvider;

const kZDayStateKey = 'z_day_state_json';

/// Owns the terminal's [ZDayState]. Mirrors [SessionRulesNotifier]: one JSON
/// blob under a single prefs key, decoded defensively so a corrupt value can
/// never brick the login screen.
class ZDayNotifier extends StateNotifier<ZDayState> {
  final SharedPreferences _prefs;

  ZDayNotifier(this._prefs) : super(_load(_prefs));

  static ZDayState _load(SharedPreferences prefs) {
    final raw = prefs.getString(kZDayStateKey);
    if (raw == null) return ZDayState.empty;
    try {
      return ZDayState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return ZDayState.empty;
    }
  }

  Future<void> _persist(ZDayState next) async {
    await _prefs.setString(kZDayStateKey, jsonEncode(next.toJson()));
    state = next;
  }

  /// Roll the stored state onto [today] if the business day changed: bump the Z
  /// number and clear the closed flag. Idempotent — safe to call on every login
  /// attempt and every timer tick. Returns the (possibly unchanged) state.
  Future<ZDayState> ensureDay(String today) async {
    if (state.businessDay == today) return state;
    final next = ZDayState(
      businessDay: today,
      // First ever run starts at 1; every rollover after that increments.
      zNumber: state.zNumber + 1,
      closed: false,
    );
    await _persist(next);
    return next;
  }

  /// Mark [today] closed. Login is blocked from here until the day rolls over
  /// or a manager reopens.
  Future<void> markDayClosed({
    required String today,
    int? byUserId,
    String? byName,
    String? zCode,
  }) async {
    await _persist(state.copyWith(
      businessDay: today,
      // Preserve the number when it was never initialised (day lock switched on
      // mid-day), so the first Z of that day is #1 rather than #0.
      zNumber: state.zNumber == 0 ? 1 : state.zNumber,
      closed: true,
      closedAt: DateTime.now(),
      closedBy: byUserId,
      closedByName: byName,
      lastZCode: zCode,
    ));
  }

  /// Manager override: lift the lock without advancing the Z number, so the
  /// reopened day stays the same fiscal day.
  Future<void> reopenDay({required int byUserId}) async {
    await _persist(state.copyWith(
      closed: false,
      reopenedAt: DateTime.now(),
      reopenedBy: byUserId,
    ));
  }

  /// Wipe the day state — used when the terminal is re-provisioned, so a new
  /// install never inherits a lock it has no Z rows to explain.
  Future<void> reset() async {
    await _prefs.remove(kZDayStateKey);
    state = ZDayState.empty;
  }
}

final zDayStateProvider =
    StateNotifierProvider<ZDayNotifier, ZDayState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ZDayNotifier(prefs);
});
