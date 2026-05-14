import 'dart:convert';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:desktop_updater/updater_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'database_providers.dart';

// SharedPreferences key for the testing override URL.
// Set this via the dev tools / a hidden setting to bypass the production URL.
// Example: prefs.setString('update_archive_url_override', 'http://localhost:9090/pos/app-archive.json')
const _kArchiveUrlOverrideKey = 'update_archive_url_override';

/// Derives the archive URL from [baseUrl] (which already ends with /api).
/// Strips the trailing /api segment so we get the bare server root, then
/// appends /pos/app-archive.json.
///
/// Examples:
///   https://app.caisse212.com/api  →  https://app.caisse212.com/pos/app-archive.json
///   http://localhost:9090/api       →  http://localhost:9090/pos/app-archive.json
String _deriveArchiveUrl(String baseUrl) {
  var root = baseUrl.trimRight();
  // Strip a trailing "/api" segment if present (the standard case).
  if (root.endsWith('/api')) {
    root = root.substring(0, root.length - 4);
  }
  return '$root/pos/app-archive.json';
}

/// Fetches the archive JSON and prints it for debugging.
/// Also pre-validates required top-level fields so we get a clear message
/// instead of a cryptic 'Null is not a subtype of String'.
Future<void> _debugFetchAndValidate(String url) async {
  try {
    debugPrint('[DesktopUpdater] Archive URL: $url');
    final response = await http.get(Uri.parse(url)).timeout(
      const Duration(seconds: 10),
    );
    debugPrint('[DesktopUpdater] HTTP ${response.statusCode}');
    if (response.statusCode != 200) {
      debugPrint('[DesktopUpdater] Non-200 response body: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
      return;
    }
    final raw = response.body;
    debugPrint('[DesktopUpdater] Raw JSON: $raw');

    // Parse and validate required fields.
    final Map<String, dynamic> json = jsonDecode(raw);
    final missing = <String>[];
    if (json['appName'] == null) missing.add('appName');
    if (json['description'] == null) missing.add('description');
    if (json['items'] == null) missing.add('items');
    if (missing.isNotEmpty) {
      debugPrint('[DesktopUpdater] ⚠️  Missing required top-level fields: $missing');
      debugPrint('[DesktopUpdater] Add these to your app-archive.json!');
    } else {
      debugPrint('[DesktopUpdater] ✅ Top-level fields OK');
    }

    final items = json['items'] as List? ?? [];
    for (int i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>? ?? {};
      final required = ['version', 'shortVersion', 'url', 'platform', 'date'];
      final itemMissing = required.where((k) => item[k] == null).toList();
      if (itemMissing.isNotEmpty) {
        debugPrint('[DesktopUpdater] ⚠️  item[$i] missing fields: $itemMissing');
      }
      // Check changes array items
      final changes = item['changes'] as List? ?? [];
      for (int j = 0; j < changes.length; j++) {
        final change = changes[j] as Map<String, dynamic>? ?? {};
        // desktop_updater expects "message" (not "title"/"description" in older versions)
        if (change['message'] == null) {
          debugPrint('[DesktopUpdater] ⚠️  item[$i].changes[$j] missing "message" field. Has: ${change.keys.toList()}');
        }
      }
    }
  } catch (e) {
    debugPrint('[DesktopUpdater] Pre-validation error: $e');
  }
}

/// Safe controller that swallows parse errors and logs them clearly.
class _SafeDesktopUpdaterController extends DesktopUpdaterController {
  final String rawArchiveUrl;

  _SafeDesktopUpdaterController({
    required Uri appArchiveUrl,
    required this.rawArchiveUrl,
    super.localization,
  }) : super(appArchiveUrl: appArchiveUrl);

  @override
  Future<void> checkVersion() async {
    // Pre-validate the JSON before the package tries to parse it.
    await _debugFetchAndValidate(rawArchiveUrl);
    try {
      await super.checkVersion();
    } catch (e) {
      debugPrint(
        '[DesktopUpdater] ❌ Version check failed: $e\n'
        '  → Check that app-archive.json has all required fields (see pre-validation log above).\n'
        '  → The app continues running — no update dialog will appear.',
      );
    }
  }
}

/// Provides a [DesktopUpdaterController] built from the stored server URL.
///
/// ## URL resolution order
/// 1. If `update_archive_url_override` is set in SharedPreferences → use it directly (testing mode).
/// 2. Otherwise derive from `api_base_url` by stripping the trailing `/api` and appending `/pos/app-archive.json`.
///
/// ## Testing mode
/// Run the app and before startup set via dart:
///   prefs.setString('update_archive_url_override', 'http://localhost:9090/pos/app-archive.json');
/// Or use the hidden dev setting in the Settings screen.
///
/// ## Required app-archive.json format
/// ```json
/// {
///   "appName": "CAISSE212",
///   "description": "POS Terminal Updates",
///   "items": [
///     {
///       "version": "1.0.1",
///       "shortVersion": 2,
///       "changes": [{"message": "Bug fixes"}],
///       "date": "2026-05-13",
///       "mandatory": false,
///       "url": "http://localhost:9090/updates/1.0.1-linux",
///       "platform": "linux"
///     }
///   ]
/// }
/// ```
final desktopUpdaterControllerProvider =
    Provider<DesktopUpdaterController?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);

  // Testing/override mode — use the exact URL stored in prefs.
  final overrideUrl = prefs.getString(_kArchiveUrlOverrideKey);

  String archiveUrlStr;
  if (overrideUrl != null && overrideUrl.isNotEmpty) {
    archiveUrlStr = overrideUrl;
    debugPrint('[DesktopUpdater] 🧪 Testing mode — using override URL: $archiveUrlStr');
  } else {
    final baseUrl = prefs.getString('api_base_url');
    if (baseUrl == null || baseUrl.isEmpty) return null;
    archiveUrlStr = _deriveArchiveUrl(baseUrl);
    debugPrint('[DesktopUpdater] Derived archive URL: $archiveUrlStr');
  }

  final archiveUri = Uri.tryParse(archiveUrlStr);
  if (archiveUri == null) {
    debugPrint('[DesktopUpdater] ❌ Invalid archive URL: $archiveUrlStr');
    return null;
  }

  return _SafeDesktopUpdaterController(
    appArchiveUrl: archiveUri,
    rawArchiveUrl: archiveUrlStr,
    localization: const DesktopUpdateLocalization(
      updateAvailableText: 'Mise à jour disponible',
      newVersionAvailableText: '{} {} est disponible',
      newVersionLongText:
          'Une nouvelle version est prête. Cliquez pour télécharger ({} MB).',
      restartText: 'Redémarrer pour mettre à jour',
      warningTitleText: 'Êtes-vous sûr ?',
      restartWarningText:
          'Un redémarrage est nécessaire pour terminer la mise à jour.\n'
          'Les modifications non sauvegardées seront perdues. Redémarrer maintenant ?',
      warningCancelText: 'Plus tard',
      warningConfirmText: 'Redémarrer',
    ),
  );
});

/// Provider that exposes read/write access to the testing-mode override URL.
final updateArchiveUrlOverrideProvider =
    StateNotifierProvider<_OverrideUrlNotifier, String?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return _OverrideUrlNotifier(prefs);
});

class _OverrideUrlNotifier extends StateNotifier<String?> {
  final dynamic _prefs;

  _OverrideUrlNotifier(this._prefs)
      : super(_prefs.getString(_kArchiveUrlOverrideKey) as String?);

  Future<void> setOverride(String url) async {
    await _prefs.setString(_kArchiveUrlOverrideKey, url);
    state = url;
  }

  Future<void> clearOverride() async {
    await _prefs.remove(_kArchiveUrlOverrideKey);
    state = null;
  }
}
