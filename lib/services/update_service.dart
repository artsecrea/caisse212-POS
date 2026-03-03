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

  /// Download and prepare update for Windows
  /// The actual installation will be handled by the PowerShell updater
  Future<String?> downloadUpdateForWindows(
    UpdateInfo updateInfo, {
    Function(double)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      _logger.warning('This method is only for Windows');
      return null;
    }

    try {
      await _initPrefs();

      // Get temp directory
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}\\app-update.zip';
      final file = File(filePath);

      // Delete old update if exists
      if (await file.exists()) {
        await file.delete();
      }

      _logger.info('Downloading update from: ${updateInfo.downloadUrl}');

      // Prepare headers with authentication (same as update check)
      final headers = <String, dynamic>{
        'Accept': 'application/zip, application/octet-stream, */*',
      };

      final token = _getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
        _logger.info('Using authentication token');
      } else {
        _logger.warning('No authentication token available');
      }

      final posName = _getPosName();
      if (posName != null) {
        headers['X-POS-Name'] = posName;
      }

      final tenantId = _getTenantId();
      if (tenantId != null) {
        headers['X-Tenant-ID'] = tenantId.toString();
      }

      // First, do a HEAD request to check content type and size
      try {
        final headResponse = await _dio.head(
          updateInfo.downloadUrl,
          options: Options(headers: headers),
        );
        _logger.info('HEAD response: ${headResponse.statusCode}');
        _logger.info('Content-Type: ${headResponse.headers.value('content-type')}');
        _logger.info('Content-Length: ${headResponse.headers.value('content-length')}');
      } catch (e) {
        _logger.warning('HEAD request failed (continuing anyway): $e');
      }

      // Download the update package with authentication
      // Use responseType: bytes to get raw data
      final response = await _dio.get<List<int>>(
        updateInfo.downloadUrl,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          validateStatus: (status) => status != null && status < 500,
        ),
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            final progress = received / total;
            onProgress(progress);
          }
        },
      );

      _logger.info('Download response status: ${response.statusCode}');
      _logger.info('Response content-type: ${response.headers.value('content-type')}');

      // Check response status
      if (response.statusCode != 200) {
        _logger.error('Download failed with status: ${response.statusCode}');
        if (response.data != null && response.data!.length < 1000) {
          _logger.error('Response body: ${String.fromCharCodes(response.data!)}');
        }
        return null;
      }

      // Check content type
      final contentType = response.headers.value('content-type') ?? '';
      if (contentType.contains('text/html') || contentType.contains('application/json')) {
        _logger.error('Server returned $contentType instead of ZIP file');
        if (response.data != null && response.data!.length < 2000) {
          _logger.error('Response content: ${String.fromCharCodes(response.data!)}');
        }
        return null;
      }

      // Check we have data
      if (response.data == null || response.data!.isEmpty) {
        _logger.error('Downloaded data is empty');
        return null;
      }

      final bytes = response.data!;
      _logger.info('Downloaded ${bytes.length} bytes');

      // Check ZIP magic bytes (PK = 0x50 0x4B)
      if (bytes.length < 4) {
        _logger.error('Downloaded file too small');
        return null;
      }

      if (bytes[0] != 0x50 || bytes[1] != 0x4B) {
        _logger.error('Downloaded file is not a valid ZIP (magic bytes: ${bytes[0].toRadixString(16)} ${bytes[1].toRadixString(16)})');
        if (bytes.length < 500) {
          _logger.error('File content: ${String.fromCharCodes(bytes)}');
        }
        return null;
      }

      // Write to file
      await file.writeAsBytes(bytes);
      _logger.info('Saved to: $filePath');

      // Verify file was written correctly
      final savedSize = await file.length();
      if (savedSize != bytes.length) {
        _logger.error('File size mismatch: expected ${bytes.length}, got $savedSize');
        return null;
      }

      _logger.info('Download completed successfully: $savedSize bytes');
      return filePath;
    } on DioException catch (e) {
      _logger.error('Dio error during download: ${e.type} - ${e.message}');
      if (e.response != null) {
        _logger.error('Response status: ${e.response?.statusCode}');
        _logger.error('Response headers: ${e.response?.headers}');
      }
      return null;
    } catch (e, stackTrace) {
      _logger.error('Failed to download update: $e', stackTrace: stackTrace);
      return null;
    }
  }

  /// Launch Windows updater
  Future<bool> launchWindowsUpdater({
    required String updateArchivePath,
    required String appDirectory,
    required String executableName,
    List<String>? excludeFolders,
    String? archivePassword,
    String? checksum,
  }) async {
    if (!Platform.isWindows) {
      _logger.warning('This method is only for Windows');
      return false;
    }

    try {
      // Get the updater script path (should be bundled with the app)
      final updaterScriptPath = '$appDirectory\\updater\\WindowsUpdater.ps1';

      if (!await File(updaterScriptPath).exists()) {
        _logger.error('Updater script not found: $updaterScriptPath');
        return false;
      }

      // Build the inner PowerShell arguments properly
      // Note: We need to escape paths for PowerShell and handle spaces correctly
      final scriptArgs = [
        '-ExecutionPolicy', 'Bypass',
        '-File', updaterScriptPath,
        '-DownloadUrl', 'file:///$updateArchivePath',
        '-AppDirectory', appDirectory,
        '-ExecutableName', executableName,
      ];

      // Add optional parameters
      if (excludeFolders != null && excludeFolders.isNotEmpty) {
        scriptArgs.addAll(['-ExcludeFolders', excludeFolders.join(',')]);
      }
      if (archivePassword != null && archivePassword.isNotEmpty) {
        scriptArgs.addAll(['-ArchivePassword', archivePassword]);
      }
      if (checksum != null && checksum.isNotEmpty) {
        scriptArgs.addAll(['-Checksum', checksum]);
      }

      _logger.info('Launching Windows updater...');
      _logger.info('Script path: $updaterScriptPath');
      _logger.info('Arguments: ${scriptArgs.join(' ')}');

      // Execute PowerShell with Start-Process to run elevated
      final result = await Process.run(
        'powershell.exe',
        [
          '-ExecutionPolicy', 'Bypass',
          '-Command',
          'Start-Process',
          'PowerShell',
          '-ArgumentList', scriptArgs.map((arg) => '"$arg"').join(','),
          '-Verb', 'RunAs',
        ],
      );

      if (result.exitCode == 0) {
        _logger.info('Windows updater launched successfully');
        return true;
      } else {
        _logger.error('Failed to launch updater: ${result.stderr}');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to launch Windows updater: $e', stackTrace: stackTrace);
      return false;
    }
  }

  /// Clean up downloaded files
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
      } else if (Platform.isWindows) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}\\app-update.zip');
        if (await file.exists()) {
          await file.delete();
          _logger.info('Cleaned up downloaded update package');
        }
      }
    } catch (e) {
      _logger.error('Failed to cleanup: $e');
    }
  }
}
