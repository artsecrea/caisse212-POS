import 'package:loggecrea/loggecrea.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// One-shot, non-blocking corrective backfill of the POS terminal's tenant &
/// business ids.
///
/// Background: early builds conflated `business_id` with `tenant_id` in local
/// storage (see the note in [ApiService]'s request interceptor), so some
/// installs scope/send data under the wrong business. This service asks the
/// server for the canonical ids for THIS terminal and rewrites the local prefs.
///
/// Design guarantees:
///  - **Non-blocking:** every path returns normally and all errors are
///    swallowed. Callers fire-and-forget; nothing here can stall startup/sync.
///  - **Guarded + idempotent:** once it applies a fix it sets a version flag and
///    never runs again. Bump [_kFlag] to force a re-run across all installs
///    after a future server-side correction ships.
///  - **Self-healing:** if offline / not logged in / server error, it does NOT
///    set the flag, so it simply retries on the next invocation.
class IdentityFixService {
  final ApiService _api;
  final SharedPreferences _prefs;
  final _logger = Logger.instance;

  IdentityFixService(this._api, this._prefs);

  /// Persisted "already fixed" flag. Bump the version suffix to re-run the
  /// backfill on every install after shipping a new correction.
  static const String _kFlag = 'identity_backfill_done_v1';

  Future<void> ensureIdentityBackfilled() async {
    try {
      if (_prefs.getBool(_kFlag) == true) return; // already fixed
      // Needs an authenticated, named terminal for the server to resolve us.
      if (_api.getAccessToken() == null) return; // not logged in yet
      if (_api.getPosName() == null) return; // terminal not configured

      final identity = await _api.fetchPosIdentity();
      if (identity == null) return; // non-200 / bad shape → retry next time

      final tenantId = _asInt(identity['tenantId']);
      final businessId = _asInt(identity['businessId']);
      // Nothing authoritative came back — don't lock the flag; retry later.
      if (tenantId == null && businessId == null) return;

      final beforeTenant = _api.getTenantId();
      final beforeBusiness = _api.getBusinessId();

      if (tenantId != null) await _api.setTenantId(tenantId);
      if (businessId != null) await _api.setBusinessId(businessId);

      await _prefs.setBool(_kFlag, true);
      _logger.info(
        'Identity backfill applied: tenant $beforeTenant->$tenantId, '
        'business $beforeBusiness->$businessId',
      );
    } catch (e) {
      // Never block startup / sync — just try again on the next cycle.
      _logger.warning('Identity backfill skipped: $e');
    }
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
