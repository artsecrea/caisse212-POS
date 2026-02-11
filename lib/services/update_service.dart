import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:loggecrea/loggecrea.dart';

/// Update information model
class UpdateInfo {
  final String version;
  final String downloadUrl;
  final bool isMandatory;
  final String releaseNotes;
  final String checksum;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.isMandatory,
    required this.releaseNotes,
    required this.checksum,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String,
      downloadUrl: json['downloadUrl'] as String,
      isMandatory: json['isMandatory'] as bool? ?? false,
      releaseNotes: json['releaseNotes'] as String? ?? '',
      checksum: json['checksum'] as String? ?? '',
    );
  }
}

/// Update service for managing app updates
class UpdateService {
  final _logger = Logger.instance;
  final Dio _dio = Dio();

  /// Check for available updates
  /// This will be implemented later to call your update API
  Future<UpdateInfo?> checkForUpdates() async {
    try {
      // TODO: Implement API call to check for updates
      // Example:
      // final response = await http.get(Uri.parse('YOUR_UPDATE_API_URL'));
      // if (response.statusCode == 200) {
      //   return UpdateInfo.fromJson(jsonDecode(response.body));
      // }
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
      // Get temp directory
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}\\app-update.zip';
      final file = File(filePath);

      // Delete old update if exists
      if (await file.exists()) {
        await file.delete();
      }

      _logger.info('Downloading update from: ${updateInfo.downloadUrl}');

      // Download the update package
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
      }

      return filePath;
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

      // Build PowerShell command
      final excludeFoldersParam = excludeFolders != null && excludeFolders.isNotEmpty
          ? '-ExcludeFolders @("${excludeFolders.join('","')}")'
          : '';

      final passwordParam = archivePassword != null && archivePassword.isNotEmpty
          ? '-ArchivePassword "$archivePassword"'
          : '';

      final checksumParam = checksum != null && checksum.isNotEmpty
          ? '-Checksum "$checksum"'
          : '';

      final command = '''
        Start-Process PowerShell -ArgumentList "-ExecutionPolicy Bypass -File \\"$updaterScriptPath\\" -DownloadUrl \\"file:///$updateArchivePath\\" -AppDirectory \\"$appDirectory\\" -ExecutableName \\"$executableName\\" $excludeFoldersParam $passwordParam $checksumParam" -Verb RunAs
      ''';

      _logger.info('Launching Windows updater...');

      // Execute the command
      final result = await Process.run(
        'powershell.exe',
        ['-Command', command],
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
