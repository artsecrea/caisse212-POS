import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// API Service for handling all server communication
class ApiService {
  late final Dio _dio;
  final SharedPreferences _prefs;

  static const String _accessTokenKey = 'server_access_token';
  static const String _refreshTokenKey = 'server_refresh_token';
  static const String _accessExpiresAtMsKey = 'server_access_expires_at_ms';
  static const String _posNameKey = 'pos_name';
  static const String _posIdKey = 'pos_terminal_id';
  static const String _baseUrlKey = 'api_base_url';
  static const String _tenantIdKey = 'tenant_id';
  static const String _businessIdKey = 'business_id';
  static const String _isDemoModeKey = 'is_demo_mode';
  static const String _businessNameKey = 'business_name';
  static const String _businessLogoKey = 'business_logo';

  // In-memory access-token expiry (loaded from prefs on startup).
  DateTime? _accessExpiresAt;

  // Single-flight refresh: if a refresh is in progress all callers wait for
  // the same Completer rather than firing parallel refresh requests.
  Completer<void>? _refreshCompleter;

  // Broadcast stream that fires when the refresh token is definitively
  // rejected (4xx from /pos/refresh). Subscribers navigate to login.
  final _forceLogoutController = StreamController<void>.broadcast();
  Stream<void> get forceLogoutStream => _forceLogoutController.stream;

  // Public getter for Dio instance (for testing/debugging)
  Dio get dio => _dio;

  ApiService(this._prefs) {
    // Restore persisted expiry into memory so pre-emptive refresh works
    // after an app restart without needing a fresh login.
    final storedMs = _prefs.getInt(_accessExpiresAtMsKey);
    if (storedMs != null) {
      _accessExpiresAt = DateTime.fromMillisecondsSinceEpoch(storedMs);
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
        // Add base URL
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
          options.headers['X-Pos-Id'] = posId.toString();
        }

        // Add tenant ID header
        final tenantId = getTenantId();
        if (tenantId != null) {
          options.headers['X-Tenant-ID'] = tenantId.toString();
        }

        // Intentionally DO NOT send X-Business-Id. Per the POS API contract the
        // server resolves the owning business from X-POS-Name; the header must
        // be omitted. Sending anything other than the exact posTerminal
        // businessId — in particular the tenant id, which this app historically
        // conflated with the business id — triggers 403 "Business does not
        // belong to the current tenant". Omitting it is the sanctioned path.

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
      _refreshCompleter!.complete();
    } catch (e) {
      _refreshCompleter!.completeError(e);
      rethrow;
    } finally {
      _refreshCompleter = null;
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
  }

  /// Called when the server explicitly rejects the refresh token (4xx).
  /// Clears auth tokens and signals the UI to show the login screen.
  Future<void> _handleForceLogout() async {
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_refreshTokenKey);
    await _prefs.remove(_accessExpiresAtMsKey);
    _accessExpiresAt = null;
    if (!_forceLogoutController.isClosed) {
      _forceLogoutController.add(null);
    }
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
          print('Business name saved: $businessName');
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
            print('Business logo saved (${base64Logo.length} chars)');
          } catch (e) {
            print('Failed to save business logo: $e');
          }
        }

        return data;
      } else {
        throw Exception('Login failed: ${response.statusMessage}');
      }
    } on DioException catch (e) {
      print('Login DioException caught: ${e.type}');
      print('Login error details: ${e.error}');

      // Handle server response errors (4xx, 5xx)
      if (e.response != null) {
        print('Server response status: ${e.response?.statusCode}');
        print('Server response data: ${e.response?.data}');

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
      print('Login general error: $e');
      throw Exception('Login error: ${e.toString()}');
    }
  }

  /// Logout from the server
  Future<void> logout() async {
    // Skip API call in demo mode
    if (isDemoMode()) {
      print('Logout (demo mode)');
      return;
    }

    try {
      final posName = getPosName();
      final accessToken = getAccessToken();

      // Only call API if we have credentials
      if (posName == null || accessToken == null) {
        print('Logout: No credentials found, skipping API call');
        return;
      }

      print('Logout: Calling /logout API for POS: $posName');

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
        print('Logout: Successfully logged out from server');
      } else {
        print('Logout: Server returned status ${response.statusCode}');
      }
    } on DioException catch (e) {
      // Log error but don't throw - logout should succeed locally even if server call fails
      print('Logout API error: ${e.type}');
      print('Logout error message: ${e.message}');
      print('Logout error response: ${e.response?.data}');

      // Don't throw exception - we still want to clear local data
      print('Logout: Continuing with local logout despite server error');
    } catch (e) {
      print('Logout general error: $e');
      // Don't throw exception - we still want to clear local data
      print('Logout: Continuing with local logout despite error');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch categories. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch products. Check connection.'}');
    } catch (e) {
      throw Exception('Error fetching products: ${e.toString()}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch components. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch component groups. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch components. Check connection.'}');
    } catch (e) {
      throw Exception('Error fetching components: ${e.toString()}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch variants. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch product variants. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch tables. Check connection.'}');
    } catch (e) {
      throw Exception('Error fetching tables: ${e.toString()}');
    }
  }

  /// Fetch users from server
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    try {
      final response = await _dio.get('/pos/users');
      print ( '>>>>>>>>>>>>é' + response.data.toString());
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch users');
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch users. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch payment methods. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch commercials. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch coupons. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch stations. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch customers. Check connection.'}');
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
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message ?? 'Failed to fetch waiters. Check connection.'}');
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
  Future<void> syncOrders(List<Map<String, dynamic>> orders) async {
    try {
      final response = await _dio.post('/pos/orders/bulk', data: {"orders": orders});
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for bulk orders sync');
      }
    } on DioException catch (e) {
      throw Exception('Failed to sync orders: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing orders: ${e.toString()}');
    }
  }

  /// Sync a single order to server using PUT (creates or updates)
  /// Throws if the server does not return a 2xx status.
  Future<void> syncSingleOrder(String orderCode, Map<String, dynamic> orderData) async {
    try {
      final response = await _dio.put('/pos/orders/$orderCode', data: orderData);
      if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) {
        throw Exception('Server returned status ${response.statusCode} for order $orderCode sync');
      }
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

  // ── External Order Queue ───────────────────────────────────────────────────

  /// Returns all PENDING external queue items for this business.
  Future<List<Map<String, dynamic>>> fetchPendingQueueItems() async {
    try {
      final response = await _dio.get('/pos/queue/pending');
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
      final response = await _dio.post('/pos/queue/$queueItemId/confirm');
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
      final response = await _dio.post('/pos/queue/$queueItemId/cancel');
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

