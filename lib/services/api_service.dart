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
        final savedBaseUrl = _prefs.getString(_baseUrlKey);
        if (savedBaseUrl != null && savedBaseUrl.isNotEmpty && !options.path.startsWith('http')) {
          final baseUrl = '$savedBaseUrl/api';
          options.path = '$baseUrl${options.path}';
        }

        // Debug logging
        print('API Request: ${options.method} ${options.path}');
        if (options.data != null) {
          print('Request data: ${options.data}');
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
        print(tenantId);
        if (tenantId != null) {
          options.headers['X-Tenant-ID'] = tenantId.toString();
        }

        print('Request headers: ${options.headers}');

        return handler.next(options);
      },
      onError: (error, handler) async {
        print('API Error: ${error.type}');
        print('API Error message: ${error.message}');
        print('API Error response: ${error.response?.data}');
        print('API Error status code: ${error.response?.statusCode}');

        // Additional debugging for connection errors
        if (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.unknown) {
          print('Connection Error Details:');
          print('  - Error: ${error.error}');
          print('  - Request URI: ${error.requestOptions.uri}');
          print('  - Request method: ${error.requestOptions.method}');
        }

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
  int? getTenantId() => _prefs.getInt(_tenantIdKey);
  String? getBaseUrl() => _prefs.getString(_baseUrlKey);
  bool isDemoMode() => _prefs.getBool(_isDemoModeKey) ?? false;

  // Setters for stored values
  Future<void> setAccessToken(String token) async {
    await _prefs.setString(_accessTokenKey, token);
  }

  Future<void> setPosName(String name) async {
    await _prefs.setString(_posNameKey, name);
  }

  Future<void> setTenantId(int id) async {
    await _prefs.setInt(_tenantIdKey, id);
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
      }, options: Options(headers: {'X-POS-Name': posName}));

      if (response.statusCode == 200) {
        final data = response.data;
        await setAccessToken(data['accessToken']);
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

  /// Fetch categories from server
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
  Future<void> syncOrders(List<Map<String, dynamic>> orders) async {
    try {
      await _dio.post('/pos/orders/bulk', data: {"orders": orders});
    } on DioException catch (e) {
      throw Exception('Failed to sync orders: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing orders: ${e.toString()}');
    }
  }

  /// Sync a single order to server using PUT (creates or updates)
  Future<void> syncSingleOrder(String orderCode, Map<String, dynamic> orderData) async {
    try {
      await _dio.put('/pos/orders/$orderCode', data: orderData);
    } on DioException catch (e) {
      throw Exception('Failed to sync order: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing order: ${e.toString()}');
    }
  }

  /// Sync tickets to server
  Future<void> syncTickets(List<Map<String, dynamic>> tickets) async {
    try {
      await _dio.post('/pos/tickets/bulk', data: {"tickets":tickets});
    } on DioException catch (e) {
      throw Exception('Failed to sync tickets: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing tickets: ${e.toString()}');
    }
  }

  /// Sync sessions to server
  Future<void> syncSessions(List<Map<String, dynamic>> sessions) async {
    try {
      await _dio.post('/pos/cash-sessions/bulk', data: {"sessions" : sessions});
    } on DioException catch (e) {
      throw Exception('Failed to sync sessions: ${e.message ?? 'Check connection.'}');
    } catch (e) {
      throw Exception('Error syncing sessions: ${e.toString()}');
    }
  }

  /// Sync customers to server (new customers created locally)
  Future<void> syncCustomers(List<Map<String, dynamic>> customers) async {
    try {
      await _dio.post('/pos/customers/bulk', data: {"customers" : customers});
    } on DioException catch (e) {
      throw Exception('Failed to sync customers: ${e.message ?? 'Check connection.'}');
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
      await _dio.put('/pos/cash-sessions/$sessionCode', data: sessionData);
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
}

