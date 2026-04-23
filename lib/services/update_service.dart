import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Update information model matching LatestUpdateResponse from API
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
      downloadUrl: json['downloadUrl'] as String,
      checksum: json['sha256'] as String? ?? '',
      isMandatory: json['mandatory'] as bool? ?? false,
      releaseNotes: json['releaseNotes'] as String?,
    );
  }
}

/// Update service for managing app updates
class UpdateService {
  final _logger = Logger.instance;
  final Dio _dio = Dio();
  SharedPreferences? _prefs;

  static const String _baseUrlKey = 'api_base_url';
  static const String _accessTokenKey = 'server_access_token';
  static const String _posNameKey = 'pos_name';
  static const String _tenantIdKey = 'tenant_id';

  /// Initialize SharedPreferences
  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Get access token for authentication
  String? _getAccessToken() => _prefs?.getString(_accessTokenKey);

  /// Get POS name
  String? _getPosName() => _prefs?.getString(_posNameKey);

  /// Get tenant ID
  int? _getTenantId() => _prefs?.getInt(_tenantIdKey);

  /// Get current platform string for API
  String get _platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Check for available updates by calling api/pos/update_check
  Future<UpdateInfo?> checkForUpdates() async {
    try {
      await _initPrefs();
      
      final baseUrl = _prefs?.getString(_baseUrlKey);
      if (baseUrl == null || baseUrl.isEmpty) {
        _logger.warning('No base URL configured for update check');
        return null;
      }

      final url = '$baseUrl/api/pos/update_check?platform=$_platform';
      _logger.info('Checking for updates: $url');

      // Prepare headers with authentication
      final headers = <String, dynamic>{};

      final token = _getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final posName = _getPosName();
      if (posName != null) {
        headers['X-POS-Name'] = posName;
      }

      final tenantId = _getTenantId();
      if (tenantId != null) {
        headers['X-Tenant-ID'] = tenantId.toString();
      }

      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final updateInfo = UpdateInfo.fromJson(response.data);
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

  /// Download and install update for Android
  Future<bool> downloadAndInstallUpdate(
    UpdateInfo updateInfo, {
    Function(double)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      _logger.warning('Update installation only supported on Android');
      return false;
    }

    try {
      // Request storage permission
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        _logger.error('Storage permission denied');
        return false;
      }

      // Get download directory
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        _logger.error('Could not access external storage');
        return false;
      }

      final filePath = '${dir.path}/app-update.apk';
      final file = File(filePath);

      // Delete old APK if exists
      if (await file.exists()) {
        await file.delete();
      }

      _logger.info('Downloading update from: ${updateInfo.downloadUrl}');

      // Download the APK
      await _dio.download(
        updateInfo.downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            final progress = received / total;
            onProgress(progress);
          }
        },
      );

      _logger.info('Download completed: $filePath');

      // Verify checksum if provided
      if (updateInfo.checksum.isNotEmpty) {
        _logger.info('Verifying checksum...');
        // TODO: Implement checksum verification
        // final fileChecksum = await _calculateChecksum(file);
        // if (fileChecksum != updateInfo.checksum) {
        //   _logger.error('Checksum verification failed');
        //   await file.delete();
        //   return false;
        // }
      }

      // Install the APK
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
      _logger.error('Failed to download/install update: $e', stackTrace: stackTrace);
      return false;
    }
  }

  // NOTE: Windows/macOS/Linux updates are handled entirely by the desktop_updater
  // package (DesktopUpdaterController + UpdateDialogListener). No manual download
  // or PowerShell launcher is needed for desktop platforms.

  /// Clean up downloaded files (Android only – desktop is handled by desktop_updater)
  Future<void> cleanup() async {
    try {
      if (Platform.isAndroid) {
        final dir = await getExternalStorageDirectory();
        if (dir != null) {
          final file = File('${dir.path}/app-update.apk');
          if (await file.exists()) {
            await file.delete();
            _logger.info('Cleaned up downloaded APK');
          }
        }
      }
    } catch (e) {
      _logger.error('Failed to cleanup: $e');
    }
  }
}
