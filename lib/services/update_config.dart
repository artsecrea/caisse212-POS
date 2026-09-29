/// Static config for the caisse212-updates service (Go, no BMS dependency).
class UpdateConfig {
  UpdateConfig._();

  /// SharedPrefs key for the app slug registered on the updates service.
  /// Configurable so one build can follow a different channel (e.g. a
  /// per-customer app) without a rebuild.
  static const String appSlugPrefKey = 'updates_app_slug';

  static const String defaultAppSlug = 'pos';

  /// SharedPrefs key holding the updates service base URL (e.g.
  /// `https://updates.example.com`). Configurable because the production host
  /// isn't decided yet; empty = update checks are disabled.
  static const String baseUrlPrefKey = 'updates_base_url';

  static const String defaultBaseUrl = '';

  /// kid → raw 32-byte ed25519 public key (std base64). Signing is optional
  /// since 2026-09-29 (owner accepted that the updates server/bucket is
  /// trusted as-is): a release signed with one of these keys must verify;
  /// unsigned or unknown-kid releases are accepted.
  // `dev-local` is the signer machine's dev key, harmless to keep pinned.
  static const Map<String, String> pinnedKeys = {
    'dev-local': 'adu+Pu1HztLYIrw/PeTeUETXYYQ2h2VoLC9yVqVlPnQ=',
  };

  static const Duration pollInterval = Duration(hours: 6);
  static const Duration pollJitter = Duration(minutes: 30);
}
