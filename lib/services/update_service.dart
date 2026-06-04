import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:loggecrea/loggecrea.dart';

/// Flat static-manifest endpoint. Each platform reads `{base}/{platform}.json`
/// (e.g. `https://update.caisse212.com/android.json`). The endpoint returns
/// either:
///   - HTTP 200 with an [UpdateInfo] JSON object → an update is available;
///   - HTTP 200 with body `null` / empty / `{}` → no update;
///   - HTTP 404 / any error → no update (silently).
///
/// No auth, no tenant context, no api/* prefix — it's a flat file you upload
/// to a bucket / CDN. Replace the host below when you wire the real domain.
const String _kUpdateManifestBaseUrl = 'https://update.caisse212.com';

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

  /// Get current platform string for the manifest URL path.
  static String get currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Check for available updates.
  ///
  /// Hits the flat static manifest at
  /// `$_kUpdateManifestBaseUrl/{platform}.json` — no backend, no auth, no
  /// tenant context. The endpoint is allowed to return any of these and we
  /// treat them all as "no update":
  ///   - HTTP 404
  ///   - HTTP 200 with body `null` (literal four bytes)
  ///   - HTTP 200 with empty body
  ///   - HTTP 200 with body `{}`
  ///   - any network / parse error
  ///
  /// Version comparison is the caller's job ([UpdateNotifier.checkForUpdates]).
  Future<UpdateInfo?> checkForUpdates() async {
    final url = '$_kUpdateManifestBaseUrl/$currentPlatform.json';
    _logger.info('Checking for updates: $url');

    try {
      final response = await _dio.get(
        url,
        options: Options(
          // Don't let Dio auto-throw on 404 — we read it as "no update".
          validateStatus: (code) => code != null && code < 500,
          // Static hosts sometimes serve JSON as text/plain; force string so
          // we can decode it ourselves.
          responseType: ResponseType.plain,
        ),
      );

      if (response.statusCode == 404) {
        _logger.info('No update available (404)');
        return null;
      }
      if (response.statusCode != 200) {
        _logger.warning('Update check got HTTP ${response.statusCode}');
        return null;
      }

      final raw = (response.data as String?)?.trim() ?? '';
      if (raw.isEmpty || raw == 'null') {
        _logger.info('No update available (empty/null manifest)');
        return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded == null || decoded is! Map<String, dynamic> || decoded.isEmpty) {
        _logger.info('No update available (manifest empty or wrong shape)');
        return null;
      }

      final updateInfo = UpdateInfo.fromJson(decoded);
      _logger.info('Update info received: version ${updateInfo.version}');
      return updateInfo;
    } on DioException catch (e) {
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
