import 'dart:async';
import '../domain/models/serial_conflict.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/booking_models.dart';
import '../utils/pos_log.dart';

/// Sentinel that distinguishes "field omitted → leave unchanged" from an
/// explicit `null` ("unassign") in [ApiService.patchSchedule].
class _Unset {
  const _Unset();
}

const _unset = _Unset();

/// API Service for handling all server communication
/// Per-record outcome of `POST /pos/refunds/bulk`.
///
/// Outcomes are keyed by refund `code`, never by array position — the contract
/// is explicit that the response identifies records by code, and a positional
/// match would silently mis-assign every outcome if the server ever reorders or
/// omits one.
class RefundSyncResult {
  /// Newly created server-side.
  final Set<String> created;

  /// The server already had this code. Also a success: our re-send was
  /// idempotent, which is exactly what should happen after a timeout retry.
  final Set<String> skipped;

  /// code -> the server's own error text. Deterministic rejections
  /// (over-refund, unknown order, bad method) — never worth an automatic retry.
  final Map<String, String> failed;

  const RefundSyncResult({
    this.created = const {},
    this.skipped = const {},
    this.failed = const {},
  });

  /// Every code the server accepted, one way or the other.
  Set<String> get accepted => {...created, ...skipped};

  factory RefundSyncResult.fromJson(Map<String, dynamic> json,
      {required List<String> sentCodes}) {
    Set<String> codesOf(String key) {
      final raw = json[key];
      if (raw is List) {
        return raw
            .map((e) => e is Map ? (e['code'] ?? '').toString() : e.toString())
            .where((c) => c.isNotEmpty)
            .toSet();
      }
      return <String>{};
    }

    final failed = <String, String>{};
    final rawFailed = json['failed'];
    if (rawFailed is List) {
      for (final f in rawFailed) {
        if (f is Map) {
          final code = (f['code'] ?? '').toString();
          if (code.isNotEmpty) {
            failed[code] = (f['error'] ?? 'Rejected by server').toString();
          }
        }
      }
    }

    final created = codesOf('created');
    final skipped = codesOf('skipped');

    // Older servers answer with only `{message, count}` and no per-record
    // arrays. A 200 there means the whole batch went through, which is the
    // behaviour this client relied on before — so treat everything sent as
    // created rather than silently marking nothing as synced.
    if (created.isEmpty && skipped.isEmpty && failed.isEmpty) {
      return RefundSyncResult(created: sentCodes.toSet());
    }

    return RefundSyncResult(
        created: created, skipped: skipped, failed: failed);
  }
}

/// A failure from the till-side catalogue endpoints.
///
/// The distinction that matters to the UI: a **403** means this role lacks
/// `pos:catalog` and the entry points should disappear, while a plan-limit
/// rejection is a message the operator must read **verbatim** — it names their
/// subscription cap, and paraphrasing it turns an actionable message into a
/// mystery.
class PosCatalogException implements Exception {
  final int? statusCode;

  /// The server's own words. Shown as-is.
  final String message;

  PosCatalogException(this.message, {this.statusCode});

  bool get isForbidden => statusCode == 403;

  factory PosCatalogException.fromDio(DioException e) {
    final data = e.response?.data;
    String? serverMessage;
    if (data is Map) {
      // Bean-validation 400s say message:"Validation failed" and put the real
      // reasons in `details` — see _serverMessage in utils/error_text.dart.
      final details = data['details'];
      if (details is Map && details.isNotEmpty) {
        final reasons = details.entries
            .map((entry) => entry.value?.toString().trim() ?? '')
            .where((v) => v.isNotEmpty)
            .toList();
        if (reasons.isNotEmpty) serverMessage = reasons.join(' · ');
      }
      serverMessage ??= (data['message'] ?? data['error'])?.toString();
    } else if (data is String && data.trim().isNotEmpty) {
      serverMessage = data;
    }
    return PosCatalogException(
      serverMessage?.trim().isNotEmpty == true
          ? serverMessage!.trim()
          : (e.message ?? 'Request failed'),
      statusCode: e.response?.statusCode,
    );
  }

  @override
  String toString() => message;
}

class ApiService {
  late final Dio _dio;
  final SharedPreferences _prefs;

  static const String _accessTokenKey = 'server_access_token';
  static const String _refreshTokenKey = 'server_refresh_token';
  static const String _accessExpiresAtMsKey = 'server_access_expires_at_ms';
  // Refresh-token expiry (the whole session's death time). Not returned by the
  // server today, so we DECODE it from the refresh JWT's `exp` claim.
  static const String _refreshExpiresAtMsKey = 'server_refresh_expires_at_ms';
  // Tenant/terminal username — persisted separately so it survives a token
  // wipe (force-logout) and can prefill the re-auth dialog.
  static const String _usernameKey = 'server_username';
  static const String _posNameKey = 'pos_name';
  // Stable per-install fallback identity, minted once. See [terminalTag].
  static const String _terminalTagKey = 'terminal_tag';
  static const String _posIdKey = 'pos_terminal_id';
  static const String _baseUrlKey = 'api_base_url';
  static const String _tenantIdKey = 'tenant_id';
  static const String _businessIdKey = 'business_id';
  static const String _isDemoModeKey = 'is_demo_mode';
  static const String _businessNameKey = 'business_name';
  static const String _businessLogoKey = 'business_logo';
  // Per-terminal category scope (posTerminal.categoryIds from login/refresh).
  static const String _categoryScopeKey = 'pos_category_scope';

  // In-memory access-token expiry (loaded from prefs on startup).
  DateTime? _accessExpiresAt;
  // In-memory refresh-token (session) expiry — decoded from the refresh JWT.
  DateTime? _refreshExpiresAt;

  // Single-flight refresh: if a refresh is in progress all callers wait for
  // the same Completer rather than firing parallel refresh requests.
  Completer<void>? _refreshCompleter;

  // Broadcast stream that fires when the refresh token is definitively
  // rejected (4xx from /pos/refresh). Subscribers navigate to login.
  final _forceLogoutController = StreamController<void>.broadcast();
  Stream<void> get forceLogoutStream => _forceLogoutController.stream;

  // Broadcast stream that fires whenever the server hands us a new per-terminal
  // category scope (login / token refresh). null means "show every category".
  //
  // Static on purpose: the login screens build their own short-lived
  // ApiService over the same SharedPreferences, so a per-instance stream would
  // announce the scope to nobody. Every instance shares this one.
  static final _categoryScopeController =
      StreamController<List<int>?>.broadcast();
  Stream<List<int>?> get categoryScopeStream => _categoryScopeController.stream;

  // Public getter for Dio instance (for testing/debugging)
  Dio get dio => _dio;

  ApiService(this._prefs) {
    // Restore persisted expiry into memory so pre-emptive refresh works
    // after an app restart without needing a fresh login.
    final storedMs = _prefs.getInt(_accessExpiresAtMsKey);
    if (storedMs != null) {
      _accessExpiresAt = DateTime.fromMillisecondsSinceEpoch(storedMs);
    }
    // Refresh (session) expiry: prefer the stored value; else decode it from
    // the refresh JWT we already hold (covers installs from before this field
    // existed, and never needs a server round-trip).
    final refreshMs = _prefs.getInt(_refreshExpiresAtMsKey);
    if (refreshMs != null) {
      _refreshExpiresAt = DateTime.fromMillisecondsSinceEpoch(refreshMs);
    } else {
      final rt = _prefs.getString(_refreshTokenKey);
      final exp = _jwtExpiry(rt);
      if (exp != null) {
        _refreshExpiresAt = exp;
        _prefs.setInt(_refreshExpiresAtMsKey, exp.millisecondsSinceEpoch);
      }
    }
    // Backfill the username from the token if it was never persisted (terminals
    // logged in before this field existed), so the re-auth dialog can prefill
    // it even after a token wipe.
    if (_prefs.getString(_usernameKey) == null) {
      final u = _jwtClaim(_prefs.getString(_accessTokenKey), 'username') ??
          _jwtClaim(_prefs.getString(_refreshTokenKey), 'username');
      if (u is String && u.isNotEmpty) _prefs.setString(_usernameKey, u);
    }
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Add base URL. NOTE: the stored `api_base_url` already ends in `/api`
        // and we append ANOTHER `/api` here on purpose — the backend runs with
        // servlet context-path `/api` AND controllers mapped at `/api/pos/...`,
        // so the real external path is `/api/api/pos/...`. Verified 2026-07-27:
        // `/api/api/pos/stations` reaches the controller; `/api/pos/...` 404s as
        // a static resource. Do NOT "normalize" the double `/api` away.
        final savedBaseUrl = _prefs.getString(_baseUrlKey);
        if (savedBaseUrl != null && savedBaseUrl.isNotEmpty && !options.path.startsWith('http')) {
          final baseUrl = '$savedBaseUrl/api';
          options.path = '$baseUrl${options.path}';
        }

        // Pre-emptive token refresh: if the access token expires within 60 s,
        // refresh now so the request goes out with a fresh token.
        // Skip for auth endpoints and for requests that are themselves a retry.
        final isAuthEndpoint = options.path.contains('/pos/login') ||
            options.path.contains('/pos/refresh') ||
            options.path.contains('/pos/logout');
        final isRetry = options.extra['_retried'] == true;

        if (!isAuthEndpoint && !isRetry) {
          final exp = _accessExpiresAt;
          if (exp != null &&
              DateTime.now().isAfter(exp.subtract(const Duration(seconds: 60)))) {
            try {
              await _doRefresh();
            } catch (_) {
              // Pre-emptive refresh failed (network error). Let the request
              // proceed anyway; if the token is truly dead the server returns
              // 401 and the onError handler will retry.
            }
          }
        }

        // Add authorization token
        final token = getAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        // Add POS name header
        final posName = getPosName();
        if (posName != null) {
          options.headers['X-POS-Name'] = posName;
        }

        // Add POS terminal ID header
        final posId = getPosId();
        if (posId != null) {
          options.headers['X-POS-Id'] = posId.toString();
        }

        // Add tenant ID header
        final tenantId = getTenantId();
        if (tenantId != null) {
          options.headers['X-Tenant-ID'] = tenantId.toString();
        }

        // X-Business-Id on every request.
        //
        // The contract now asks for this globally (today only the queue
        // endpoints read it; the rest resolve business from X-POS-Name), so it
        // is sent ahead of the server features that will need it.
        //
        // It is sent ONLY from [getBusinessId] — the real `posTerminal.
        // businessId` captured at login. This header used to be omitted
        // deliberately because an earlier version sent the TENANT id here, which
        // the server rejects with 403 "Business does not belong to the current
        // tenant". Never fall back to the tenant id: no header is safe, a wrong
        // one breaks every call.
        final businessId = getBusinessId();
        if (businessId != null) {
          options.headers['X-Business-Id'] = businessId.toString();
        }

        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode != 401) {
          return handler.next(error);
        }

        // Don't refresh for auth endpoints or if we already retried once.
        final path = error.requestOptions.path;
        final isAuthEndpoint = path.contains('/pos/login') ||
            path.contains('/pos/refresh') ||
            path.contains('/pos/logout');
        if (isAuthEndpoint || error.requestOptions.extra['_retried'] == true) {
          return handler.next(error);
        }

        try {
          // Single-flight: if another 401 is already refreshing, wait for it.
          await _doRefresh();

          // Retry the original request once with the new access token.
          final retryOpts = error.requestOptions;
          retryOpts.headers['Authorization'] = 'Bearer ${getAccessToken()}';
          retryOpts.extra['_retried'] = true;
          final response = await _dio.fetch(retryOpts);
          return handler.resolve(response);
        } on DioException catch (e) {
          // Only force-logout when the server explicitly rejected the refresh
          // token (4xx). Network errors while offline mean "retry later".
          if (e.response != null &&
              e.response!.statusCode! >= 400 &&
              e.response!.statusCode! < 500) {
            await _handleForceLogout();
          }
          return handler.next(error);
        } catch (_) {
          return handler.next(error);
        }
      },
    ));
  }

  // ── Refresh token flow ───────────────────────────────────────────────────

  /// Single-flight internal refresh. All concurrent callers await the same
  /// Completer so only one `POST /pos/refresh` is ever in flight at a time.
  Future<void> _doRefresh() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<void>();
    try {
      final refreshToken = _prefs.getString(_refreshTokenKey);
      if (refreshToken == null) throw Exception('No refresh token stored');

      final response = await _dio.post(
        '/pos/refresh',
        data: {'refreshToken': refreshToken},
        // Mark so the onRequest interceptor skips the pre-emptive check.
        options: Options(extra: {'_retried': true}),
      );

      final data = response.data as Map<String, dynamic>;
      await _saveTokenPair(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        expiresInMs: (data['expiresIn'] as num).toInt(),
      );
      // A scope edited in the BMS reaches the till here — refresh is the only
      // channel that carries it (the catalogue sync does not).
      await applyCategoryScope(data['posTerminal']);
      _refreshCompleter!.complete();
    } catch (e) {
      _refreshCompleter!.completeError(e);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Pulls the terminal's own info — today just the category scope — by
  /// rotating the token pair early.
  ///
  /// `posTerminal.categoryIds` rides ONLY on login and refresh; the catalogue
  /// sync never carries it. Without this, an admin hiding a category in the BMS
  /// would not reach a till that stays signed in all day until its access token
  /// happened to expire. The Update button calls this so "hide a category, hit
  /// Update" does what the person pressing it expects.
  ///
  /// Safe to call on a whim: this is the same single-flight refresh the
  /// interceptor uses, and a failure here is never a logout — only the
  /// interceptor's 401 path force-logs-out, and only on an explicit 4xx.
  /// Returns false if the refresh could not be done (offline, no token yet).
  Future<bool> refreshTerminalInfo() async {
    try {
      await _doRefresh();
      return true;
    } catch (e) {
      posLog('Terminal info refresh skipped: $e');
      return false;
    }
  }

  Future<void> _saveTokenPair({
    required String accessToken,
    required String refreshToken,
    required int expiresInMs,
  }) async {
    await _prefs.setString(_accessTokenKey, accessToken);
    await _prefs.setString(_refreshTokenKey, refreshToken);
    final expiresAt = DateTime.now().add(Duration(milliseconds: expiresInMs));
    await _prefs.setInt(_accessExpiresAtMsKey, expiresAt.millisecondsSinceEpoch);
    _accessExpiresAt = expiresAt;

    // Session (refresh) expiry — decoded straight from the refresh JWT's `exp`,
    // since the server doesn't return it. Rotation moves this forward on every
    // refresh, so an active terminal's session death keeps sliding out.
    final refreshExp = _jwtExpiry(refreshToken);
    if (refreshExp != null) {
      _refreshExpiresAt = refreshExp;
      await _prefs.setInt(
          _refreshExpiresAtMsKey, refreshExp.millisecondsSinceEpoch);
    }
    // Persist the username (from the JWT) so the re-auth dialog can prefill it
    // even after tokens are wiped.
    final username = _jwtClaim(accessToken, 'username');
    if (username != null) await _prefs.setString(_usernameKey, username);
  }

  /// The `exp` claim of a JWT as a local [DateTime], or null if the token is
  /// missing/malformed. Only READS the payload (no signature verification —
  /// used purely for client-side expiry timing; the server still validates).
  static DateTime? _jwtExpiry(String? token) {
    final exp = _jwtClaim(token, 'exp');
    final secs = exp is int ? exp : int.tryParse('${exp ?? ''}');
    if (secs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  }

  /// Reads a single claim from a JWT payload (base64url-decoded middle segment).
  static dynamic _jwtClaim(String? token, String claim) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      var seg = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      seg = seg.padRight(seg.length + (4 - seg.length % 4) % 4, '=');
      final json = jsonDecode(utf8.decode(base64.decode(seg)))
          as Map<String, dynamic>;
      return json[claim];
    } catch (_) {
      return null;
    }
  }

  /// Called when the server explicitly rejects the refresh token (4xx).
  /// Clears auth tokens and signals the UI to show the login screen.
  Future<void> _handleForceLogout() async {
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_refreshTokenKey);
    await _prefs.remove(_accessExpiresAtMsKey);
    await _prefs.remove(_refreshExpiresAtMsKey);
    _accessExpiresAt = null;
    _refreshExpiresAt = null;
    if (!_forceLogoutController.isClosed) {
      _forceLogoutController.add(null);
    }
  }

  /// The refresh-token (session) expiry, or null if unknown.
  DateTime? getRefreshExpiresAt() => _refreshExpiresAt;

  /// Something short and stable that identifies THIS terminal, for codes that
  /// have to differ between tills.
  ///
  /// Prefers the POS name, then the terminal id. Falls back to a random token
  /// minted once and kept: a till whose name was never set would otherwise
  /// contribute nothing at all to a code, and two such tills refunding in the
  /// same second would produce identical ones. Rare, and exactly the terminals
  /// least likely to have been set up carefully.
  String terminalTag() {
    final name = _prefs.getString(_posNameKey);
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final id = _prefs.getInt(_posIdKey);
    if (id != null) return 'T$id';
    final existing = _prefs.getString(_terminalTagKey);
    if (existing != null && existing.isNotEmpty) return existing;
    // Minted from the clock rather than a random source: it only has to be
    // unlikely to coincide with another install, and it is kept forever after.
    final minted =
        'X${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    _prefs.setString(_terminalTagKey, minted);
    return minted;
  }

  /// The tenant/terminal username. Prefers the persisted value (which survives
  /// a token wipe); falls back to decoding it from the access/refresh JWT we
  /// still hold — covering terminals logged in before this was persisted.
  String? getUsername() {
    final stored = _prefs.getString(_usernameKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final fromToken =
        _jwtClaim(_prefs.getString(_accessTokenKey), 'username') ??
            _jwtClaim(_prefs.getString(_refreshTokenKey), 'username');
    return fromToken is String ? fromToken : null;
  }

  /// True when the session (refresh token) is expired, or within [lead] of it —
  /// the signal to force a re-login. False when we don't know the expiry (never
  /// nag on missing data) or the user isn't logged in.
  bool isReauthDue({Duration lead = const Duration(hours: 24)}) {
    if (_prefs.getString(_refreshTokenKey) == null &&
        _prefs.getString(_accessTokenKey) == null) {
      return false; // logged out entirely — the login screen handles that
    }
    final exp = _refreshExpiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp.subtract(lead));
  }

  // Getters for stored values
  String? getAccessToken() => _prefs.getString(_accessTokenKey);
  String? getPosName() => _prefs.getString(_posNameKey);
  int? getPosId() => _prefs.getInt(_posIdKey);
  int? getTenantId() => _prefs.getInt(_tenantIdKey);
  int? getBusinessId() => _prefs.getInt(_businessIdKey);
  String? getBaseUrl() => _prefs.getString(_baseUrlKey);
  bool isDemoMode() => _prefs.getBool(_isDemoModeKey) ?? false;
  String? getBusinessName() => _prefs.getString(_businessNameKey);
  String? getBusinessLogo() => _prefs.getString(_businessLogoKey);

  // Setters for stored values
  Future<void> setAccessToken(String token) async {
    await _prefs.setString(_accessTokenKey, token);
  }

  Future<void> setPosName(String name) async {
    await _prefs.setString(_posNameKey, name);
  }

  Future<void> setPosId(int id) async {
    await _prefs.setInt(_posIdKey, id);
  }

  Future<void> setTenantId(int id) async {
    await _prefs.setInt(_tenantIdKey, id);
  }

  Future<void> setBusinessId(int id) async {
    await _prefs.setInt(_businessIdKey, id);
  }

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(_baseUrlKey, url);
  }

  Future<void> setDemoMode(bool isDemoMode) async {
    await _prefs.setBool(_isDemoModeKey, isDemoMode);
  }

  Future<void> setBusinessName(String name) async {
    await _prefs.setString(_businessNameKey, name);
  }

  Future<void> setBusinessLogo(String base64Logo) async {
    await _prefs.setString(_businessLogoKey, base64Logo);
  }

  /// The categories this terminal is allowed to show, in the order the server
  /// wants them on the grid. null = no scope = show everything.
  List<int>? get categoryScope {
    final raw = _prefs.getStringList(_categoryScopeKey);
    if (raw == null || raw.isEmpty) return null;
    final ids = raw.map(int.tryParse).whereType<int>().toList();
    return ids.isEmpty ? null : ids;
  }

  /// Stores `posTerminal.categoryIds` from a login/refresh response.
  ///
  /// No terminal object at all (`"posTerminal": null`, which refresh returns
  /// when the request carried no `X-POS-Name`, or when the terminal was renamed
  /// or unassigned) carries no information about the scope, so the stored one
  /// is left alone.
  ///
  /// A terminal object WITHOUT the field is different: the server serializes
  /// nulls explicitly, so a cleared scope always arrives as
  /// `"categoryIds": null`. Absence therefore means the server has no scope
  /// feature at all — an older or rolled-back build — and the right answer is
  /// to show everything rather than keep hiding categories forever on the
  /// strength of a scope nobody can clear any more.
  ///
  /// An empty array is never sent (the write endpoint 400s on one), so an empty
  /// or unparseable list is read as "no scope" rather than blanking the grid.
  Future<void> applyCategoryScope(dynamic posTerminal) async {
    if (posTerminal is! Map) return;
    final raw = posTerminal['categoryIds'];
    List<int>? ids;
    if (raw is List) {
      final parsed = raw
          .map((e) => e is int ? e : int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
      if (parsed.isNotEmpty) ids = parsed;
    }
    if (ids == null) {
      await _prefs.remove(_categoryScopeKey);
    } else {
      await _prefs.setStringList(
          _categoryScopeKey, ids.map((e) => e.toString()).toList());
    }
    posLog('Category scope: ${ids ?? 'all categories'}');
    _categoryScopeController.add(ids);
  }

  /// Clear all authentication data
  Future<void> clearAuthData() async {
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_refreshTokenKey);
    await _prefs.remove(_accessExpiresAtMsKey);
    _accessExpiresAt = null;
    await _prefs.remove(_posNameKey);
    await _prefs.remove(_posIdKey);
    await _prefs.remove(_tenantIdKey);
    await _prefs.remove(_businessIdKey);
    await _prefs.remove(_baseUrlKey);
    await _prefs.remove(_isDemoModeKey);
    await _prefs.remove(_businessNameKey);
    await _prefs.remove(_businessLogoKey);
    await _prefs.remove(_categoryScopeKey);
    _categoryScopeController.add(null);
    // NOTE: We do NOT remove 'tenant_password_hash' here - it should only be cleared on full logout
  }

  /// Clear ALL data including tenant password hash (for full logout)
  Future<void> clearAllAuthData() async {
    await clearAuthData();
    await _prefs.remove('tenant_password_hash');
  }

  /// Login to the server with username, password, and POS name
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    required String posName,
  }) async {
    try {
      final response = await _dio.post('/pos/login', data: {
        'username': username,
        'posName': posName,
        'password': password,
        'supportsRefresh': true,
      }, options: Options(headers: {'X-POS-Name': posName}));

      if (response.statusCode == 200) {
        final data = response.data;

        // Save access token (and refresh token + expiry if the server sent them).
        await setAccessToken(data['accessToken']);
        if (data['refreshToken'] != null && data['expiresIn'] != null) {
          await _saveTokenPair(
            accessToken: data['accessToken'] as String,
            refreshToken: data['refreshToken'] as String,
            expiresInMs: (data['expiresIn'] as num).toInt(),
          );
        }
        await setPosName(posName);

        // Handle tenant_id - it might come as String or int from server
        if (data['user'] != null && data['user']['tenantId'] != null) {
          final tenantId = data['user']['tenantId'];
          if (tenantId is int) {
            await setTenantId(tenantId);
          } else if (tenantId is String) {
            await setTenantId(int.parse(tenantId));
          }
        }

        // Save POS terminal ID from posTerminal data
        if (data['posTerminal'] != null && data['posTerminal']['id'] != null) {
          final raw = data['posTerminal']['id'];
          final id = raw is int ? raw : int.tryParse(raw.toString());
          if (id != null) await setPosId(id);
        }

        // Save business ID from posTerminal data
        if (data['posTerminal'] != null && data['posTerminal']['businessId'] != null) {
          final raw = data['posTerminal']['businessId'];
          final id = raw is int ? raw : int.tryParse(raw.toString());
          if (id != null) await setBusinessId(id);
        }

        // Save business name from posTerminal data
        if (data['posTerminal'] != null && data['posTerminal']['businessName'] != null) {
          final businessName = data['posTerminal']['businessName'] as String;
          await setBusinessName(businessName);
          posLog('Business name saved: $businessName');
        }

        // Save business logo from posTerminal data (byte array -> base64 string)
        if (data['posTerminal'] != null && data['posTerminal']['businessLogo'] != null) {
          try {
            final logoData = data['posTerminal']['businessLogo'];
            String base64Logo;
            if (logoData is String) {
              // Already a base64 string - use as-is
              base64Logo = logoData;
            } else if (logoData is List) {
              // Byte array from server (may contain signed values from Java: -128 to 127)
              final bytes = logoData.map<int>((e) => (e as int) & 0xFF).toList();
              base64Logo = base64Encode(Uint8List.fromList(bytes));
            } else {
              throw Exception('Unexpected logo data type: ${logoData.runtimeType}');
            }
            await setBusinessLogo(base64Logo);
            posLog('Business logo saved (${base64Logo.length} chars)');
          } catch (e) {
            posLog('Failed to save business logo: $e');
          }
        }

        // Per-terminal category scope — which categories this till may show.
        await applyCategoryScope(data['posTerminal']);

        return data;
      } else {
        throw Exception('Login failed: ${response.statusMessage}');
      }
    } on DioException catch (e) {
      posLog('Login DioException caught: ${e.type}');
      posLog('Login error details: ${e.error}');

      // Handle server response errors (4xx, 5xx)
      if (e.response != null) {
        posLog('Server response status: ${e.response?.statusCode}');
        posLog('Server response data: ${e.response?.data}');

        String errorMessage = 'Unknown error';

        // Try to extract error message from response
        if (e.response?.data is Map) {
          final responseData = e.response?.data as Map;
          errorMessage = responseData['message']?.toString() ??
                        responseData['error']?.toString() ??
                        'Server error: ${e.response?.statusCode}';
        } else if (e.response?.data is String) {
          errorMessage = e.response?.data as String;
        } else {
          errorMessage = e.message ?? 'Server error: ${e.response?.statusCode}';
        }

        throw Exception('Login failed: $errorMessage');
      }

      // Provide specific error messages based on error type
      String errorMsg;
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
          errorMsg = 'Connection timeout. Server took too long to respond.';
          break;
        case DioExceptionType.sendTimeout:
          errorMsg = 'Send timeout. Failed to send request to server.';
          break;
        case DioExceptionType.receiveTimeout:
          errorMsg = 'Receive timeout. Server took too long to respond.';
          break;
        case DioExceptionType.connectionError:
          errorMsg = 'Connection error. Cannot connect to server at ${e.requestOptions.uri.host}:${e.requestOptions.uri.port}. Please check if the server is running.';
          break;
        case DioExceptionType.badCertificate:
          errorMsg = 'SSL certificate error. The server certificate is invalid.';
          break;
        case DioExceptionType.cancel:
          errorMsg = 'Request was cancelled.';
          break;
        default:
          // For unknown errors, check if it's a type cast error
          if (e.error.toString().contains('is not a subtype')) {
            errorMsg = 'Data format error: ${e.error}. Please contact support.';
          } else {
            errorMsg = e.message ?? 'Connection failed. Server might be offline or URL is incorrect. Please verify: ${e.requestOptions.uri}';
          }
      }

      throw Exception('Network error: $errorMsg');
    } catch (e) {
      posLog('Login general error: $e');
      throw Exception('Login error: ${e.toString()}');
    }
  }

  /// Logout from the server
  Future<void> logout() async {
    // Skip API call in demo mode
    if (isDemoMode()) {
      posLog('Logout (demo mode)');
      return;
    }

    try {
      final posName = getPosName();
      final accessToken = getAccessToken();

      // Only call API if we have credentials
      if (posName == null || accessToken == null) {
        posLog('Logout: No credentials found, skipping API call');
        return;
      }

      posLog('Logout: Calling /logout API for POS: $posName');

      final response = await _dio.post(
        '/pos/logout',
        options: Options(
          headers: {
            'X-POS-Name': posName,
            'Authorization': 'Bearer $accessToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        posLog('Logout: Successfully logged out from server');
      } else {
        posLog('Logout: Server returned status ${response.statusCode}');
      }
    } on DioException catch (e) {
      // Log error but don't throw - logout should succeed locally even if server call fails
      posLog('Logout API error: ${e.type}');
      posLog('Logout error message: ${e.message}');
      posLog('Logout error response: ${e.response?.data}');

      // Don't throw exception - we still want to clear local data
      posLog('Logout: Continuing with local logout despite server error');
    } catch (e) {
      posLog('Logout general error: $e');
      // Don't throw exception - we still want to clear local data
      posLog('Logout: Continuing with local logout despite error');
    }
  }

  /// Pull a page of order deltas from the server. Returns the raw response
  /// envelope: `{changes: List<Map>, nextCursor: String, hasMore: bool}`.
  /// Cursor is **opaque** — pass back exactly what the previous response
  /// gave you. Omit for a backfill from the beginning.
  Future<Map<String, dynamic>> fetchOrderDeltas({
    String? cursor,
    int limit = 200,
  }) async {
    try {
      final r = await _dio.get(
        '/pos/sync/orders',
        queryParameters: {
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          'limit': limit,
        },
      );
      if (r.statusCode == 200) {
        return Map<String, dynamic>.from(r.data as Map);
      }
      throw Exception('Failed to fetch order deltas (${r.statusCode})');
    } on DioException catch (e) {
      throw Exception(
          'Network error: ${e.message ?? 'Failed to fetch order deltas. Check connection.'}');
    } catch (e) {
      throw Exception('Error fetching order deltas: ${e.toString()}');
    }
  }

  /// Pull a page of payment (ticket) deltas. Same envelope as
  /// [fetchOrderDeltas]; items keyed by (orderCode, ticketNumber).
  Future<Map<String, dynamic>> fetchPaymentDeltas({
    String? cursor,
    int limit = 200,
  }) async {
    try {
      final r = await _dio.get(
        '/pos/sync/payments',
        queryParameters: {
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          'limit': limit,
        },
      );
      if (r.statusCode == 200) {
        return Map<String, dynamic>.from(r.data as Map);
      }
      throw Exception('Failed to fetch payment deltas (${r.statusCode})');
    } on DioException catch (e) {
      throw Exception(
          'Network error: ${e.message ?? 'Failed to fetch payment deltas. Check connection.'}');
    } catch (e) {
      throw Exception('Error fetching payment deltas: ${e.toString()}');
    }
  }

  /// Fetch categories from server
  /// Fetch the authoritative tenant & business identity for THIS POS terminal.
  ///
  /// Read-only and idempotent. The server must resolve the terminal from the
  /// auth token + `X-POS-Name` header (added by the interceptor) and must NOT
  /// trust the `X-Tenant-ID` header — that value may be stale/wrong on the very
  /// installs this call exists to repair.
  ///
  /// Backend contract — `GET /pos/identity` → 200:
  /// ```json
  /// { "tenantId": <int>, "businessId": <int>,
  ///   "businessName": "<string?>" }
  /// ```
  /// Returns the decoded map, or null on any non-200 / unexpected shape so the
  /// caller can safely retry later.
  Future<Map<String, dynamic>?> fetchPosIdentity() async {
    final response = await _dio.get('/pos/identity');
    if (response.statusCode == 200 && response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    try {
      final response = await _dio.get('/pos/categories');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch categories');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching categories: ${e.toString()}');
    }
  }

  /// Fetch products from server
  Future<List<Map<String, dynamic>>> fetchProducts() async {
    try {
      final response = await _dio.get('/pos/products');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch products');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching products: ${e.toString()}');
    }
  }

  /// `GET /pos/serials` — every serial of the tenant, sold or not.
  ///
  /// Sold rows are returned too (they arrive with `isAvailable: false`) and are
  /// deliberately kept: a reprint or a refund needs to name the unit that left.
  /// Pulled with the catalogue, because a unit sold on another terminal is gone
  /// and the picker must not still offer it.
  Future<List<Map<String, dynamic>>> fetchSerials({int? productId}) async {
    try {
      final response = await _dio.get(
        '/pos/serials',
        queryParameters: productId == null ? null : {'productId': productId},
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch serials');
    } on DioException catch (e) {
      throw Exception(
          'Network error: ${e.message ?? 'Failed to fetch serials. Check connection.'}');
    } catch (e) {
      throw Exception('Error fetching serials: ${e.toString()}');
    }
  }

  /// `GET /pos/serials/lookup?number=` — one serial by its printed number.
  ///
  /// Returns null on 404 (unknown serial). Only an online nicety: the local
  /// cache answers scans offline, so callers must treat a failure here as
  /// "cache is the answer", never as "serial invalid".
  Future<Map<String, dynamic>?> lookupSerial(String number) async {
    try {
      final response = await _dio.get('/pos/serials/lookup',
          queryParameters: {'number': number});
      if (response.statusCode == 200 && response.data != null) {
        return Map<String, dynamic>.from(response.data);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// `POST /pos/products` — create a product from the till.
  ///
  /// Deliberately thin: the server owns every default (TVA, stock behaviour,
  /// active flags) and stamps tenant + business from `X-POS-Name`, so those must
  /// never be sent from here. It also runs the plan's product cap, which is why
  /// the till cannot just insert locally and sync later.
  ///
  /// Returns the raw envelope so the caller can tell `created: true` from
  /// `created: false` (barcode already existed — a success, not an error) and
  /// persist the returned rows through the normal sync path.
  ///
  /// Exactly one of [categoryId] / [categoryName] may be given; sending both is
  /// a 400 by contract, so it is refused here rather than round-tripped.
  Future<Map<String, dynamic>> createPosProduct({
    required String name,
    required double price,
    String? barcode,
    int? categoryId,
    String? categoryName,
  }) async {
    if (categoryId != null &&
        categoryName != null &&
        categoryName.trim().isNotEmpty) {
      throw ArgumentError(
          'Pass categoryId or categoryName, never both (the server 400s)');
    }
    try {
      final response = await _dio.post('/pos/products', data: {
        'name': name.trim(),
        'price': price,
        if (barcode != null && barcode.trim().isNotEmpty)
          'barcode': barcode.trim(),
        if (categoryId != null) 'categoryId': categoryId,
        if (categoryId == null &&
            categoryName != null &&
            categoryName.trim().isNotEmpty)
          'categoryName': categoryName.trim(),
      });
      final data = response.data;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on DioException catch (e) {
      throw PosCatalogException.fromDio(e);
    }
  }

  /// `POST /pos/categories` — find-or-create by name, case-insensitive.
  Future<Map<String, dynamic>> createPosCategory(String name) async {
    try {
      final response =
          await _dio.post('/pos/categories', data: {'name': name.trim()});
      final data = response.data;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on DioException catch (e) {
      throw PosCatalogException.fromDio(e);
    }
  }

  // ── Agenda / Booking ────────────────────────────────────────────────────

  /// `GET /order-products/availability` — the real free slots for booking a
  /// time-managed [productId] on [date] (already accounts for hours, staff
  /// time-off, existing bookings and resource capacity). Online-only.
  ///
  /// Requires the `X-Business-Id` header, which the default interceptor omits by
  /// design — so we set it explicitly here (mirrors the SSE subscribe fix).
  Future<AvailabilityResponse> getAvailability({
    required int productId,
    required DateTime date,
    int? waiterId,
    int? resourceId,
  }) async {
    final businessId = getBusinessId();
    final dateStr = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    try {
      final query = {
        'productId': productId,
        'date': dateStr,
        if (waiterId != null) 'waiterId': waiterId,
        if (resourceId != null) 'resourceId': resourceId,
      };
      final options = Options(headers: {
        if (businessId != null) 'X-Business-Id': businessId,
      });

      Response<dynamic> response;
      try {
        response = await _dio.get('/pos/availability',
            queryParameters: query, options: options);
      } on DioException catch (e) {
        // A backend from before the endpoint moved under /pos still answers on
        // the old path. Terminals and servers update on their own schedules, so
        // fall back rather than making booking depend on the deploy order.
        if (e.response?.statusCode != 404) rethrow;
        response = await _dio.get('/order-products/availability',
            queryParameters: query, options: options);
      }
      if (response.statusCode == 200) {
        return AvailabilityResponse.fromJson(
            Map<String, dynamic>.from(response.data as Map));
      }
      throw Exception('Failed to fetch availability');
    } on DioException catch (e) {
      // 400 = product not bookable yet (no duration configured) or missing
      // business context — surface the server's message so the UI can explain.
      if (e.response?.statusCode == 400 && e.response?.data is Map) {
        final m = Map<String, dynamic>.from(e.response!.data as Map);
        throw Exception(
            (m['message'] ?? m['error'] ?? 'Product is not bookable yet')
                .toString());
      }
      throw Exception('Network error: ${e.message ?? 'availability'}');
    }
  }

  /// `PATCH /order-products/{id}/schedule` — (re)schedule / (re)assign a booking.
  /// Partial: only fields you pass change. Times go up as explicit UTC.
  /// [planWaiterId] / [planResourceId] use a sentinel so `null` explicitly
  /// UNASSIGNS and omitting leaves it unchanged (per the spec).
  ///
  /// Throws [ScheduleConflict] on `409` (waiter/resource conflict) and
  /// [ScheduleValidationError] on `400` (bad range / unparseable).
  Future<void> patchSchedule(
    int orderProductId, {
    DateTime? planStartAt,
    DateTime? planEndAt,
    Object? planWaiterId = _unset,
    Object? planResourceId = _unset,
  }) async {
    final data = <String, dynamic>{};
    if (planStartAt != null) {
      data['planStartAt'] = planStartAt.toUtc().toIso8601String();
    }
    if (planEndAt != null) {
      data['planEndAt'] = planEndAt.toUtc().toIso8601String();
    }
    if (!identical(planWaiterId, _unset)) data['planWaiterId'] = planWaiterId;
    if (!identical(planResourceId, _unset)) {
      data['planResourceId'] = planResourceId;
    }
    try {
      await _dio.patch('/order-products/$orderProductId/schedule', data: data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      if (status == 409) {
        throw ScheduleConflict.fromJson(
            body is Map ? Map<String, dynamic>.from(body) : const {});
      }
      if (status == 400) {
        final msg = (body is Map
                ? (body['message'] ?? body['error'])
                : null)
            ?.toString();
        throw ScheduleValidationError(msg ?? 'Invalid schedule (check the time range)');
      }
      rethrow;
    }
  }

  /// `DELETE /order-products/{id}/schedule` — unbook the line and free the
  /// slot. Online-only like the rest of the booking calls: the slot belongs to
  /// the server, and a queued release would hold a chair hostage until the
  /// terminal happened to reconnect.
  Future<void> deleteSchedule(int orderProductId) async {
    try {
      await _dio.delete('/order-products/$orderProductId/schedule');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Already unscheduled server-side — the caller wanted it gone and it is.
      if (status == 404) return;
      if (status == 400) {
        final body = e.response?.data;
        final msg =
            (body is Map ? (body['message'] ?? body['error']) : null)?.toString();
        throw ScheduleValidationError(msg ?? 'Cannot unschedule this line');
      }
      rethrow;
    }
  }

  /// `GET /pos/providers` — bookable staff (barbers/stylists). Same offline
  /// login shape as `/kds-profiles`. Best-effort like [fetchResources]: an
  /// older backend without the endpoint must not fail the whole master sync.
  Future<List<Map<String, dynamic>>> fetchProviders() async {
    try {
      final response = await _dio.get('/pos/providers');
      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// `GET /pos/agenda` — every booking **overlapping**
  /// `[startDate 00:00, endDate+1 00:00)`.
  ///
  /// Overlap, not start-in-window: a cut that begins at 23:30 and runs past
  /// midnight belongs to both days, and asking for either must return it.
  ///
  /// The `timeStatus` the server sends is deliberately dropped — it is derived
  /// from the clock and stale on arrival. Callers compute it as they paint,
  /// see [bookingTimeStatus].
  Future<AgendaPage> fetchAgenda({
    required DateTime startDate,
    required DateTime endDate,
    int? waiterId,
    int? resourceId,
  }) async {
    final businessId = getBusinessId();
    try {
      final response = await _dio.get(
        '/pos/agenda',
        queryParameters: {
          'startDate': _isoDate(startDate),
          'endDate': _isoDate(endDate),
          if (waiterId != null) 'waiterId': waiterId,
          if (resourceId != null) 'resourceId': resourceId,
        },
        options: Options(headers: {
          if (businessId != null) 'X-Business-Id': businessId,
        }),
      );
      if (response.statusCode != 200) return AgendaPage.empty;
      return AgendaPage.fromResponse(response.data);
    } on DioException {
      rethrow;
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Fetch bookable resources (rooms/chairs/equipment) from the server.
  /// Best-effort: this is an optional/new endpoint, so a 404 or any network
  /// error yields an empty list rather than failing the whole master sync.
  Future<List<Map<String, dynamic>>> fetchResources() async {
    try {
      final response = await _dio.get('/pos/resources');
      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Fetch components from server
  Future<List<Map<String, dynamic>>> fetchComponents() async {
    try {
      final response = await _dio.get('/pos/components');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch components');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching components: ${e.toString()}');
    }
  }

  /// Fetch component groups from server
  Future<List<Map<String, dynamic>>> fetchComponentGroups() async {
    try {
      final response = await _dio.get('/pos/component-groups');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch component groups');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching component groups: ${e.toString()}');
    }
  }

  /// Fetch product components from server
  Future<List<Map<String, dynamic>>> fetchProductComponents() async {
    try {
      final response = await _dio.get('/pos/product-components');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch product components');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching components: ${e.toString()}');
    }
  }

  /// Fetch the per-product component group rule overrides.
  ///
  /// Only products that override something appear, and the values are already
  /// merged with the group defaults by the server, so a row here is the
  /// effective rule and everything absent simply follows its group.
  ///
  /// A 404 is not an error: this endpoint is newer than the POS builds in the
  /// field, and a server without it just means nobody has overridden anything.
  /// Anything else still throws — a broken sync should be visible.
  Future<List<Map<String, dynamic>>> fetchProductComponentGroups() async {
    try {
      final response = await _dio.get('/pos/product-component-groups');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch product component groups');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const [];
      throw Exception('Network error: ${e.message ?? 'Failed to fetch product component groups. Check connection.'}');
    } catch (e) {
      throw Exception('Error fetching product component groups: ${e.toString()}');
    }
  }

  /// Fetch all product variants from server
  Future<List<Map<String, dynamic>>> fetchVariants() async {
    try {
      final response = await _dio.get('/pos/variants');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch variants');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching variants: ${e.toString()}');
    }
  }

  /// Fetch variants for a specific product
  Future<List<Map<String, dynamic>>> fetchProductVariants(int productId) async {
    try {
      final response = await _dio.get('/pos/products/$productId/variants');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch product variants');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching product variants: ${e.toString()}');
    }
  }

  /// Fetch areas from server
  Future<List<Map<String, dynamic>>> fetchAreas() async {
    try {
      final response = await _dio.get('/pos/areas');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch areas');
    } on DioException {
      rethrow;
    }
  }

  /// Fetch tables from server
  Future<List<Map<String, dynamic>>> fetchTables() async {
    try {
      final response = await _dio.get('/pos/tables');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch tables');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching tables: ${e.toString()}');
    }
  }

  /// Fetch users from server
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    try {
      final response = await _dio.get('/pos/users');
      // (Removed a leftover debug print that dumped the whole users payload —
      // bcrypt password hashes included — to the console on every sync.)
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch users');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching users: ${e.toString()}');
    }
  }

  /// Fetch payment methods from server
  Future<List<Map<String, dynamic>>> fetchPaymentMethods() async {
    try {
      final response = await _dio.get('/pos/payment-methods');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch payment methods');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching payment methods: ${e.toString()}');
    }
  }

  /// Fetch commercials from server
  Future<List<Map<String, dynamic>>> fetchCommercials() async {
    try {
      final response = await _dio.get('/pos/commercials');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch commercials');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching commercials: ${e.toString()}');
    }
  }

  /// Fetch coupons from server
  Future<List<Map<String, dynamic>>> fetchCoupons() async {
    try {
      final response = await _dio.get('/pos/coupons');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch coupons');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching coupons: ${e.toString()}');
    }
  }

  /// Fetch stations from server
  Future<List<Map<String, dynamic>>> fetchStations() async {
    try {
      final response = await _dio.get('/pos/stations');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch stations');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching stations: ${e.toString()}');
    }
  }

  /// Fetch customers from server
  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    try {
      final response = await _dio.get('/pos/customers');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch customers');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching customers: ${e.toString()}');
    }
  }

  /// Fetch waiters from server
  Future<List<Map<String, dynamic>>> fetchWaiters() async {
    try {
      final response = await _dio.get('/pos/waiters');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch waiters');
    } on DioException {
      rethrow;
    } catch (e) {
      throw Exception('Error fetching waiters: ${e.toString()}');
    }
  }

  /// Fetch a single order by code from server
  Future<Map<String, dynamic>> fetchOrderByCode(String orderCode) async {
    try {
      final response = await _dio.get('/pos/orders/$orderCode');
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Failed to fetch order');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception('Order not found');
      }
      throw Exception('Network error: ${e.message ?? 'Failed to fetch order. Check connection.'}');
    } catch (e) {
      throw Exception('Error fetching order: ${e.toString()}');
    }
  }

  // ============ SYNC DATA TO SERVER ============

  /// Sync orders to server (bulk)
  /// Throws if the server does not return a 2xx status.
  /// Push a batch of orders. Returns any serial links the server refused —
  /// the orders themselves still saved, so this is not an error path.
  Future<List<SerialConflictReport>> syncOrders(
      List<Map<String, dynamic>> orders) async {
    try {
      final response = await _dio.post('/pos/orders/bulk', data: {"orders": orders});
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for bulk orders sync');
      }
      return SerialConflictReport.listFrom(response.data);
    } on DioException catch (e) {
      throw Exception('Failed to sync orders: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing orders: ${e.toString()}');
    }
  }

  /// Sync a single order to server using PUT (creates or updates)
  /// Throws if the server does not return a 2xx status.
  /// Push one order. Same conflict contract as the bulk path, so a batch of
  /// one behaves identically to a batch of two.
  Future<List<SerialConflictReport>> syncSingleOrder(
      String orderCode, Map<String, dynamic> orderData) async {
    try {
      final response = await _dio.put('/pos/orders/$orderCode', data: orderData);
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for order $orderCode sync');
      }
      return SerialConflictReport.listFrom(response.data);
    } on DioException catch (e) {
      throw Exception('Failed to sync order: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing order: ${e.toString()}');
    }
  }

  /// Sync tickets to server
  /// Throws if the server does not return a 2xx status.
  Future<void> syncTickets(List<Map<String, dynamic>> tickets) async {
    try {
      final response = await _dio.post('/pos/tickets/bulk', data: {"tickets":tickets});
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for bulk tickets sync');
      }
    } on DioException catch (e) {
      throw Exception('Failed to sync tickets: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing tickets: ${e.toString()}');
    }
  }

  /// Sync sessions to server
  /// Throws if the server does not return a 2xx status.
  Future<void> syncSessions(List<Map<String, dynamic>> sessions) async {
    try {
      final response = await _dio.post('/pos/cash-sessions/bulk', data: {"sessions" : sessions});
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for bulk sessions sync');
      }
    } on DioException catch (e) {
      throw Exception('Failed to sync sessions: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing sessions: ${e.toString()}');
    }
  }

  /// Sync customers to server (new customers created locally).
  ///
  /// Throws if the server does not return a 2xx status. Returns the
  /// `mappings` array the new backend sends with each canonical id
  /// (`[{localId, serverId, phoneNormalized}]`), or an empty list on older
  /// backends that don't include one. The caller uses the list to renumber
  /// local rows so the dedup-by-phone feature can activate without a
  /// coordinated client release.
  Future<List<Map<String, dynamic>>> syncCustomers(
      List<Map<String, dynamic>> customers) async {
    try {
      final response = await _dio
          .post('/pos/customers/bulk', data: {"customers": customers});
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw Exception(
            'Server returned status ${response.statusCode} for bulk customers sync');
      }
      final body = response.data;
      if (body is Map && body['mappings'] is List) {
        return List<Map<String, dynamic>>.from(
          (body['mappings'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m)),
        );
      }
      return const <Map<String, dynamic>>[];
    } on DioException catch (e) {
      throw Exception(
          'Failed to sync customers: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing customers: ${e.toString()}');
    }
  }

  /// Check server connection
  Future<bool> checkConnection() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ========== DELETE OPERATIONS ==========

  /// Delete an order from server by order code
  Future<void> deleteOrder(String orderCode) async {
    try {
      await _dio.delete('/pos/orders/$orderCode');
    } on DioException catch (e) {
      throw Exception('Failed to delete order: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error deleting order: ${e.toString()}');
    }
  }

  /// Delete a ticket from server by order code and ticket num
  Future<void> deleteTicket(String orderCode, String ticketNum) async {
    try {
      await _dio.delete('/pos/tickets/$orderCode/$ticketNum');
    } on DioException catch (e) {
      throw Exception('Failed to delete ticket: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error deleting ticket: ${e.toString()}');
    }
  }

  /// Delete an order product from server
  Future<void> deleteOrderProduct(int serverId) async {
    try {
      await _dio.delete('/pos/order-products/$serverId');
    } on DioException catch (e) {
      throw Exception('Failed to delete order product: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error deleting order product: ${e.toString()}');
    }
  }

  // ========== UPDATE OPERATIONS ==========

  /// Update an order on server by order code
  Future<void> updateOrder(String orderCode, Map<String, dynamic> updateData) async {
    try {
      await _dio.put('/pos/orders/$orderCode', data: updateData);
    } on DioException catch (e) {
      throw Exception('Failed to update order: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error updating order: ${e.toString()}');
    }
  }

  /// Update a ticket on server by order code and ticket num
  Future<void> updateTicket(String orderCode, String ticketNum, Map<String, dynamic> updateData) async {
    try {
      await _dio.put('/pos/tickets/$orderCode/$ticketNum', data: updateData);
    } on DioException catch (e) {
      throw Exception('Failed to update ticket: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error updating ticket: ${e.toString()}');
    }
  }

  /// Update an order product on server
  Future<void> updateOrderProduct(int serverId, Map<String, dynamic> updateData) async {
    try {
      await _dio.put('/pos/order-products/$serverId', data: updateData);
    } on DioException catch (e) {
      throw Exception('Failed to update order product: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error updating order product: ${e.toString()}');
    }
  }

  // ========== SESSION OPERATIONS ==========

  /// Sync a single session to server using PUT (creates or updates)

  // ========== ISSUE REPORTING ==========

  /// Submit an issue report to the server
  Future<void> submitIssue({
    required String title,
    required String type,
    String? description,
    String? ipAddress,
    int? userId,
  }) async {
    try {
      final posName = getPosName();
      final data = {
        'ipAddress': ipAddress,
        'userId': userId,
        'source': posName ?? 'Unknown POS',
        'type': type,
        'title': title,
        'description': description,
        'status': 'OPEN',
      };

      await _dio.post('/pos/issues', data: data);
    } on DioException catch (e) {
      throw Exception('Failed to submit issue: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error submitting issue: ${e.toString()}');
    }
  }

  // ========== SESSION OPERATIONS (continued) ==========
  Future<void> syncSingleSession(String sessionCode, Map<String, dynamic> sessionData) async {
    try {
      final response = await _dio.put('/pos/cash-sessions/$sessionCode', data: sessionData);
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for session $sessionCode sync');
      }
    } on DioException catch (e) {
      throw Exception('Failed to sync session: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing session: ${e.toString()}');
    }
  }

  /// Delete a session from server by session code
  Future<void> deleteSession(String sessionCode) async {
    try {
      await _dio.delete('/pos/cash-sessions/$sessionCode');
    } on DioException catch (e) {
      throw Exception('Failed to delete session: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error deleting session: ${e.toString()}');
    }
  }

  /// Update a session on server by session code
  Future<void> updateSession(String sessionCode, Map<String, dynamic> updateData) async {
    try {
      await _dio.put('/pos/cash-sessions/$sessionCode', data: updateData);
    } on DioException catch (e) {
      throw Exception('Failed to update session: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error updating session: ${e.toString()}');
    }
  }

  // ── Z (shift) sync ─────────────────────────────────────────────────────────
  // Terminal is identified by the auto-injected X-Pos-Id header; the server
  // enforces one OPEN Z per POS (see docs/Z_TRACKING_API.md).

  /// Bulk upsert Z rows. POST /pos/z/bulk {"zs": [...]}.
  /// Bulk-upsert Zs. POST /pos/z/bulk.
  ///
  /// Throws [ZAlreadyOpenException] on 409 — the terminal already has a
  /// different open Z server-side and the response body IS that Z. The caller
  /// adopts it rather than retrying, since a retry can only conflict again.
  Future<void> syncZs(List<Map<String, dynamic>> zs) async {
    try {
      final response = await _dio.post('/pos/z/bulk', data: {"zs": zs});
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for bulk Z sync');
      }
    } on DioException catch (e) {
      final conflict = _openZConflict(e);
      if (conflict != null) throw ZAlreadyOpenException(conflict);
      throw Exception('Failed to sync Z: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      if (e is ZAlreadyOpenException) rethrow;
      throw Exception('Error syncing Z: ${e.toString()}');
    }
  }

  /// Upsert a single Z by code. PUT /pos/z/{code}.
  /// Throws [ZAlreadyOpenException] on 409 — see [syncZs].
  Future<void> syncSingleZ(String zCode, Map<String, dynamic> zData) async {
    try {
      final response = await _dio.put('/pos/z/$zCode', data: zData);
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for Z $zCode sync');
      }
    } on DioException catch (e) {
      final conflict = _openZConflict(e);
      if (conflict != null) throw ZAlreadyOpenException(conflict);
      throw Exception('Failed to sync Z: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      if (e is ZAlreadyOpenException) rethrow;
      throw Exception('Error syncing Z: ${e.toString()}');
    }
  }

  /// The already-open Z carried in a 409 body, or null if this wasn't that.
  Map<String, dynamic>? _openZConflict(DioException e) {
    if (e.response?.statusCode != 409) return null;
    final data = e.response?.data;
    if (data is Map && data['code'] != null) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  /// Z history, newest first. GET /pos/z?status=&limit=
  Future<List<Map<String, dynamic>>> fetchZs({
    String? status,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get('/pos/z', queryParameters: {
        if (status != null) 'status': status,
        'limit': limit,
      });
      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data as List);
      }
      return const [];
    } catch (_) {
      return const []; // history is informational — never break a screen for it
    }
  }

  /// One Z by code, or null on 404. GET /pos/z/{code}.
  Future<Map<String, dynamic>?> fetchZByCode(String zCode) async {
    try {
      final response = await _dio.get(
        '/pos/z/$zCode',
        options: Options(validateStatus: (c) => c != null && c < 500),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The cash sessions belonging to a Z. GET /pos/z/{code}/sessions.
  Future<List<Map<String, dynamic>>> fetchZSessions(String zCode) async {
    try {
      final response = await _dio.get(
        '/pos/z/$zCode/sessions',
        options: Options(validateStatus: (c) => c != null && c < 500),
      );
      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data as List);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// One cash session by code (includes the resolved Z linkage), or null on
  /// 404. GET /pos/cash-sessions/{code}.
  Future<Map<String, dynamic>?> fetchCashSession(String sessionCode) async {
    try {
      final response = await _dio.get(
        '/pos/cash-sessions/$sessionCode',
        options: Options(validateStatus: (c) => c != null && c < 500),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Refunds ────────────────────────────────────────────────────────────────

  /// Push refunds. POST /pos/refunds/bulk.
  ///
  /// Each refund's `code` is the idempotency key — re-sending one the server
  /// already has is a documented no-op, so a retry after a timeout is safe.
  ///
  /// Returns a per-record outcome. The endpoint answers **200 even when some
  /// records were refused**, so treating any 200 as total success would mark a
  /// rejected refund as synced and lose it silently — money handed back with no
  /// server record and nothing on screen to say so.
  Future<RefundSyncResult> syncRefunds(List<Map<String, dynamic>> refunds) async {
    try {
      final response =
          await _dio.post('/pos/refunds/bulk', data: {"refunds": refunds});
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw Exception(
            'Server returned status ${response.statusCode} for bulk refund sync');
      }
      final sentCodes =
          refunds.map((r) => (r['code'] ?? '').toString()).toList();
      return RefundSyncResult.fromJson(
          response.data is Map ? Map<String, dynamic>.from(response.data) : {},
          sentCodes: sentCodes);
    } on DioException catch (e) {
      throw Exception(
          'Failed to sync refunds: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing refunds: ${e.toString()}');
    }
  }

  /// Refunds the server holds for an order. GET /pos/refunds?orderCode=...
  Future<List<Map<String, dynamic>>> fetchRefunds(String orderCode) async {
    try {
      final response = await _dio.get(
        '/pos/refunds',
        queryParameters: {'orderCode': orderCode},
        options: Options(validateStatus: (c) => c != null && c < 500),
      );
      if (response.statusCode == 200 && response.data is List) {
        return List<Map<String, dynamic>>.from(response.data as List);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Tell the backend the kitchen has finished an order, so it can forward the
  /// ready call to the delivery platform (Glovo `ready_for_pickup`, Kooul
  /// `ready`). POST /pos/orders/{code}/ready.
  ///
  /// This is a **signal, not a state change**: `status` is untouched, only
  /// `deliveryStatus` advances. It is idempotent server-side, ignored on
  /// cancelled orders, and deliberately has **no offline queue** — the platform
  /// only cares in the moment, so a signal that couldn't be delivered while the
  /// courier was waiting is worthless later.
  ///
  /// Returns true when the platform was signalled. `false` on 404 (the order
  /// hasn't been synced yet — sync it, then signal) and on any network error.
  Future<bool> signalOrderReady(String orderCode) async {
    try {
      final response = await _dio.post(
        '/pos/orders/$orderCode/ready',
        options: Options(validateStatus: (c) => c != null && c < 500),
      );
      if (response.statusCode == 404) return false;
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
    } catch (_) {
      return false;
    }
  }

  /// The open Z for THIS terminal on the server, or null (404 = none open).
  /// GET /pos/z/open. Used to avoid opening a duplicate Z.
  Future<Map<String, dynamic>?> fetchOpenZ() async {
    try {
      final response = await _dio.get(
        '/pos/z/open',
        options: Options(validateStatus: (c) => c != null && c < 500),
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return null;
    } on DioException catch (_) {
      return null; // best-effort; local uniqueness still applies
    } catch (_) {
      return null;
    }
  }

  /// Delete a Z by code. DELETE /pos/z/{code}.
  Future<void> deleteZ(String zCode) async {
    try {
      await _dio.delete('/pos/z/$zCode');
    } on DioException catch (e) {
      throw Exception('Failed to delete Z: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error deleting Z: ${e.toString()}');
    }
  }

  // ── External Order Queue ───────────────────────────────────────────────────

  /// Per-request options for the external-queue endpoints.
  ///
  /// The interceptor now sends X-Business-Id on every request, so this is
  /// belt-and-braces: these routes are the ones that genuinely 500 with
  /// "No business context" without it, so they assert it explicitly rather than
  /// depending on the global default staying in place.
  Options? _queueOptions() {
    final businessId = getBusinessId();
    if (businessId == null) return null;
    return Options(headers: {'X-Business-Id': businessId.toString()});
  }

  /// Paged queue browse. `GET /pos/queue?page=&size=&source=&status=`.
  ///
  /// Newest first. [source] is one of WEB | GLOVO | KOOUL | OTHER, [status] one
  /// of PENDING | CONFIRMED | CANCELLED | ACKNOWLEDGED; both optional.
  ///
  /// Returns the raw page envelope so the caller can read `totalElements` /
  /// `totalPages` for the pager rather than guessing from the item count.
  Future<Map<String, dynamic>> fetchQueuePage({
    int page = 0,
    int size = 20,
    String? source,
    String? status,
  }) async {
    try {
      final response = await _dio.get(
        '/pos/queue',
        queryParameters: {
          'page': page,
          'size': size,
          if (source != null && source.isNotEmpty) 'source': source,
          if (status != null && status.isNotEmpty) 'status': status,
        },
        options: _queueOptions(),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('Failed to browse queue: ${response.statusCode}');
    } on DioException catch (e) {
      throw Exception(
          'Failed to browse queue: ${e.message ?? 'Check connection.'}');
    }
  }

  /// Per-source tallies for the filter chips. `GET /pos/queue/counts?status=`.
  ///
  /// The four source keys are always present and zero-filled, and are exactly
  /// the values the `source` filter accepts — so the chips can be rendered
  /// straight off the map instead of being hardcoded.
  ///
  /// Never throws: a missing badge count must not break the screen.
  Future<Map<String, dynamic>> fetchQueueCounts({String? status}) async {
    try {
      final response = await _dio.get(
        '/pos/queue/counts',
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
        },
        options: _queueOptions(),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return const {'total': 0, 'bySource': {}};
    } catch (_) {
      return const {'total': 0, 'bySource': {}};
    }
  }

  /// Delivery-platform mapping snapshot. `GET /pos/mappings?provider=`.
  ///
  /// Lets the POS resolve a marketplace line to a local product itself instead
  /// of trusting the queue payload. Carries no credentials — tokens and webhook
  /// secrets never reach a terminal.
  Future<Map<String, dynamic>> fetchIntegrationMappings({String? provider}) async {
    try {
      final response = await _dio.get(
        '/pos/mappings',
        queryParameters: {
          if (provider != null && provider.isNotEmpty) 'provider': provider,
        },
        options: _queueOptions(),
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return const {'stores': [], 'items': []};
    } catch (_) {
      return const {'stores': [], 'items': []};
    }
  }

  /// Returns all PENDING external queue items for this business.
  Future<List<Map<String, dynamic>>> fetchPendingQueueItems() async {
    try {
      final response =
          await _dio.get('/pos/queue/pending', options: _queueOptions());
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data as List);
      }
      throw Exception('Server returned ${response.statusCode}');
    } on DioException catch (e) {
      throw Exception(
          'Failed to fetch queue: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error fetching queue: $e');
    }
  }

  /// Confirms a queue item. Backend flips state PENDING→CONFIRMED
  /// atomically (only one terminal wins) and notifies DealUp. The
  /// **backend does NOT save the order** — the POS is the source of
  /// truth for order content; the local order row syncs via the regular
  /// order endpoints.
  ///
  /// Returns `{queueItemId, orderCode, status: "CONFIRMED"}` on 200.
  /// Throws [QueueItemTakenException] on 409 (another terminal already
  /// confirmed or cancelled) so callers can drop the item from the queue
  /// view without surfacing a generic error.
  Future<Map<String, dynamic>> confirmQueueItem(int queueItemId) async {
    try {
      final response = await _dio.post('/pos/queue/$queueItemId/confirm',
          options: _queueOptions());
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Server returned ${response.statusCode}');
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw QueueItemTakenException(queueItemId);
      }
      if (e.response?.statusCode == 404) {
        throw Exception('Queue item not found');
      }
      throw Exception(
          'Failed to confirm: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      if (e is QueueItemTakenException) rethrow;
      throw Exception('Error confirming order: $e');
    }
  }

  /// Rejects a queue item. Backend flips state to CANCELLED and notifies
  /// DealUp.
  ///
  /// Returns `{queueItemId, orderCode, status: "CANCELLED"}` on 200.
  /// On 409 the item was already cancelled by someone else — that's
  /// idempotent-safe, returns a synthetic success map so callers can
  /// treat it the same way as a fresh cancel.
  Future<Map<String, dynamic>> cancelQueueItem(int queueItemId) async {
    try {
      final response = await _dio.post('/pos/queue/$queueItemId/cancel',
          options: _queueOptions());
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      throw Exception('Server returned ${response.statusCode}');
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // Already cancelled — treat as success. Caller can still drop
        // the queue item locally; the desired end state is reached.
        return {
          'queueItemId': queueItemId,
          'status': 'CANCELLED',
        };
      }
      if (e.response?.statusCode == 404) {
        throw Exception('Queue item not found');
      }
      throw Exception(
          'Failed to cancel: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error cancelling order: $e');
    }
  }

  // ========== NOTIFICATIONS ==========

  /// POST /pos/notify — fire-and-forget admin notification.
  /// Never throws; the caller should unawaited-call and not block on result.
  Future<void> postNotification({
    required String type,
    required Map<String, String> params,
    String? refId,
    String? clientRequestId,
  }) async {
    try {
      await _dio.post('/pos/notify', data: {
        'type': type,
        'params': params,
        if (refId != null) 'refId': refId,
        if (clientRequestId != null) 'clientRequestId': clientRequestId,
      });
    } catch (_) {
      // Best-effort — never block the caller.
    }
  }

  // ========== SESSION RULES ==========

  /// Fetches server-configured session rules.
  /// Returns null on 404 (not yet configured), auth errors, or any network
  /// failure — the caller should keep the last cached value in that case.
  Future<Map<String, dynamic>?> fetchSessionRules() async {
    try {
      final response = await _dio.get('/pos/session-rules');
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ========== SESSION EMAIL REPORT ==========

  /// POST /pos/cash-sessions/{sessionCode}/email-report
  /// Fire-and-forget: caller should unawaited-call and swallow exceptions.
  /// 4xx responses are logged and dropped (no retry); 5xx / network errors
  /// are rethrown so the caller can decide whether to retry.
  Future<void> sendSessionEmailReport(
    String sessionCode,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _dio.post(
        '/pos/cash-sessions/$sessionCode/email-report',
        data: payload,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        // Permanent failure — bad payload or auth. Don't retry.
        return;
      }
      rethrow;
    }
  }
}

/// Thrown on HTTP 409 from the Z upsert endpoints: this terminal already has a
/// DIFFERENT open Z on the server, and [openZ] is that Z (the server returns it
/// as the conflict body).
///
/// Retrying is pointless — the contract is "adopt it". The sync path replaces
/// the local open Z with this one so both sides agree, then carries on.
class ZAlreadyOpenException implements Exception {
  final Map<String, dynamic> openZ;
  ZAlreadyOpenException(this.openZ);
  String? get code => openZ['code'] as String?;
  @override
  String toString() => 'ZAlreadyOpenException(serverOpenZ=$code)';
}

/// Thrown by [ApiService.confirmQueueItem] on HTTP 409 — another POS
/// terminal (or admin) already confirmed or cancelled this queue item.
/// The cashier should be told the item is gone and the local queue view
/// should drop it; no order is saved.
class QueueItemTakenException implements Exception {
  final int queueItemId;
  QueueItemTakenException(this.queueItemId);
  @override
  String toString() => 'QueueItemTakenException(id=$queueItemId)';
}

