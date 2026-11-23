/// Static config for the caisse212-updates service (Go, no BMS dependency).
class UpdateConfig {
  UpdateConfig._();

  /// SharedPrefs key for the app slug registered on the updates service.
  /// Configurable so one build can follow a different channel (e.g. a
  /// per-customer app) without a rebuild.
  static const String appSlugPrefKey = 'updates_app_slug';

  static const String defaultAppSlug = 'pos';

  /// SharedPrefs key holding an override of the updates service base URL.
  /// Empty or unset = [defaultBaseUrl].
  static const String baseUrlPrefKey = 'updates_base_url';

  static const String defaultBaseUrl = 'https://updates.caisse212.com';

  /// SharedPrefs key: epoch ms of the last check the server actually answered.
  static const String lastCheckPrefKey = 'updates_last_check_ms';

  /// Set once the saved URL override from older builds has been cleared, so
  /// every till lands on [defaultBaseUrl]; a technician can still override
  /// it again afterwards.
  static const String baseUrlBakedPrefKey = 'updates_base_url_baked_v1';

  /// Hours between automatic checks; 0 = only when someone asks.
  static const String checkHoursPrefKey = 'updates_check_hours';
  static const int defaultCheckHours = 24;
  static const List<int> checkHoursChoices = [0, 1, 6, 12, 24, 168];

  /// Off = an update downloaded earlier waits at startup instead of being
  /// installed before the till opens; it is then installed from the dialog.
  static const String installOnStartPrefKey = 'updates_install_on_start';

  /// Off = the optional-update dialog never opens by itself; the update is
  /// still offered from the Update button and Settings.
  static const String notifyPrefKey = 'updates_notify';

  /// kid → raw 32-byte ed25519 public key (std base64). Signing is optional
  /// since 2026-09-29 (owner accepted that the updates server/bucket is
  /// trusted as-is): a release signed with one of these keys must verify;
  /// unsigned or unknown-kid releases are accepted.
  // `dev-local` is the signer machine's dev key, harmless to keep pinned.
  static const Map<String, String> pinnedKeys = {
    'dev-local': 'adu+Pu1HztLYIrw/PeTeUETXYYQ2h2VoLC9yVqVlPnQ=',
  };

  /// A till asks the server once per [checkHoursPrefKey]. The timer ticks every
  /// [tickInterval] so a missed check (offline, failed download) is retried
  /// within the hour instead of waiting another day.
  static const Duration tickInterval = Duration(hours: 1);
  static const Duration tickJitter = Duration(minutes: 10);

  /// A staged update that failed to install this many times is thrown away
  /// and fetched again later, so a broken one can't loop the till forever.
  static const int maxApplyAttempts = 3;
}
