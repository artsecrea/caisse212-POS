import 'package:desktop_updater/desktop_updater.dart';
import 'package:desktop_updater/updater_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_providers.dart';

/// A safe subclass of [DesktopUpdaterController] that catches any errors thrown
/// during [checkVersion]. The base class calls checkVersion() unawaited inside
/// init(), so a malformed server response (e.g. null appName/description) would
/// otherwise crash the app with an unhandled async exception.
class _SafeDesktopUpdaterController extends DesktopUpdaterController {
  _SafeDesktopUpdaterController({
    required super.appArchiveUrl,
    super.localization,
  });

  @override
  Future<void> checkVersion() async {
    try {
      await super.checkVersion();
    } catch (e) {
      // Silently swallow – the app keeps running without the update dialog.
      // Common causes: server returns HTML/404, or app-archive.json is missing
      // the required "appName" or "description" fields.
      debugPrint('DesktopUpdater: version check failed (check app-archive.json): $e');
    }
  }
}

/// Provides a [DesktopUpdaterController] built from the stored server URL.
///
/// The server must expose:
///   GET <baseUrl>/pos/app-archive.json
/// (note: baseUrl already contains /api, so no extra /api prefix here)
///
/// Expected app-archive.json format:
/// {
///   "appName": "CAISSE212",        ← required, must not be null
///   "description": "Latest release", ← required, must not be null
///   "items": [
///     {
///       "version": "1.0.1",
///       "shortVersion": 2,
///       "changes": [{"message": "Bug fixes"}],
///       "date": "2026-04-22",
///       "mandatory": false,
///       "url": "<baseUrl>/updates/1.0.1-linux",
///       "platform": "linux"   // "windows" / "macos" / "linux"
///     }
///   ]
/// }
final desktopUpdaterControllerProvider =
    Provider<DesktopUpdaterController?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final baseUrl = prefs.getString('api_base_url');

  if (baseUrl == null || baseUrl.isEmpty) return null;

  // baseUrl already ends with /api (e.g. https://app.caisse212.com/api),
  // so we only append /pos/app-archive.json — not /api/pos/…
  final archiveUrl = Uri.tryParse('$baseUrl/pos/app-archive.json');
  if (archiveUrl == null) return null;

  return _SafeDesktopUpdaterController(
    appArchiveUrl: archiveUrl,
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





