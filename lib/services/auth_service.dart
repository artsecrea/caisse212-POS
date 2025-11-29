import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final Dio _dio;
  final SharedPreferences _prefs;
  static const String _tokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';

  AuthService(this._dio, this._prefs) {
    _dio.options.baseUrl = 'https://your-api-url.com/api'; // TODO: Set your API URL
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try to refresh token
          final refreshed = await refreshToken();
          if (refreshed) {
            // Retry the request
            return handler.resolve(await _dio.fetch(error.requestOptions));
          }
        }
        return handler.next(error);
      },
    ));
  }

  String? getToken() {
    return _prefs.getString(_tokenKey);
  }

  Future<void> saveToken(String token) async {
    await _prefs.setString(_tokenKey, token);
  }

  Future<void> saveRefreshToken(String token) async {
    await _prefs.setString(_refreshTokenKey, token);
  }

  Future<void> saveUserId(int userId) async {
    await _prefs.setInt(_userIdKey, userId);
  }

  int? getUserId() {
    return _prefs.getInt(_userIdKey);
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'username': username,
        'password': password,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        await saveToken(data['accessToken']);
        await saveRefreshToken(data['refreshToken']);
        await saveUserId(data['user']['id']);
        return data;
      } else {
        throw Exception('Login failed');
      }
    } catch (e) {
      throw Exception('Login error: $e');
    }
  }

  Future<bool> refreshToken() async {
    try {
      final refreshToken = _prefs.getString(_refreshTokenKey);
      if (refreshToken == null) return false;

      final response = await _dio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        await saveToken(data['accessToken']);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> syncData() async {
    try {
      final response = await _dio.get('/sync/all');
      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('Sync failed');
      }
    } catch (e) {
      throw Exception('Sync error: $e');
    }
  }

  Future<void> logout() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_refreshTokenKey);
    await _prefs.remove(_userIdKey);
  }

  bool isLoggedIn() {
    return getToken() != null;
  }
}

