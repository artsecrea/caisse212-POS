import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final String appName;
  final String platform;
  final String version;
  final String downloadUrl;
  final String checksum; // sha256
  final bool isMandatory;
  final String? releaseNotes;

  UpdateInfo({
    required this.appName,
    required this.platform,
    required this.version,
    required this.downloadUrl,
    required this.checksum,
    required this.isMandatory,
    this.releaseNotes,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      appName: json['appName'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      version: json['version'] as String,
      downloadUrl: json['url'] as String,
      checksum: json['sha256'] as String? ?? '',
      isMandatory: json['mandatory'] as bool? ?? false,
      releaseNotes: json['releaseNotes'] as String?,
    );
  }
}

class UpdateService {
  final _logger = Logger.instance;
  final Dio _dio = Dio();
  SharedPreferences? _prefs;

  static const String _baseUrlKey = 'api_base_url';
  static const String _accessTokenKey = 'server_access_token';
  static const String _posNameKey = 'pos_name';
  static const String _tenantIdKey = 'tenant_id';

  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  String? _getAccessToken() => _prefs?.getString(_accessTokenKey);
  String? _getPosName() => _prefs?.getString(_posNameKey);
  int? _getTenantId() => _prefs?.getInt(_tenantIdKey);

  /// Get current platform string for API
  static String get currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Check for available updates (Android only; desktop uses desktop_updater).
  Future<UpdateInfo?> checkForUpdates() async {
    try {
      await _initPrefs();

      final baseUrl = _prefs?.getString(_baseUrlKey);
      if (baseUrl == null || baseUrl.isEmpty) {
        _logger.warning('No base URL configured for update check');
        return null;
      }

      // Strip trailing /api so we can re-append it cleanly.
      var root = baseUrl.trimRight();
      if (root.endsWith('/api')) root = root.substring(0, root.length - 4);
      final platform = UpdateService.currentPlatform;
      final url = '$root/api/pos/update_check?platform=$platform';
      _logger.info('Checking for updates: $url');

      final headers = <String, dynamic>{};
      final token = _getAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final posName = _getPosName();
      if (posName != null) headers['X-POS-Name'] = posName;
      final tenantId = _getTenantId();
      if (tenantId != null) headers['X-Tenant-ID'] = tenantId.toString();

      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;
        final updateInfo = UpdateInfo.fromJson(data);
        _logger.info('Update info received: version ${updateInfo.version}');
        return updateInfo;
      }

      _logger.info('No update available');
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _logger.info('No update available (404)');
        return null;
      }
      _logger.error('Failed to check for updates: ${e.message}');
      return null;
    } catch (e) {
      _logger.error('Failed to check for updates: $e');
      return null;
    }
  }

  /// Download and install update (Android only).
  /// Desktop updates are handled by desktop_updater via UpdateDialogListener.
  Future<bool> downloadAndInstallUpdate(
    UpdateInfo updateInfo, {
    Function(double)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      _logger.warning('downloadAndInstallUpdate called on non-Android platform');
      return false;
    }

    try {
      // Use app-specific dir — no storage permission needed on any API level.
      final dir = await getApplicationSupportDirectory();
      final filePath = '${dir.path}/app-update.apk';
      final file = File(filePath);

      if (await file.exists()) await file.delete();

      _logger.info('Downloading update from: ${updateInfo.downloadUrl}');

      await _dio.download(
        updateInfo.downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );

      _logger.info('Download completed: $filePath');

      if (updateInfo.checksum.isNotEmpty) {
        _logger.info('Verifying checksum...');
        final fileBytes = await file.readAsBytes();
        final fileChecksum = sha256.convert(fileBytes).toString();
        if (fileChecksum != updateInfo.checksum) {
          _logger.error(
              'Checksum mismatch — expected ${updateInfo.checksum}, got $fileChecksum');
          await file.delete();
          return false;
        }
        _logger.info('Checksum OK');
      }

      _logger.info('Opening APK installer...');
      final result = await OpenFilex.open(filePath);

      if (result.type == ResultType.done) {
        _logger.info('APK installer opened successfully');
        return true;
      } else {
        _logger.error('Failed to open APK installer: ${result.message}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to download/install update: $e',
          stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> cleanup() async {
    try {
      if (Platform.isAndroid) {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/app-update.apk');
        if (await file.exists()) {
          await file.delete();
          _logger.info('Cleaned up downloaded APK');
        }
      }
    } catch (e) {
      _logger.error('Failed to cleanup: $e');
    }
  }
}
