import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// API Service for handling all server communication
class ApiService {
  late final Dio _dio;
  final SharedPreferences _prefs;

  static const String _accessTokenKey = 'server_access_token';
  static const String _posNameKey = 'pos_name';
  static const String _baseUrlKey = 'api_base_url';
  static const String _tenantIdKey = 'tenant_id';
  static const String _isDemoModeKey = 'is_demo_mode';

  // Public getter for Dio instance (for testing/debugging)
  Dio get dio => _dio;

  ApiService(this._prefs) {
    _dio = Dio();
    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Add base URL
        final baseUrl = "${_prefs.getString(_baseUrlKey) ?? ''}/api";
        if (baseUrl.isNotEmpty && !options.path.startsWith('http')) {
          options.path = '$baseUrl${options.path}';
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

        // Add tenant ID header
        final tenantId = getTenantId();
        if (tenantId != null) {
          options.headers['X-Tenant-ID'] = tenantId;
        }

        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Token expired - could implement refresh logic here
          print('API Error 401: Unauthorized');
        }
        return handler.next(error);
      },
    ));
  }

  // Getters for stored values
  String? getAccessToken() => _prefs.getString(_accessTokenKey);
  String? getPosName() => _prefs.getString(_posNameKey);
  String? getTenantId() => _prefs.getString(_tenantIdKey);
  String? getBaseUrl() => _prefs.getString(_baseUrlKey);
  bool isDemoMode() => _prefs.getBool(_isDemoModeKey) ?? false;

  // Setters for stored values
  Future<void> setAccessToken(String token) async {
    await _prefs.setString(_accessTokenKey, token);
  }

  Future<void> setPosName(String name) async {
    await _prefs.setString(_posNameKey, name);
  }

  Future<void> setTenantId(String id) async {
    await _prefs.setString(_tenantIdKey, id);
  }

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(_baseUrlKey, url);
  }

  Future<void> setDemoMode(bool isDemoMode) async {
    await _prefs.setBool(_isDemoModeKey, isDemoMode);
  }

  /// Clear all authentication data
  Future<void> clearAuthData() async {
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_posNameKey);
    await _prefs.remove(_tenantIdKey);
    await _prefs.remove(_baseUrlKey);
    await _prefs.remove(_isDemoModeKey);
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
      }, options: Options(headers: {'X-POS-Name': posName}));

      if (response.statusCode == 200) {
        final data = response.data;
        await setAccessToken(data['accessToken']);
        await setPosName(posName);
        if (data['tenantId'] != null) {
          await setTenantId(data['tenantId']);
        }
        return data;
      } else {
        throw Exception('Login failed: ${response.statusMessage}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception('Login failed: ${e.response?.data['message'] ?? e.message}');
      }
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Fetch categories from server
  Future<List<Map<String, dynamic>>> fetchCategories() async {
    try {
      final response = await _dio.get('/pos/categories');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch categories');
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
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
      throw Exception('Network error: ${e.message}');
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
      throw Exception('Network error: ${e.message}');
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
      throw Exception('Network error: ${e.message}');
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
      throw Exception('Network error: ${e.message}');
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
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Fetch users from server
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    try {
      final response = await _dio.get('/pos/users');
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      throw Exception('Failed to fetch users');
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
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
      throw Exception('Network error: ${e.message}');
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
      throw Exception('Network error: ${e.message}');
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
      throw Exception('Network error: ${e.message}');
    }
  }

  // ============ SYNC DATA TO SERVER ============

  /// Sync orders to server
  Future<void> syncOrders(List<Map<String, dynamic>> orders) async {
    try {
      await _dio.post('/pos/orders/bulk', data: {'orders': orders});
    } on DioException catch (e) {
      throw Exception('Failed to sync orders: ${e.message}');
    }
  }

  /// Sync tickets to server
  Future<void> syncTickets(List<Map<String, dynamic>> tickets) async {
    try {
      await _dio.post('/pos/sync/tickets', data: {'tickets': tickets});
    } on DioException catch (e) {
      throw Exception('Failed to sync tickets: ${e.message}');
    }
  }

  /// Sync sessions to server
  Future<void> syncSessions(List<Map<String, dynamic>> sessions) async {
    try {
      await _dio.post('/pos/sync/sessions', data: {'sessions': sessions});
    } on DioException catch (e) {
      throw Exception('Failed to sync sessions: ${e.message}');
    }
  }

  /// Sync customers to server (new customers created locally)
  Future<void> syncCustomers(List<Map<String, dynamic>> customers) async {
    try {
      await _dio.post('/pos/sync/customers', data: {'customers': customers});
    } on DioException catch (e) {
      throw Exception('Failed to sync customers: ${e.message}');
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
}

