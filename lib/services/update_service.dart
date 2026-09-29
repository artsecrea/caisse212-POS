import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart' as ed;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'update_config.dart';

/// A release the updates service offered. Every field except [releaseNotes]
/// comes from the manifest, never from the loose body fields.
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
  final SharedPreferences _prefs;
  final _logger = Logger.instance;

  // Separate from ApiService.dio on purpose: the updates service takes no JWT,
  // and BMS headers must not leak to it or to the binaries host.
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    validateStatus: (code) => code != null && code < 500,
  ));

  final Map<String, String> _pinnedKeys;

  UpdateService(this._apiService, this._prefs,
      {Map<String, String> pinnedKeys = UpdateConfig.pinnedKeys})
      : _pinnedKeys = pinnedKeys;

  static String get currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static bool get platformSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isAndroid;

  String get baseUrl {
    final raw = _prefs.getString(UpdateConfig.baseUrlPrefKey) ??
        UpdateConfig.defaultBaseUrl;
    return raw.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> setBaseUrl(String url) =>
      _prefs.setString(UpdateConfig.baseUrlPrefKey, url.trim());

  String get appSlug {
    final raw =
        _prefs.getString(UpdateConfig.appSlugPrefKey)?.trim().toLowerCase() ??
            '';
    return raw.isEmpty ? UpdateConfig.defaultAppSlug : raw;
  }

  /// Empty resets to [UpdateConfig.defaultAppSlug].
  Future<void> setAppSlug(String slug) =>
      _prefs.setString(UpdateConfig.appSlugPrefKey, slug.trim());

  // ── Check ──────────────────────────────────────────────────────────────────

  /// `GET {base}/v1/{app}/{platform}/latest`. 404 = nothing newer for this
  /// till. A 200 is only trusted after [verify]; anything off returns null.
  Future<UpdateInfo?> checkForUpdates({required int installedBuild}) async {
    if (!platformSupported) return null;
    final base = baseUrl;
    if (base.isEmpty) {
      _logger.info('Update check skipped: no updates server configured');
      return null;
    }

    // Sent exactly as stored (Dio URL-encodes). business and terminal only
    // travel together — the server matches terminal stages on the pair.
    final query = <String, dynamic>{'build': installedBuild};
    final tenant = _apiService.getTenantId();
    if (tenant != null) query['tenant'] = tenant;
    final business = _apiService.getBusinessId();
    final terminal = _apiService.getPosName();
    if (business != null && terminal != null) {
      query['business'] = business;
      query['terminal'] = terminal;
    }

    try {
      final response = await _dio.get(
        '$base/v1/${Uri.encodeComponent(appSlug)}/$currentPlatform/latest',
        queryParameters: query,
      );

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        _logger.warning('Update check returned HTTP ${response.statusCode}');
        return null;
      }

      final data = response.data;
      if (data is! Map<String, dynamic> || data.isEmpty) return null;

      final info = await verify(data, installedBuild);
      if (info != null) {
        _logger.info('Update available: ${info.version}+${info.buildNumber}');
      }
      return info;
    } on DioException catch (e) {
      _logger.error('Update check failed: ${e.message}');
      return null;
    } catch (e) {
      _logger.error('Update check failed: $e');
      return null;
    }
  }

  @visibleForTesting
  Future<UpdateInfo?> verify(
      Map<String, dynamic> body, int installedBuild) async {
    final manifestB64 = body['manifest'] as String?;
    if (manifestB64 == null || manifestB64.isEmpty) {
      _logger.warning('Update rejected: no manifest');
      return null;
    }
    final manifestBytes = base64.decode(manifestB64);

    // Signing was dropped server-side (owner's decision, 2026-09-29): releases
    // arrive with empty kid/signature and are trusted as served. A signature
    // from a pinned key is still checked, so a tampered signed release fails.
    final kid = body['kid'] as String? ?? '';
    final signatureB64 = body['signature'] as String? ?? '';
    final pub = _pinnedKeys[kid];
    if (pub != null && signatureB64.isNotEmpty) {
      final ok = await ed.Ed25519().verify(
        manifestBytes,
        signature: ed.Signature(
          base64.decode(signatureB64),
          publicKey: ed.SimplePublicKey(base64.decode(pub),
              type: ed.KeyPairType.ed25519),
        ),
      );
      if (!ok) {
        _logger.warning('Update rejected: bad signature (kid $kid)');
        return null;
      }
    }

    final m = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    if (m['app'] != appSlug || m['platform'] != currentPlatform) {
      _logger.warning(
          'Update rejected: manifest is for ${m['app']}/${m['platform']}');
      return null;
    }
    final build = (m['buildNumber'] as num?)?.toInt() ?? 0;
    if (build <= installedBuild) return null;

    final sha = m['sha256'] as String? ?? '';
    final size = (m['sizeBytes'] as num?)?.toInt();
    if (sha.isEmpty || size == null || size <= 0) {
      _logger.warning('Update rejected: manifest lacks sha256/sizeBytes');
      return null;
    }

    return UpdateInfo(
      version: m['version'] as String,
      buildNumber: build,
      downloadUrl: m['downloadUrl'] as String,
      checksum: sha,
      isMandatory: m['mandatory'] as bool? ?? false,
      sizeBytes: size,
      releaseNotes: body['releaseNotes'] as String?,
    );
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
      await _verifyChecksum(file, info);
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
    await _verifyChecksum(zipFile, info);

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

      final launched = Platform.isWindows
          ? await _launchWindowsBat(filePath, appDir, exePath, tmp.path)
          : await _launchUnixSh(filePath, appDir, exePath, tmp.path);

      // If the updater couldn't be launched — e.g. UAC elevation was DECLINED on
      // a Program Files install — do NOT exit. Exiting here would close the POS
      // without relaunching or updating. Continue on the current version; the
      // staged update was already discarded (marker deleted above) and will
      // re-stage on the next check.
      if (!launched) {
        Logger.instance
            .warning('Update apply not launched — staying on current version');
        return;
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

  /// Returns true when an updater process was actually launched (so the caller
  /// may exit and let it take over). Returns false when elevation was declined
  /// / the launch failed — the caller must then stay running so the POS doesn't
  /// close without relaunching.
  static Future<bool> _launchWindowsBat(
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
      // Delayed expansion is required by :relaunch, which reads a variable it
      // set inside the same parenthesised block.
      ..write('setlocal enabledelayedexpansion\r\n')
      // Give the exiting app time to release its .exe/.dll handles. `ping` is
      // used instead of `timeout` because `timeout` needs a console, which a
      // detached process may not have.
      ..write('ping -n 4 127.0.0.1 >nul\r\n')
      // Note the exe the NEW build ships, before anything is copied or cleaned
      // up. robocopy below is additive (no /PURGE), so a release that renames
      // the binary leaves the old .exe sitting next to the new one — the old
      // path still "exists" and blindly relaunching it would pair a stale
      // binary with the freshly copied data\flutter_assets, a snapshot mismatch
      // that does not boot. A Flutter Windows bundle has exactly one top-level
      // .exe, so this reads the intended target unambiguously.
      ..write('set NEXCOUNT=0\r\n')
      ..write('for %%F in ("${w(source)}\\*.exe") do '
          '(set /a NEXCOUNT+=1 >nul & if not defined NEWEXE '
          'set "NEWEXE=%%~nxF")\r\n')
      ..write('echo [%date% %time%] backup >"${w(logPath)}"\r\n')
      // 1. Back up the current install so a failed copy can be rolled back.
      ..write('rmdir /s /q "${w(backupDir)}" 2>nul\r\n')
      ..write('robocopy "${w(appDir)}" "${w(backupDir)}" $robo $excl >>"${w(logPath)}" 2>&1\r\n')
      ..write('if %ERRORLEVEL% geq 8 goto backup_failed\r\n')
      // 2. Apply the update over the install.
      ..write('echo [%date% %time%] apply >>"${w(logPath)}"\r\n')
      ..write('robocopy "${w(source)}" "${w(appDir)}" $robo $excl >>"${w(logPath)}" 2>&1\r\n')
      ..write('if %ERRORLEVEL% geq 8 goto copy_failed\r\n')
      // 3. Success — relaunch (see :relaunch), clean temp, self-delete.
      ..write('echo [%date% %time%] ok >>"${w(logPath)}"\r\n')
      ..write('rmdir /s /q "${w(backupDir)}" 2>nul\r\n')
      ..write('rmdir /s /q "${w(extractPath)}" 2>nul\r\n')
      ..write('call :relaunch_new\r\n')
      ..write('goto done\r\n')
      // Rollback: restore the backup over the partial copy, then relaunch old.
      ..write(':copy_failed\r\n')
      ..write('echo [%date% %time%] copy failed, rolling back >>"${w(logPath)}"\r\n')
      ..write('robocopy "${w(backupDir)}" "${w(appDir)}" $robo $excl >>"${w(logPath)}" 2>&1\r\n')
      ..write('call :relaunch_old\r\n')
      ..write('goto done\r\n')
      // Backup failed before any change was made — safe to just relaunch old.
      ..write(':backup_failed\r\n')
      ..write('echo [%date% %time%] backup failed, aborting (no changes) >>"${w(logPath)}"\r\n')
      ..write('call :relaunch_old\r\n')
      ..write(':done\r\n')
      ..write('(goto) 2>nul & del "%~f0"\r\n')
      // Launch the binary the update just installed. Same name as before in
      // every normal release, so RELAUNCH stays exactly what it always was.
      ..write(':relaunch_new\r\n')
      ..write('set "RELAUNCH=${w(exePath)}"\r\n')
      ..write('for %%F in ("${w(exePath)}") do set "OLDEXE=%%~nxF"\r\n')
      ..write('if "!NEXCOUNT!"=="1" if defined NEWEXE '
          'if exist "${w(appDir)}\\!NEWEXE!" '
          'set "RELAUNCH=${w(appDir)}\\!NEWEXE!"\r\n')
      // On a rename, drop the superseded binary. Leaving it means a desktop
      // shortcut still pointing at the old name would launch a stale exe over
      // the new assets; a shortcut that fails outright is the better failure.
      // Gated on the new build shipping exactly ONE exe — anything ambiguous
      // deletes nothing and keeps the old behaviour.
      ..write('if "!NEXCOUNT!"=="1" if defined NEWEXE '
          'if /i not "!NEWEXE!"=="!OLDEXE!" '
          'if exist "${w(appDir)}\\!NEWEXE!" del /f /q "${w(exePath)}" 2>nul\r\n')
      ..write('goto :launch\r\n')
      // Rollback paths: the backup was restored, so the ORIGINAL exe is the
      // only one that matches what is now on disk.
      ..write(':relaunch_old\r\n')
      ..write('set "RELAUNCH=${w(exePath)}"\r\n')
      ..write(':launch\r\n')
      // explorer.exe launches the app as the interactive (non-elevated) user
      // even when this script is running elevated.
      ..write('explorer.exe "!RELAUNCH!"\r\n')
      ..write('exit /b\r\n');

    await File(scriptPath).writeAsString(script.toString());

    if (await _isDirWritable(appDir)) {
      await Process.start(
        'cmd',
        ['/c', w(scriptPath)],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return true;
    }

    // Protected location (e.g. Program Files): elevate via UAC, otherwise
    // robocopy hits Access Denied on every file and the update silently fails.
    // Run the launcher NON-detached and await its exit code so a DECLINED UAC
    // prompt is detectable — `Start-Process -Verb RunAs` throws (non-zero exit)
    // when the user cancels. We must know that so the caller doesn't close the
    // app after a failed elevation.
    Logger.instance.info('App dir not writable — launching elevated updater');
    final ps = "Start-Process -WindowStyle Hidden -FilePath 'cmd.exe' "
        "-ArgumentList '/c','\"${w(scriptPath)}\"' -Verb RunAs";
    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
          '-Command', ps],
        runInShell: false,
      );
      if (result.exitCode != 0) {
        Logger.instance.warning(
            'Elevated updater not started (UAC declined?) exit=${result.exitCode}');
        return false;
      }
      return true;
    } catch (e) {
      Logger.instance.error('Failed to launch elevated updater: $e');
      return false;
    }
  }

  static Future<bool> _launchUnixSh(
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
        // Same additive-copy hazard as the Windows path: rsync and cp both run
        // without --delete, so a release that renames the binary leaves the old
        // one sitting beside the new one. Relaunching it would pair a stale
        // binary with the freshly copied data/ — adopt the exe the new build
        // actually shipped, and drop the superseded one so a stale launcher
        // fails outright rather than starting a mismatched app. Must run before
        // SRC is cleaned up.
        // Identified by "the one extensionless regular file at the top level" —
        // a Flutter Linux bundle holds exactly that plus data/ and lib/. The
        // executable bit is deliberately NOT used as the test: archive
        // extraction routinely drops it, which is why relaunch() has always had
        // to chmod +x first. If the layout is ever ambiguous (0 or >1
        // candidates) this does nothing and the old path is kept.
        'adopt_new_exe() {\n'
        '  c=""; k=0\n'
        '  for f in "\$SRC"/*; do\n'
        '    [ -f "\$f" ] || continue\n'
        '    b=\$(basename "\$f")\n'
        '    case "\$b" in *.*) continue ;; esac\n'
        '    c="\$b"; k=\$((k+1))\n'
        '  done\n'
        '  [ "\$k" = 1 ] || return\n'
        '  [ "\$c" != "\$(basename "\$EXE")" ] || return\n'
        '  [ -f "\$APP/\$c" ] || return\n'
        '  rm -f "\$EXE"; EXE="\$APP/\$c"\n'
        '}\n'
        'if command -v rsync >/dev/null 2>&1; then\n'
        '  rm -rf "\$BAK"; mkdir -p "\$BAK"\n'
        '  rsync -a --exclude="*.db" --exclude="*.db-wal" --exclude="*.db-shm" "\$APP/" "\$BAK/" || { relaunch; rm -- "\$0"; exit 0; }\n'
        '  if rsync -a --exclude="*.db" --exclude="*.db-wal" --exclude="*.db-shm" "\$SRC/" "\$APP/"; then\n'
        '    adopt_new_exe\n'
        '    rm -rf "\$BAK" "$extractPath"\n'
        '  else\n'
        '    rsync -a "\$BAK/" "\$APP/"\n'  // rollback — original EXE is correct
        '  fi\n'
        'else\n'
        '  cp -rf "\$SRC/." "\$APP/" || true\n'
        '  adopt_new_exe\n'
        'fi\n'
        'relaunch\n'
        'rm -- "\$0"\n';

    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);
    await Process.start('sh', [scriptPath], mode: ProcessStartMode.detached);
    return true;
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
    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 15),
        validateStatus: (code) => code == 200,
      ),
    );
    _logger.info('Download complete: $savePath');
  }

  /// Size and sha256 both come from the signed manifest, so a matching file is
  /// byte-for-byte the release that was signed.
  Future<void> _verifyChecksum(File file, UpdateInfo info) async {
    final size = await file.length();
    if (info.sizeBytes != null && size != info.sizeBytes) {
      await file.delete();
      throw Exception('Size mismatch — expected ${info.sizeBytes}, got $size');
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual.toLowerCase() != info.checksum.toLowerCase()) {
      await file.delete();
      throw Exception(
          'Checksum mismatch — expected ${info.checksum}, got $actual');
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
