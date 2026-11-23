import 'dart:async';
import '../domain/models/serial_conflict.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/reservation_models.dart';
import '../utils/pos_log.dart';
import 'subscription_store.dart';
import 'account_status_store.dart';
import 'kick_store.dart';
import '../domain/models/account_status.dart';
import '../domain/models/order_tag_codec.dart';
import 'refund_policy_store.dart';
import '../domain/models/subscription_info.dart';

/// What an order push reported besides success: serial links the server
/// refused, and how any `reservationCode` on the pushed orders was linked.
class OrderPushResult {
  final List<SerialConflictReport> serialConflicts;
  final List<ReservationLink> reservationLinks;

  const OrderPushResult(this.serialConflicts, this.reservationLinks);
}

/// The `error` of a DioException for a call refused locally because the
/// account is disabled. See [ApiService.checkAccountStatus].
class AccountBlockedException implements Exception {
  const AccountBlockedException();
  @override
  String toString() => 'Account disabled';
}

enum AccountCheck { active, blocked, unknown }

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

enum RefundLookupFailure { notFound, offline }

/// Why an online refund lookup failed. `offline` covers every "could not get
/// a straight answer" case — no network, timeout, 5xx — because the response
/// is the same: refunds wait for the connection.
class RefundLookupException implements Exception {
  final RefundLookupFailure failure;
  final String? detail;
  const RefundLookupException(this.failure, [this.detail]);

  @override
  String toString() => 'RefundLookupException(${failure.name}: $detail)';
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

  // Fires whenever a token expiry moves (new pair saved, force-logout, or a
  // debug simulation). Static for the same reason as the scope stream above.
  static final _expiryController = StreamController<void>.broadcast();
  Stream<void> get expiryChanges => _expiryController.stream;

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
      // 10s was too tight for the tills in the field: the logs are full of
      // "the request connection took longer than 0:00:10 and it was aborted",
      // thousands of them, on a link that plainly works the rest of the time.
      // A restaurant's uplink is congested, not absent. Raised — paired with
      // the streak breaker in DataSyncService, which is what stops a genuinely
      // unreachable endpoint from costing 20s per queued order instead.
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      // Was unset, so a stalled upload had no deadline at all and sat on the
      // socket until the OS gave up.
      sendTimeout: const Duration(seconds: 30),
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
        final noAuth = options.extra[_noAuthExtra] == true;

        // A disabled account makes no cloud calls except the ones that can
        // tell us it is back (status check, login, refresh) and logout. Failing
        // here, before the network, keeps sync from burning its retry budget
        // on refusals: queued work waits untouched until reactivation.
        if (!_accountGateExempt(options.path) &&
            AccountStatusStore(_prefs).isBlocked) {
          return handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: const AccountBlockedException(),
          ));
        }

        if (!isAuthEndpoint && !isRetry && !noAuth) {
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
        if (token != null && !noAuth) {
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
      onResponse: (response, handler) async {
        // login / refresh / GET /pos/subscription carry
        // posTerminal.accountStatus; an explicit verdict is applied, an
        // absent one changes nothing.
        final body = response.data;
        if (body is Map) {
          final terminal = body['posTerminal'];
          final raw = terminal is Map && terminal.containsKey('accountStatus')
              ? terminal['accountStatus']
              : body['accountStatus'];
          await AccountStatusStore(_prefs).applyStatus(parseAccountStatus(raw));
        }
        return handler.next(response);
      },
      onError: (error, handler) async {
        final block = _accountBlockOf(error);
        if (block != null) {
          await AccountStatusStore(_prefs).block(block);
          return handler.next(error);
        }
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
          // token (4xx). Network errors while offline mean "retry later". A
          // disabled account is not a dead token: keep the tokens, the lock
          // card handles it, and they work again on reactivation.
          if (_accountBlockOf(e) == null &&
              e.response != null &&
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

  // ── Account status (tenant / business / terminal active) ─────────────────

  static const _noAuthExtra = '_noAuth';

  static bool _accountGateExempt(String path) =>
      path.contains('/pos/account-status') ||
      path.contains('/pos/login') ||
      path.contains('/pos/refresh') ||
      path.contains('/pos/logout') ||
      path.contains('/pos/update_check');

  static AccountBlock? _accountBlockOf(DioException e) {
    if (e.error is AccountBlockedException) return null; // our own gate
    final r = e.response;
    if (r == null) return null;
    return accountBlockFromError(
      statusCode: r.statusCode,
      body: r.data,
      statusHeader: r.headers.value(kAccountStatusHeader),
    );
  }

  AccountBlock? get accountBlock => AccountStatusStore(_prefs).current;

  /// Asks the server whether this till may work: `GET /pos/account-status`,
  /// sent without a token because a kicked till's token may be refused too.
  ///
  /// Stores the verdict and returns it. [AccountCheck.unknown] (offline, server
  /// error) leaves the stored state alone: only a definite answer locks or
  /// unlocks.
  Future<AccountCheck> checkAccountStatus() async {
    if (isDemoMode()) return AccountCheck.active;
    try {
      final response = await _dio.get(
        '/pos/account-status',
        options: Options(extra: {_noAuthExtra: true}),
      );
      final body = response.data;
      if (body is Map && body.containsKey('subscription')) {
        await SubscriptionStore(_prefs).apply(body['subscription']);
      }
      final parsed = parseAccountStatus(body);
      if (parsed == null) return AccountCheck.unknown;
      await AccountStatusStore(_prefs).applyStatus(parsed);
      return parsed == true ? AccountCheck.active : AccountCheck.blocked;
    } on DioException catch (e) {
      if (_accountBlockOf(e) != null) return AccountCheck.blocked;
      // A server from before the endpoint: a token refresh stands in. It is
      // exempt from the local gate, and on a server with the account filter
      // it answers 423 while disabled. Old servers never checked on refresh,
      // so success there proves nothing and changes nothing.
      if (e.response?.statusCode == 404) {
        try {
          await _doRefresh();
        } on DioException catch (re) {
          if (_accountBlockOf(re) != null) return AccountCheck.blocked;
        } catch (_) {}
        return isAccountBlocked ? AccountCheck.unknown : AccountCheck.active;
      }
      posLog('Account status check failed: ${e.type} ${e.response?.statusCode}');
      return AccountCheck.unknown;
    } catch (e) {
      posLog('Account status check failed: $e');
      return AccountCheck.unknown;
    }
  }

  bool get isAccountBlocked => AccountStatusStore(_prefs).isBlocked;

  /// For channels outside Dio (the SSE stream): records an "account disabled"
  /// refusal. Returns true when it was one.
  Future<bool> noteAccountRefusal(
      int statusCode, String? statusHeader, dynamic body) async {
    final block = accountBlockFromError(
        statusCode: statusCode, body: body, statusHeader: statusHeader);
    if (block == null) return false;
    await AccountStatusStore(_prefs).block(block);
    return true;
  }

  /// The SSE `force_kick` push: records why, then signs the TERMINAL out —
  /// tokens wiped, so the re-auth gate asks for the terminal password. Tenant,
  /// business, POS name and the pending sync queue stay, so signing back in
  /// picks up where the till left off.
  Future<void> applyKick(Map<String, dynamic> command) async {
    final code = (command['code'] as String?)?.trim();
    final message = (command['message'] as String?)?.trim();
    await KickStore(_prefs).record(KickNotice(
      code: code == null || code.isEmpty ? 'ADMIN_KICK' : code.toUpperCase(),
      message: message == null || message.isEmpty ? null : message,
      at: DateTime.now(),
    ));
    if (command['lock'] == true) {
      await applyAccountDisabledPush({
        'scope': command['scope'] ?? 'TERMINAL',
        'message': message,
        'reasonCode': code,
      });
    }
    await _handleForceLogout();
  }

  /// The SSE `account_disabled` push.
  Future<void> applyAccountDisabledPush(Map<String, dynamic> command) =>
      AccountStatusStore(_prefs).block(AccountBlock(
        scope: parseAccountScope(command['scope']),
        message: (command['message'] as String?)?.trim().isEmpty ?? true
            ? null
            : (command['message'] as String).trim(),
        reasonCode: (command['reasonCode'] as String?)?.trim().isEmpty ?? true
            ? null
            : (command['reasonCode'] as String).trim(),
        since: DateTime.now(),
      ));

  // ── Refresh token flow ───────────────────────────────────────────────────

  /// For callers outside Dio (the SSE stream): refresh the access token when
  /// it expires within a minute, or always when [force]. Returns false when
  /// the refresh failed; the caller keeps the token it has.
  Future<bool> ensureFreshToken({bool force = false}) async {
    // From prefs, not the in-memory copy: other ApiService instances refresh
    // too, and acting on a stale expiry would rotate the pair needlessly.
    final ms = _prefs.getInt(_accessExpiresAtMsKey);
    final exp = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    final due = force ||
        (exp != null &&
            DateTime.now().isAfter(exp.subtract(const Duration(seconds: 60))));
    if (!due) return true;
    try {
      await _doRefresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Single-flight internal refresh. All concurrent callers await the same
  /// Completer so only one `POST /pos/refresh` is ever in flight at a time.
  Future<void> _doRefresh() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<void>();
    // The first caller gets the error from the rethrow below; the shared
    // future only matters to concurrent waiters. Without this, every failed
    // refresh nobody else was waiting on surfaced as an "Unhandled Exception".
    _refreshCompleter!.future.ignore();
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
      // Same channel carries the subscription, so every rotation (timer, 401,
      // Update button, SSE `refresh_token`) also re-reads it for free.
      await SubscriptionStore(_prefs).applyResponse(data);
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
    _expiryController.add(null);
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
    _expiryController.add(null);
    if (!_forceLogoutController.isClosed) {
      _forceLogoutController.add(null);
    }
  }

  /// The refresh-token (session) expiry, or null if unknown.
  DateTime? getRefreshExpiresAt() => _refreshExpiresAt;

  DateTime? getAccessExpiresAt() => _accessExpiresAt;

  String? getRefreshToken() => _prefs.getString(_refreshTokenKey);

  /// Decoded JWT payload (no signature check) — for the debug token panel.
  static Map<String, dynamic>? jwtPayload(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      var seg = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      seg = seg.padRight(seg.length + (4 - seg.length % 4) % 4, '=');
      return jsonDecode(utf8.decode(base64.decode(seg))) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Debug-only simulation (Test mode screen) ──────────────────────────────
  // These move only the CLIENT's idea of when the tokens die; the tokens
  // themselves are untouched, so the server keeps accepting them and any real
  // refresh or re-login puts the true expiry back.

  /// Pretend the session (refresh token) dies at [at]. null restores the real
  /// expiry decoded from the stored refresh JWT.
  Future<void> debugSetRefreshExpiry(DateTime? at) async {
    final real = _jwtExpiry(_prefs.getString(_refreshTokenKey));
    final value = at ?? real;
    _refreshExpiresAt = value;
    if (value == null) {
      await _prefs.remove(_refreshExpiresAtMsKey);
    } else {
      await _prefs.setInt(_refreshExpiresAtMsKey, value.millisecondsSinceEpoch);
    }
    _expiryController.add(null);
  }

  /// Pretend the access token dies at [at], so the next API call takes the
  /// pre-emptive refresh path.
  Future<void> debugSetAccessExpiry(DateTime at) async {
    _accessExpiresAt = at;
    await _prefs.setInt(_accessExpiresAtMsKey, at.millisecondsSinceEpoch);
    _expiryController.add(null);
  }

  /// What a hard-rejected refresh (4xx) looks like to the UI — the obligatory
  /// re-auth gate — WITHOUT wiping the tokens the real path would wipe.
  void debugSimulateRefreshRejected() {
    if (!_forceLogoutController.isClosed) _forceLogoutController.add(null);
  }

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
    await SubscriptionStore(_prefs).clear();
    await RefundPolicyStore(_prefs).clear();
    // Another tenant's lock must not follow a tenant switch; the new one's
    // login says for itself.
    await AccountStatusStore(_prefs).clear();
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
        await SubscriptionStore(_prefs).applyResponse(data);
        // The server checks tenant, business and terminal on login (old
        // servers check the terminal), so a login it accepts means active.
        await AccountStatusStore(_prefs).clear();
        await KickStore(_prefs).clear();

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

  /// `GET /pos/orders/{code}/split` — the server's view of a split bill:
  /// `{orderTotal, paidAmount, remainingAmount, unassignedPaidAmount,
  /// tickets[{ticketNumber, amount, method, date, split}], lines[...]}`.
  /// Cancelled tickets are already left out. Null on any failure or timeout:
  /// callers fall back to what this till knows.
  Future<Map<String, dynamic>?> fetchOrderSplit(String orderCode,
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final r = await _dio
          .get('/pos/orders/${Uri.encodeComponent(orderCode)}/split')
          .timeout(timeout);
      if (r.statusCode == 200 && r.data is Map) {
        return Map<String, dynamic>.from(r.data as Map);
      }
      return null;
    } catch (_) {
      return null;
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

  /// `GET /pos/subscription` → stored. Returns false when it could not be read
  /// (offline, older server without the endpoint); the stored copy is kept.
  ///
  /// With [onlyIfDue] it is a no-op unless the login warning is showing and
  /// today's check has not happened yet — see [subscriptionCheckDue].
  Future<bool> refreshSubscription({bool onlyIfDue = false}) async {
    final store = SubscriptionStore(_prefs);
    if (onlyIfDue && !store.checkDue) return true;
    if (isDemoMode()) return false;
    try {
      final response = await _dio.get('/pos/subscription');
      if (response.statusCode == 200) {
        final body = response.data;
        // Accept the object itself or `{ "subscription": {...} }`.
        await store.apply(body is Map && body.containsKey('subscription')
            ? body['subscription']
            : body);
        return true;
      }
      if (response.statusCode == 204) {
        await store.apply(null);
        return true;
      }
      return false;
    } catch (e) {
      posLog('Subscription check skipped: $e');
      return false;
    }
  }

  SubscriptionInfo? get subscription => SubscriptionStore(_prefs).current;

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

  // ── Reservations (backend V198) ─────────────────────────────────────────
  //
  // Every write here is ONLINE ONLY and never queued: it claims slots in the
  // shop's one diary under a server lock. The business comes from
  // X-POS-Name; X-Business-Id is added too, as on the other agenda calls.

  Options _reservationOptions() {
    final businessId = getBusinessId();
    return Options(headers: {
      if (businessId != null) 'X-Business-Id': businessId,
    });
  }

  /// Maps a reservation write's failure to the contract's errors: 409 →
  /// [ReservationConflict], 400 → [ReservationValidationError].
  Never _reservationError(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    final map = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
    if (status == 409) throw ReservationConflict.fromJson(map);
    if (status == 400 || status == 403 || status == 404) {
      throw ReservationValidationError(
          (map['message'] ?? map['error'] ?? 'Reservation refused').toString());
    }
    throw e;
  }

  Reservation _reservationFrom(Response<dynamic> r) =>
      Reservation.fromJson(Map<String, dynamic>.from(r.data as Map));

  /// `GET /pos/reservations/agenda` — the frame and reservations of
  /// [from]..[to] (shop-zone days, inclusive, at most 42).
  Future<AgendaWindow> fetchReservationAgenda({
    required DateTime from,
    required DateTime to,
    List<int>? resourceIds,
  }) async {
    final response = await _dio.get(
      '/pos/reservations/agenda',
      queryParameters: {
        'from': _isoDate(from),
        'to': _isoDate(to),
        if (resourceIds != null && resourceIds.isNotEmpty)
          'resourceIds': resourceIds.join(','),
      },
      options: _reservationOptions(),
    );
    return AgendaWindow.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  /// `GET /pos/reservations/availability` — free starts for the whole basket
  /// [productIds] (chained back to back) from [date] for [days] days.
  /// Advisory: the write is the authoritative check.
  Future<List<AvailabilitySlot>> fetchReservationAvailability({
    required List<int> productIds,
    required DateTime date,
    int days = 1,
    List<int>? resourceIds,
    int? step,
    int? excludeReservationId,
  }) async {
    try {
      final response = await _dio.get(
        '/pos/reservations/availability',
        queryParameters: {
          'productIds': productIds.join(','),
          'date': _isoDate(date),
          'days': days,
          if (resourceIds != null && resourceIds.isNotEmpty)
            'resourceIds': resourceIds.join(','),
          if (step != null) 'step': step,
          if (excludeReservationId != null)
            'excludeReservationId': excludeReservationId,
        },
        options: _reservationOptions(),
      );
      final body = response.data;
      final slots = body is Map ? body['slots'] : body;
      return (slots is List ? slots : const [])
          .whereType<Map>()
          .map((m) => AvailabilitySlot.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      _reservationError(e);
    }
  }

  /// `GET /pos/reservations` — search. [search] matches code, name, phone.
  Future<List<Reservation>> searchReservations({
    String? search,
    int? customerId,
    String? status,
    DateTime? from,
    DateTime? to,
    int limit = 50,
  }) async {
    final response = await _dio.get(
      '/pos/reservations',
      queryParameters: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (customerId != null) 'customerId': customerId,
        if (status != null) 'status': status,
        if (from != null) 'from': _isoDate(from),
        if (to != null) 'to': _isoDate(to),
        'limit': limit.clamp(1, 100),
      },
      options: _reservationOptions(),
    );
    final body = response.data;
    final list = body is Map ? (body['data'] ?? body['content']) : body;
    return (list is List ? list : const [])
        .whereType<Map>()
        .map((m) => Reservation.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<Reservation> fetchReservation(int id) async {
    try {
      return _reservationFrom(await _dio.get('/pos/reservations/$id',
          options: _reservationOptions()));
    } on DioException catch (e) {
      _reservationError(e);
    }
  }

  Future<Reservation> fetchReservationByCode(String code) async {
    try {
      return _reservationFrom(await _dio.get(
          '/pos/reservations/code/${Uri.encodeComponent(code)}',
          options: _reservationOptions()));
    } on DioException catch (e) {
      _reservationError(e);
    }
  }

  /// `POST /pos/reservations`. See [ReservationDraft.toJson] for the body.
  Future<Reservation> createReservation(Map<String, dynamic> body) async {
    try {
      return _reservationFrom(await _dio.post('/pos/reservations',
          data: body, options: _reservationOptions()));
    } on DioException catch (e) {
      _reservationError(e);
    }
  }

  /// `PUT /pos/reservations/{id}` — full replace; items keep their `id`.
  Future<Reservation> updateReservation(
      int id, Map<String, dynamic> body) async {
    try {
      return _reservationFrom(await _dio.put('/pos/reservations/$id',
          data: body, options: _reservationOptions()));
    } on DioException catch (e) {
      _reservationError(e);
    }
  }

  /// `PATCH /pos/reservations/{id}/move` — shift the whole reservation,
  /// optionally onto another resource.
  Future<Reservation> moveReservation(int id,
      {required DateTime startAt,
      int? resourceId,
      bool overbook = false,
      bool allowOverlap = false}) async {
    try {
      return _reservationFrom(await _dio.patch(
        '/pos/reservations/$id/move',
        data: {
          'startAt': toWireInstant(startAt),
          if (resourceId != null) 'resourceId': resourceId,
          if (overbook) 'overbook': true,
          if (allowOverlap) 'allowOverlap': true,
        },
        options: _reservationOptions(),
      ));
    } on DioException catch (e) {
      _reservationError(e);
    }
  }

  /// `PATCH /pos/reservations/items/{itemId}` — move or reassign one service.
  Future<Reservation> updateReservationItem(int itemId,
      {required DateTime startAt,
      DateTime? endAt,
      List<int>? resourceIds,
      bool overbook = false,
      bool allowOverlap = false}) async {
    try {
      return _reservationFrom(await _dio.patch(
        '/pos/reservations/items/$itemId',
        data: {
          'startAt': toWireInstant(startAt),
          if (endAt != null) 'endAt': toWireInstant(endAt),
          if (resourceIds != null) 'resourceIds': resourceIds,
          if (overbook) 'overbook': true,
          if (allowOverlap) 'allowOverlap': true,
        },
        options: _reservationOptions(),
      ));
    } on DioException catch (e) {
      _reservationError(e);
    }
  }

  /// `PATCH /pos/reservations/{id}/status`. CONVERTED is refused here; it is
  /// set only by an order push carrying `reservationCode`.
  Future<Reservation> setReservationStatus(int id, String status,
      {String? reason, bool overbook = false}) async {
    try {
      return _reservationFrom(await _dio.patch(
        '/pos/reservations/$id/status',
        data: {
          'status': status,
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          if (overbook) 'overbook': true,
        },
        options: _reservationOptions(),
      ));
    } on DioException catch (e) {
      _reservationError(e);
    }
  }

  /// `POST /pos/reservations/blocks` — a break, absence or block on a
  /// resource. [kind] is BREAK | ABSENCE | BLOCK.
  Future<void> createAgendaBlock({
    required int resourceId,
    required String kind,
    String? title,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    try {
      await _dio.post(
        '/pos/reservations/blocks',
        data: {
          'resourceId': resourceId,
          'kind': kind,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          'startAt': toWireInstant(startAt),
          'endAt': toWireInstant(endAt),
        },
        options: _reservationOptions(),
      );
    } on DioException catch (e) {
      _reservationError(e);
    }
  }

  Future<void> deleteAgendaBlock(int id) async {
    try {
      await _dio.delete('/pos/reservations/blocks/$id',
          options: _reservationOptions());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return; // already gone
      _reservationError(e);
    }
  }

  static String _isoDate(DateTime d) => dayKey(d);

  /// Fetch bookable resources (staff, rooms, chairs, equipment).
  /// Best-effort: an older backend without the endpoint, or any network
  /// error, yields an empty list rather than failing the whole master sync.
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
  /// Null on a 404: the endpoint is newer than some servers in the field, and
  /// "this server cannot say" must stay distinct from an empty 200, which is
  /// authoritative (no overrides, no conditional groups). Anything else still
  /// throws — a broken sync should be visible.
  Future<List<Map<String, dynamic>>?> fetchProductComponentGroups() async {
    try {
      final response = await _dio.get('/pos/product-component-groups');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch product component groups');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
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

  /// Every order of one cash session, each a full snapshot (lines with their
  /// components, line tombstones, payments). `docs/ORDER_REFRESH_CONTRACT.md`.
  Future<List<Map<String, dynamic>>> fetchSessionOrders(
      String sessionCode) async {
    try {
      final r = await _dio.get(
          '/pos/sessions/${Uri.encodeComponent(sessionCode)}/orders');
      if (r.statusCode == 200) {
        final data = r.data;
        final list = data is Map ? data['orders'] : data;
        return ((list as List?) ?? const [])
            .map((o) => Map<String, dynamic>.from(o as Map))
            .toList();
      }
      throw Exception('Failed to fetch session orders (${r.statusCode})');
    } on DioException catch (e) {
      // A session the server has never seen has no orders there yet.
      if (e.response?.statusCode == 404) return const [];
      throw Exception(
          'Network error: ${e.message ?? 'Failed to fetch session orders. Check connection.'}');
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
  ///
  /// [v2] sends to `/pos/v2/orders/bulk`: same body, but every line carries
  /// its `lineUid` (cancelled lines included) and a known order gets its lines
  /// merged too, not only its state.
  Future<OrderPushResult> syncOrders(
      List<Map<String, dynamic>> orders, {bool v2 = false}) async {
    try {
      final response = await _dio.post(
          v2 ? '/pos/v2/orders/bulk' : '/pos/orders/bulk',
          data: {"orders": orders});
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for bulk orders sync');
      }
      return OrderPushResult(SerialConflictReport.listFrom(response.data),
          ReservationLink.listFrom(response.data));
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
  ///
  /// [v2] sends to `/pos/v2/orders/{code}` — see [syncOrders].
  Future<OrderPushResult> syncSingleOrder(
      String orderCode, Map<String, dynamic> orderData,
      {bool v2 = false}) async {
    try {
      final response = await _dio.put(
          v2 ? '/pos/v2/orders/$orderCode' : '/pos/orders/$orderCode',
          data: orderData);
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for order $orderCode sync');
      }
      return OrderPushResult(SerialConflictReport.listFrom(response.data),
          ReservationLink.listFrom(response.data, orderCode: orderCode));
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

  // ── Z (day close), contract v3 ─────────────────────────────────────────────
  // No Z entity on the server: a Z is the (zDay, zSeq) label carried on
  // sessions. The terminal is resolved from X-POS-Name + the JWT tenant.

  /// This terminal's latest Z, for resuming the counter at startup and after
  /// a reinstall. GET /pos/z/current →
  /// `{currentZDay, zDay, zSeq, closed, closeMode, closedAt}` (zDay / zSeq
  /// null when the terminal never had a session). Null on any failure, so an
  /// offline till falls back to its own sessions.
  Future<Map<String, dynamic>?> fetchCurrentZ() async {
    try {
      final response = await _dio.get(
        '/pos/z/current',
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

  /// Close a session the server holds open but this till has no record of
  /// (a reinstall mid-Z). POST /pos/cash-sessions/{code}/close with
  /// `{endedAt, autoClosed, isClosingSession?, zCloseMode?, zClosedAt?}` —
  /// never touches its money, times or cashier; idempotent on a closed one.
  Future<void> closeServerSession(
      String code, Map<String, dynamic> body) async {
    try {
      final response =
          await _dio.post('/pos/cash-sessions/$code/close', data: body);
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw Exception(
            'Server returned status ${response.statusCode} closing session $code');
      }
    } on DioException catch (e) {
      throw Exception(
          'Failed to close session $code: ${e.message ?? 'Check connection.'}');
    }
  }

  // ── Cash movements (drawer pay-in / pay-out) ──────────────────────────────

  /// Bulk upsert by `code`. POST /pos/cash-movements/bulk {"movements": [...]}.
  Future<void> syncCashMovements(List<Map<String, dynamic>> movements) async {
    try {
      final response = await _dio.post('/pos/cash-movements/bulk',
          data: {"movements": movements});
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw Exception(
            'Server returned status ${response.statusCode} for cash movement sync');
      }
    } on DioException catch (e) {
      throw Exception(
          'Failed to sync cash movements: ${e.message ?? 'Check connection.'}');
    }
  }

  /// Upsert one movement. PUT /pos/cash-movements/{code}.
  Future<void> syncSingleCashMovement(
      String code, Map<String, dynamic> movement) async {
    try {
      final response =
          await _dio.put('/pos/cash-movements/$code', data: movement);
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw Exception(
            'Server returned status ${response.statusCode} for cash movement $code');
      }
    } on DioException catch (e) {
      throw Exception(
          'Failed to sync cash movement: ${e.message ?? 'Check connection.'}');
    }
  }

  /// Delete a movement. DELETE /pos/cash-movements/{code}.
  Future<void> deleteCashMovement(String code) async {
    try {
      await _dio.delete('/pos/cash-movements/$code');
    } on DioException catch (e) {
      throw Exception(
          'Failed to delete cash movement: ${e.message ?? 'Check connection.'}');
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

  /// The order, fresh from the server, for a refund. Refunds are online-only:
  /// the server's copy is the truth (another till may have changed or refunded
  /// it), so any failure is reported — never papered over with a local copy.
  ///
  /// Throws [RefundLookupException]: `notFound` on 404, `offline` otherwise.
  Future<Map<String, dynamic>> fetchOrderForRefund(String orderCode) async {
    try {
      final response = await _dio.get(
        '/pos/orders/${Uri.encodeComponent(orderCode)}',
        options: Options(validateStatus: (c) => c != null && c < 500),
      );
      if (response.statusCode == 404) {
        throw const RefundLookupException(RefundLookupFailure.notFound);
      }
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw RefundLookupException(RefundLookupFailure.offline,
          'HTTP ${response.statusCode}');
    } on RefundLookupException {
      rethrow;
    } catch (e) {
      throw RefundLookupException(RefundLookupFailure.offline, '$e');
    }
  }

  /// Every refund the server holds for [orderCode], from ALL tills — strict.
  ///
  /// Unlike [fetchRefunds], a failure throws: "could not ask" must not read as
  /// "no earlier refunds", or a refund given on another till would not count
  /// against the cap. 404 = the order has none.
  Future<List<Map<String, dynamic>>> fetchRefundsForRefund(
      String orderCode) async {
    try {
      final response = await _dio.get(
        '/pos/refunds',
        queryParameters: {'orderCode': orderCode},
        options: Options(validateStatus: (c) => c != null && c < 500),
      );
      if (response.statusCode == 404) return const [];
      final data = response.data;
      if (response.statusCode == 200) {
        if (data is List) return List<Map<String, dynamic>>.from(data);
        if (data is Map && data['content'] is List) {
          return List<Map<String, dynamic>>.from(data['content'] as List);
        }
        if (data == null || data == '') return const [];
      }
      throw RefundLookupException(RefundLookupFailure.offline,
          'HTTP ${response.statusCode}');
    } on RefundLookupException {
      rethrow;
    } catch (e) {
      throw RefundLookupException(RefundLookupFailure.offline, '$e');
    }
  }

  /// One page of refunds across the business, newest first:
  /// `GET /pos/refunds?from=&to=&page=&size=`. Returns null when the server
  /// does not support the listing yet (it answers the old `orderCode` form
  /// only), so the screen can say so instead of showing an empty list.
  Future<Map<String, dynamic>?> fetchRefundsPage({
    required DateTime from,
    required DateTime to,
    int page = 0,
    int size = 50,
  }) async {
    final response = await _dio.get(
      '/pos/refunds',
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'page': page,
        'size': size,
      },
      options: Options(validateStatus: (c) => c != null && c < 500),
    );
    final data = response.data;
    if (response.statusCode == 200 && data is Map && data['content'] is List) {
      return Map<String, dynamic>.from(data);
    }
    // 400 (missing orderCode), 404, or a bare list: not the paged listing.
    return null;
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

  /// POST /pos/notify, throwing on any failure — for the outbox, which must
  /// know whether to delete its row. Callers wanting fire-and-forget use
  /// [postNotification].
  Future<void> sendNotification({
    required String type,
    required Map<String, String> params,
    String? refId,
    required String clientRequestId,
  }) async {
    final response = await _dio.post('/pos/notify', data: {
      'type': type,
      'params': params,
      if (refId != null) 'refId': refId,
      'clientRequestId': clientRequestId,
    });
    final code = response.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
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

  // ========== ORDER TAGS ==========

  /// `GET /pos/order-tags` → the business's tags plus the shared ones. Null
  /// when the server has no such route (older build): keep the cached list.
  Future<List<Map<String, dynamic>>?> fetchOrderTags() async {
    final response = await _dio.get(
      '/pos/order-tags',
      options: Options(validateStatus: (c) => c != null && c < 500),
    );
    if (response.statusCode == 404) return null;
    final data = response.data;
    if (response.statusCode == 200 && data is Map && data['tags'] is List) {
      return List<Map<String, dynamic>>.from(data['tags'] as List);
    }
    throw Exception('Order tags: HTTP ${response.statusCode}');
  }

  /// `PUT /pos/orders/{code}/tags` — full replace.
  ///
  /// On success `stored` is the set the server ACTUALLY kept: a tag deleted
  /// in the back office while the push was queued is dropped silently, and
  /// the till must take that set rather than keep showing the deleted one.
  /// `error` is `'NOT_ON_SERVER'` on 404 (push the order first) or the
  /// server's message on 400 (a tag that never existed, another business's,
  /// more than 10). Throws on a transport failure so the caller retries.
  Future<({List<int>? stored, String? error})> putOrderTags(
      String orderCode, List<int> tagIds) async {
    final response = await _dio.put(
      '/pos/orders/${Uri.encodeComponent(orderCode)}/tags',
      data: {'tagIds': tagIds},
      options: Options(validateStatus: (c) => c != null && c < 500),
    );
    if (response.statusCode == 404) {
      return (stored: null, error: 'NOT_ON_SERVER');
    }
    if (response.statusCode == 400) {
      final d = response.data;
      return (
        stored: null,
        error: (d is Map ? (d['message'] ?? d['error']) : d)?.toString() ??
            'HTTP 400'
      );
    }
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      final d = response.data;
      // An older/odd body without the stored set: assume ours was kept.
      final stored = d is Map ? tagIdsFromSnapshot(Map<String, dynamic>.from(d)) : null;
      return (stored: stored ?? tagIds, error: null);
    }
    throw Exception('Order tags push: HTTP ${response.statusCode}');
  }

  // ========== REFUND POLICY ==========

  /// `GET /pos/refund-policy` → stored. 200 = the effective policy, 204 =
  /// nothing configured (defaults). Returns false when it could not be read
  /// (offline, an older server without the route → 404): the cached policy
  /// stands, which is what a till refunding offline needs.
  Future<bool> refreshRefundPolicy() async {
    if (isDemoMode()) return false;
    try {
      final response = await _dio.get('/pos/refund-policy');
      if (response.statusCode == 204 ||
          (response.statusCode == 200 && response.data == null)) {
        await RefundPolicyStore(_prefs).apply(null);
        return true;
      }
      if (response.statusCode == 200 && response.data is Map) {
        await RefundPolicyStore(_prefs).apply(response.data as Map);
        return true;
      }
      return false;
    } catch (e) {
      posLog('Refund policy fetch skipped: $e');
      return false;
    }
  }

  // ========== REMOTE CONSOLE ==========

  /// POST /pos/remote/{requestId}/result — the one reply to a `pos-command`
  /// that carried a requestId. Never retried: 404 = expired, 403 = another
  /// terminal's request, 409 = already answered, and anything else would only
  /// answer twice.
  Future<void> postRemoteResult(
      String requestId, Map<String, dynamic> body) async {
    try {
      await _dio.post(
        '/pos/remote/${Uri.encodeComponent(requestId)}/result',
        data: body,
      );
    } on DioException catch (e) {
      posLog('Remote reply $requestId dropped: '
          '${e.response?.statusCode ?? e.type}');
    } catch (e) {
      posLog('Remote reply $requestId dropped: $e');
    }
  }

  /// PUT /pos/remote-access — how support reaches this till. True on 2xx.
  /// The body may carry the remote-support password: it is never logged.
  Future<bool> putRemoteAccess(Map<String, dynamic> body) async {
    if (isDemoMode()) return false;
    try {
      final r = await _dio.put('/pos/remote-access', data: body);
      final code = r.statusCode ?? 0;
      return code >= 200 && code < 300;
    } on DioException catch (e) {
      posLog('Remote access report refused: '
          '${e.response?.statusCode ?? e.type}');
      return false;
    } catch (e) {
      posLog('Remote access report failed: ${e.runtimeType}');
      return false;
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

