import 'dart:convert';
import 'dart:io';
import 'package:desktop_updater/desktop_updater.dart';
import 'package:desktop_updater/updater_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'database_providers.dart';
import 'settings_provider.dart';

/// Flat static-manifest endpoint for the desktop builds. Each platform reads
/// `{base}/{platform}-archive.json` (e.g. `windows-archive.json`).
///
/// This replaces the old tenant-derived URL (`{api_base_url}/pos/app-archive.json`)
/// so the update channel no longer touches the backend at all — you just push
/// new files into a bucket / CDN. Change the host below when you wire the
/// real production domain.
///
/// **Windows is the primary supported target.** Linux / macOS get their own
/// archive files at the same base URL but aren't actively maintained yet.
const String _kDesktopUpdateBaseUrl = 'https://update.caisse212.com';

// SharedPreferences key for the testing override URL.
// Set this via the dev tools / a hidden setting to bypass the production URL.
// Example: prefs.setString('update_archive_url_override', 'http://localhost:9090/pos/app-archive.json')
const _kArchiveUrlOverrideKey = 'update_archive_url_override';

/// Returns the static archive URL for the host platform, or `null` on
/// platforms where desktop updates don't apply (Android, iOS, web, unknown).
String? _archiveUrlForCurrentPlatform() {
  if (kIsWeb) return null;
  if (Platform.isWindows) return '$_kDesktopUpdateBaseUrl/windows-archive.json';
  if (Platform.isLinux) return '$_kDesktopUpdateBaseUrl/linux-archive.json';
  if (Platform.isMacOS) return '$_kDesktopUpdateBaseUrl/macos-archive.json';
  return null;
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

/// Provides a [DesktopUpdaterController] pointed at the flat per-platform
/// archive manifest. No tenant backend involvement — just a static file on a
/// CDN / bucket.
///
/// ## URL resolution order
/// 1. If `update_archive_url_override` is set in SharedPreferences → use it
///    directly (testing mode, e.g. a local server).
/// 2. Otherwise hit `$_kDesktopUpdateBaseUrl/{platform}-archive.json` via
///    [_archiveUrlForCurrentPlatform].
///
/// On non-desktop platforms (Android/iOS/web) this returns `null` — the
/// caller in `main.dart` already gates on `Platform.isWindows/MacOS/Linux`.
///
/// ## Testing mode
/// Before startup, in code:
///   `prefs.setString('update_archive_url_override', 'http://localhost:9090/windows-archive.json')`
/// Or use the hidden dev setting in the Settings screen.
///
/// ## Required {platform}-archive.json format
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
///       "url": "https://update.caisse212.com/builds/1.0.1-windows.zip",
///       "platform": "windows"
///     }
///   ]
/// }
/// ```
final desktopUpdaterControllerProvider =
    Provider<DesktopUpdaterController?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  // Rebuild when the app language changes so the desktop-updater overlay
  // text tracks the rest of the UI (en/ar/fr).
  final lang = ref.watch(settingsProvider.select((s) => s.language));

  // Testing/override mode — use the exact URL stored in prefs.
  final overrideUrl = prefs.getString(_kArchiveUrlOverrideKey);

  String archiveUrlStr;
  if (overrideUrl != null && overrideUrl.isNotEmpty) {
    archiveUrlStr = overrideUrl;
    debugPrint('[DesktopUpdater] 🧪 Testing mode — using override URL: $archiveUrlStr');
  } else {
    final url = _archiveUrlForCurrentPlatform();
    if (url == null) {
      debugPrint('[DesktopUpdater] No archive URL for this platform');
      return null;
    }
    archiveUrlStr = url;
    debugPrint('[DesktopUpdater] Archive URL: $archiveUrlStr');
  }

  final archiveUri = Uri.tryParse(archiveUrlStr);
  if (archiveUri == null) {
    debugPrint('[DesktopUpdater] ❌ Invalid archive URL: $archiveUrlStr');
    return null;
  }

  return _SafeDesktopUpdaterController(
    appArchiveUrl: archiveUri,
    rawArchiveUrl: archiveUrlStr,
    localization: _localizationFor(lang),
  );
});

/// Build the desktop_updater plugin's overlay strings for the requested
/// app language. Falls back to English for any unknown locale.
DesktopUpdateLocalization _localizationFor(String lang) {
  switch (lang) {
    case 'ar':
      return const DesktopUpdateLocalization(
        updateAvailableText: 'تحديث متاح',
        newVersionAvailableText: '{} {} متاح',
        newVersionLongText:
            'إصدار جديد جاهز. انقر للتنزيل ({} ميغابايت).',
        restartText: 'أعد التشغيل للتحديث',
        warningTitleText: 'هل أنت متأكد؟',
        restartWarningText:
            'تحتاج إلى إعادة تشغيل لإكمال التحديث.\n'
            'ستفقد التغييرات غير المحفوظة. هل تعيد التشغيل الآن؟',
        warningCancelText: 'لاحقا',
        warningConfirmText: 'إعادة التشغيل',
      );
    case 'fr':
      return const DesktopUpdateLocalization(
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
      );
    case 'en':
    default:
      return const DesktopUpdateLocalization(
        updateAvailableText: 'Update available',
        newVersionAvailableText: '{} {} is available',
        newVersionLongText:
            'A new version is ready. Tap to download ({} MB).',
        restartText: 'Restart to update',
        warningTitleText: 'Are you sure?',
        restartWarningText:
            'A restart is required to finish the update.\n'
            'Unsaved changes will be lost. Restart now?',
        warningCancelText: 'Later',
        warningConfirmText: 'Restart',
      );
  }
}

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
