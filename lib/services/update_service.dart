import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:loggecrea/loggecrea.dart';
import 'api_service.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String checksum; // sha256
  final bool isMandatory;
  final String? releaseNotes;
  final int? sizeBytes;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.checksum,
    required this.isMandatory,
    this.releaseNotes,
    this.sizeBytes,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String,
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      downloadUrl: json['downloadUrl'] as String,
      checksum: json['sha256'] as String? ?? '',
      isMandatory: json['mandatory'] as bool? ?? false,
      releaseNotes: json['releaseNotes'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
    );
  }
}

class UpdateService {
  final ApiService _apiService;
  final _logger = Logger.instance;

  UpdateService(this._apiService);

  static String get currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  // ── Check ──────────────────────────────────────────────────────────────────

  /// Hits `GET /pos/updates/latest?platform={platform}`.
  /// Auth + X-Business-Id injected automatically by the ApiService interceptor.
  Future<UpdateInfo?> checkForUpdates() async {
    try {
      final response = await _apiService.dio.get(
        '/pos/updates/latest',
        queryParameters: {'platform': currentPlatform},
        options: Options(
          validateStatus: (code) => code != null && code < 500,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        _logger.warning('Update check returned HTTP ${response.statusCode}');
        return null;
      }

      final data = response.data;
      if (data == null || data is! Map<String, dynamic> || data.isEmpty) {
        return null;
      }

      final info = UpdateInfo.fromJson(data);
      _logger.info('Update available: ${info.version}+${info.buildNumber}');
      return info;
    } on DioException catch (e) {
      _logger.error('Update check failed: ${e.message}');
      return null;
    } catch (e) {
      _logger.error('Update check failed: $e');
      return null;
    }
  }

  // ── Background prepare (no app exit) ──────────────────────────────────────

  /// Downloads the update and prepares it for the next restart.
  ///
  /// Android  — downloads APK to temp, verifies checksum, writes marker.
  /// Desktop  — downloads ZIP, extracts to temp, deletes ZIP, writes marker.
  ///
  /// Does NOT close the app. On next startup [applyPendingUpdateIfExists]
  /// reads the marker and applies silently.
  ///
  /// Throws on network or checksum failure.
  Future<void> downloadAndPrepare(
    UpdateInfo info, {
    Function(double)? onProgress,
  }) async {
    if (Platform.isIOS) return;

    final tmp = await getTemporaryDirectory();

    if (Platform.isAndroid) {
      final apkPath = _join(tmp.path, 'caisse212-update.apk');
      final file = File(apkPath);
      if (await file.exists()) await file.delete();
      await _download(info.downloadUrl, apkPath, onProgress);
      await _verifyChecksum(file, info.checksum);
      await _writeMarker(tmp.path, info, apkPath);
      return;
    }

    // Desktop: download ZIP → extract → delete ZIP → write marker
    final zipPath = _join(tmp.path, 'caisse212-update.zip');
    final extractPath = _join(tmp.path, 'caisse212-update-extracted');
    final zipFile = File(zipPath);
    final extractDir = Directory(extractPath);

    if (await zipFile.exists()) await zipFile.delete();
    if (await extractDir.exists()) await extractDir.delete(recursive: true);

    await _download(info.downloadUrl, zipPath, onProgress);
    await _verifyChecksum(zipFile, info.checksum);

    _logger.info('Extracting to: $extractPath');
    await extractDir.create(recursive: true);
    await extractFileToDisk(zipPath, extractPath);
    await zipFile.delete();

    await _writeMarker(tmp.path, info, extractPath);
    _logger.info('Update ${info.version} ready — will apply on next restart');
  }

  // ── Startup apply (static — runs before ProviderScope) ────────────────────

  /// Called at the very start of `main()` after `WidgetsFlutterBinding`.
  /// If a prepared update exists, launches the updater script and calls exit(0).
  /// If no update or any error, returns silently so normal startup continues.
  static Future<void> applyPendingUpdateIfExists() async {
    try {
      final tmp = await getTemporaryDirectory();
      final markerFile = File(_sJoin(tmp.path, 'caisse212-update.ready'));
      if (!await markerFile.exists()) return;

      final raw = jsonDecode(await markerFile.readAsString()) as Map<String, dynamic>;
      final filePath = raw['path'] as String;
      final version = raw['version'] as String? ?? '?';

      // Delete marker first so a failed apply doesn't loop forever.
      await markerFile.delete();

      final exePath = Platform.resolvedExecutable;
      final appDir = File(exePath).parent.path;

      if (Platform.isAndroid) {
        final result = await OpenFilex.open(filePath);
        if (result.type == ResultType.done) exit(0);
        return;
      }

      if (Platform.isIOS) return;

      Logger.instance.info('Applying update $version from $filePath');

      if (Platform.isWindows) {
        await _launchWindowsBat(filePath, appDir, exePath, tmp.path);
      } else {
        await _launchUnixSh(filePath, appDir, exePath, tmp.path);
      }

      await Future.delayed(const Duration(milliseconds: 600));
      exit(0);
    } catch (_) {
      // Never block normal startup.
    }
  }

  /// Returns the version string from the marker, or null if no update is ready.
  static Future<String?> pendingUpdateVersion() async {
    try {
      final tmp = await getTemporaryDirectory();
      final f = File(_sJoin(tmp.path, 'caisse212-update.ready'));
      if (!await f.exists()) return null;
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return raw['version'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Updater scripts ────────────────────────────────────────────────────────

  static Future<void> _launchWindowsBat(
    String extractPath,
    String appDir,
    String exePath,
    String tmpPath,
  ) async {
    String w(String p) => p.replaceAll('/', '\\');
    final scriptPath = _sJoin(tmpPath, 'caisse212-updater.bat');
    final logPath = _sJoin(tmpPath, 'caisse212-update.log');
    final backupDir = _sJoin(tmpPath, 'caisse212-update-backup');
    final source = _resolveUpdateSource(extractPath);

    // robocopy tuning:
    //  /E                copy subdirs incl. empty (additive — never deletes
    //                    destination files absent from source, so the DB and
    //                    logs in appDir survive).
    //  /IS /IT           overwrite same/tweaked files (force new binaries in).
    //  /R:3 /W:2         bound retries — the DEFAULT is /R:1000000 /W:30, which
    //                    hangs effectively forever if any file is briefly
    //                    locked (AV / slow handle release), so the app would
    //                    never relaunch. Cap it hard.
    //  /XF *.db*         belt-and-braces: never copy a DB over the live one
    //                    (Flutter's data\ dir is otherwise fully updated).
    const robo = '/E /IS /IT /R:3 /W:2 /NFL /NDL /NJH /NJS /NC /NS';
    const excl = '/XF "*.db" "*.db-wal" "*.db-shm"';

    // robocopy success is exit code < 8; >= 8 means at least one file failed.
    final script = StringBuffer()
      ..write('@echo off\r\n')
      ..write('setlocal\r\n')
      // Give the exiting app time to release its .exe/.dll handles. `ping` is
      // used instead of `timeout` because `timeout` needs a console, which a
      // detached process may not have.
      ..write('ping -n 4 127.0.0.1 >nul\r\n')
      ..write('echo [%date% %time%] backup >"${w(logPath)}"\r\n')
      // 1. Back up the current install so a failed copy can be rolled back.
      ..write('rmdir /s /q "${w(backupDir)}" 2>nul\r\n')
      ..write('robocopy "${w(appDir)}" "${w(backupDir)}" $robo $excl >>"${w(logPath)}" 2>&1\r\n')
      ..write('if %ERRORLEVEL% geq 8 goto backup_failed\r\n')
      // 2. Apply the update over the install.
      ..write('echo [%date% %time%] apply >>"${w(logPath)}"\r\n')
      ..write('robocopy "${w(source)}" "${w(appDir)}" $robo $excl >>"${w(logPath)}" 2>&1\r\n')
      ..write('if %ERRORLEVEL% geq 8 goto copy_failed\r\n')
      // 3. Success — relaunch, clean temp, self-delete. `explorer.exe` launches
      //    the app as the interactive (non-elevated) user even when this script
      //    is running elevated.
      ..write('echo [%date% %time%] ok >>"${w(logPath)}"\r\n')
      ..write('rmdir /s /q "${w(backupDir)}" 2>nul\r\n')
      ..write('rmdir /s /q "${w(extractPath)}" 2>nul\r\n')
      ..write('explorer.exe "${w(exePath)}"\r\n')
      ..write('goto done\r\n')
      // Rollback: restore the backup over the partial copy, then relaunch old.
      ..write(':copy_failed\r\n')
      ..write('echo [%date% %time%] copy failed, rolling back >>"${w(logPath)}"\r\n')
      ..write('robocopy "${w(backupDir)}" "${w(appDir)}" $robo $excl >>"${w(logPath)}" 2>&1\r\n')
      ..write('explorer.exe "${w(exePath)}"\r\n')
      ..write('goto done\r\n')
      // Backup failed before any change was made — safe to just relaunch old.
      ..write(':backup_failed\r\n')
      ..write('echo [%date% %time%] backup failed, aborting (no changes) >>"${w(logPath)}"\r\n')
      ..write('explorer.exe "${w(exePath)}"\r\n')
      ..write(':done\r\n')
      ..write('(goto) 2>nul & del "%~f0"\r\n');

    await File(scriptPath).writeAsString(script.toString());

    if (await _isDirWritable(appDir)) {
      await Process.start(
        'cmd',
        ['/c', w(scriptPath)],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
    } else {
      // Protected location (e.g. Program Files): elevate via UAC, otherwise
      // robocopy hits Access Denied on every file and the update silently fails.
      Logger.instance
          .info('App dir not writable — launching elevated updater');
      final ps = "Start-Process -WindowStyle Hidden -FilePath 'cmd.exe' "
          "-ArgumentList '/c','\"${w(scriptPath)}\"' -Verb RunAs";
      await Process.start(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
          '-Command', ps],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
    }
  }

  static Future<void> _launchUnixSh(
    String extractPath,
    String appDir,
    String exePath,
    String tmpPath,
  ) async {
    final scriptPath = _sJoin(tmpPath, 'caisse212-updater.sh');
    final backupDir = _sJoin(tmpPath, 'caisse212-update-backup');
    final source = _resolveUpdateSource(extractPath);

    // Prefer rsync (atomic-ish, supports excludes + a mirror we can roll back
    // from); fall back to cp when rsync is unavailable. The DB is excluded so
    // it's never clobbered, and a backup is taken for rollback on failure.
    final script = '#!/bin/sh\n'
        'sleep 2\n'
        'SRC="$source"\n'
        'APP="$appDir"\n'
        'BAK="$backupDir"\n'
        'EXE="$exePath"\n'
        'relaunch() { chmod +x "\$EXE" 2>/dev/null; "\$EXE" & }\n'
        'if command -v rsync >/dev/null 2>&1; then\n'
        '  rm -rf "\$BAK"; mkdir -p "\$BAK"\n'
        '  rsync -a --exclude="*.db" --exclude="*.db-wal" --exclude="*.db-shm" "\$APP/" "\$BAK/" || { relaunch; rm -- "\$0"; exit 0; }\n'
        '  if rsync -a --exclude="*.db" --exclude="*.db-wal" --exclude="*.db-shm" "\$SRC/" "\$APP/"; then\n'
        '    rm -rf "\$BAK" "$extractPath"\n'
        '  else\n'
        '    rsync -a "\$BAK/" "\$APP/"\n'  // rollback
        '  fi\n'
        'else\n'
        '  cp -rf "\$SRC/." "\$APP/" || true\n'
        'fi\n'
        'relaunch\n'
        'rm -- "\$0"\n';

    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);
    await Process.start('sh', [scriptPath], mode: ProcessStartMode.detached);
  }

  /// If the extracted archive wrapped everything in a single top-level folder
  /// (e.g. `Release\app.exe` instead of `app.exe` at the root), descend into it
  /// so files land at the app root rather than nested under a wrapper dir —
  /// otherwise the copy is a silent no-op and the old version relaunches.
  static String _resolveUpdateSource(String extractPath) {
    try {
      final entries = Directory(extractPath).listSync();
      if (entries.length == 1 && entries.first is Directory) {
        return entries.first.path;
      }
    } catch (_) {}
    return extractPath;
  }

  /// Probe whether [dir] is writable by the current (non-elevated) process.
  /// Used to decide whether the updater must self-elevate.
  static Future<bool> _isDirWritable(String dir) async {
    try {
      final probe = File(
          _sJoin(dir, '.upd_write_test_${DateTime.now().microsecondsSinceEpoch}'));
      await probe.writeAsString('x', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _join(String base, String name) =>
      '$base${Platform.pathSeparator}$name';

  // Static version of _join for use in static methods.
  static String _sJoin(String base, String name) =>
      '$base${Platform.pathSeparator}$name';

  Future<void> _writeMarker(
      String tmpPath, UpdateInfo info, String filePath) async {
    final markerPath = _join(tmpPath, 'caisse212-update.ready');
    await File(markerPath).writeAsString(jsonEncode({
      'version': info.version,
      'buildNumber': info.buildNumber,
      'path': filePath,
    }));
  }

  Future<void> _download(
    String url,
    String savePath,
    Function(double)? onProgress,
  ) async {
    await _apiService.dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
      options: Options(receiveTimeout: const Duration(minutes: 15)),
    );
    _logger.info('Download complete: $savePath');
  }

  Future<void> _verifyChecksum(File file, String expected) async {
    if (expected.isEmpty) return;
    final bytes = await file.readAsBytes();
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      await file.delete();
      throw Exception('Checksum mismatch — expected $expected, got $actual');
    }
    _logger.info('Checksum OK');
  }

  Future<void> cleanup() async {
    try {
      final tmp = await getTemporaryDirectory();
      for (final name in ['caisse212-update.apk', 'caisse212-update.zip']) {
        final f = File(_join(tmp.path, name));
        if (await f.exists()) {
          await f.delete();
          _logger.info('Cleaned up: $name');
        }
      }
      final extractDir = Directory(_join(tmp.path, 'caisse212-update-extracted'));
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
        _logger.info('Cleaned up extract dir');
      }
    } catch (e) {
      _logger.error('Cleanup failed: $e');
    }
  }
}
