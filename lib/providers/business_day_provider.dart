import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/business_day_config.dart';
import '../services/z_rules.dart';
import 'database_providers.dart' show sharedPreferencesProvider;

const kBusinessDayConfigKey = 'business_day_config_json';

/// The tenant's business-day definition, cached so the till can compute its
/// zDay offline. Refreshed from `/pos/identity` at login and on every sync.
class BusinessDayNotifier extends StateNotifier<BusinessDayConfig> {
  final SharedPreferences _prefs;

  BusinessDayNotifier(this._prefs) : super(load(_prefs));

  static BusinessDayConfig load(SharedPreferences prefs) {
    final raw = prefs.getString(kBusinessDayConfigKey);
    if (raw == null) return BusinessDayConfig.empty;
    try {
      return BusinessDayConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return BusinessDayConfig.empty;
    }
  }

  Future<void> update(BusinessDayConfig config) async {
    await _prefs.setString(kBusinessDayConfigKey, jsonEncode(config.toJson()));
    state = config;
  }

  /// Today's business day on this till's clock.
  String currentZDay([DateTime? now]) =>
      zDayKeyOf(now ?? DateTime.now(), state.startHour);
}

final businessDayProvider =
    StateNotifierProvider<BusinessDayNotifier, BusinessDayConfig>((ref) {
  return BusinessDayNotifier(ref.watch(sharedPreferencesProvider));
});
