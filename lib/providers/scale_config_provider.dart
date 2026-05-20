import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/scale_config.dart';
import 'database_providers.dart' show sharedPreferencesProvider;

class ScaleConfigKeys {
  static const String scaleConfig = 'scale_config_json';
}

class ScaleConfigNotifier extends StateNotifier<ScaleConfig> {
  final SharedPreferences _prefs;

  ScaleConfigNotifier(this._prefs) : super(const ScaleConfig()) {
    _load();
  }

  void _load() {
    final raw = _prefs.getString(ScaleConfigKeys.scaleConfig);
    if (raw == null) return;
    try {
      state = ScaleConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt prefs — keep defaults.
    }
  }

  Future<void> save(ScaleConfig config) async {
    state = config;
    await _prefs.setString(ScaleConfigKeys.scaleConfig, jsonEncode(config.toJson()));
  }
}

final scaleConfigProvider =
    StateNotifierProvider<ScaleConfigNotifier, ScaleConfig>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ScaleConfigNotifier(prefs);
});

