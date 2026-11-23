import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart' as ed;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'update_config.dart';

/// Outcome of one check. [answered] is false when the server could not be
/// reached or answered garbage — the caller must not count that as the day's
/// check, nor treat it as "the release was withdrawn".
class UpdateCheck {
  final bool answered;
  final UpdateInfo? info;
  const UpdateCheck(this.answered, [this.info]);
}

/// An update downloaded (and extracted, on desktop) waiting to be installed.
class StagedUpdate {
  final String version;
  final int buildNumber;
  final String path;
  final int attempts;
  const StagedUpdate(this.version, this.buildNumber, this.path, this.attempts);
}

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
    final stored = _prefs.getString(UpdateConfig.baseUrlPrefKey)?.trim() ?? '';
    final raw = stored.isEmpty ? UpdateConfig.defaultBaseUrl : stored;
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  bool get usesDefaultBaseUrl =>
      (_prefs.getString(UpdateConfig.baseUrlPrefKey)?.trim() ?? '').isEmpty;

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

  /// One-time: drops a URL override saved by an older build (a LAN or test
  /// server) so the till follows [UpdateConfig.defaultBaseUrl].
  Future<void> bakeDefaultBaseUrl() async {
    if (_prefs.getBool(UpdateConfig.baseUrlBakedPrefKey) == true) return;
    final stored = _prefs.getString(UpdateConfig.baseUrlPrefKey)?.trim() ?? '';
    if (stored.isNotEmpty) {
      _logger.info('Updates server override "$stored" cleared — using ${UpdateConfig.defaultBaseUrl}');
      await _prefs.remove(UpdateConfig.baseUrlPrefKey);
    }
    await _prefs.setBool(UpdateConfig.baseUrlBakedPrefKey, true);
  }

  int get checkHours =>
      _prefs.getInt(UpdateConfig.checkHoursPrefKey) ??
      UpdateConfig.defaultCheckHours;

  Future<void> setCheckHours(int hours) =>
      _prefs.setInt(UpdateConfig.checkHoursPrefKey, hours);

  bool get installOnStart =>
      _prefs.getBool(UpdateConfig.installOnStartPrefKey) ?? true;

  Future<void> setInstallOnStart(bool value) =>
      _prefs.setBool(UpdateConfig.installOnStartPrefKey, value);

  bool get notify => _prefs.getBool(UpdateConfig.notifyPrefKey) ?? true;

  Future<void> setNotify(bool value) =>
      _prefs.setBool(UpdateConfig.notifyPrefKey, value);

  DateTime? get lastCheck {
    final ms = _prefs.getInt(UpdateConfig.lastCheckPrefKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // ── Check ──────────────────────────────────────────────────────────────────

  Future<UpdateInfo?> checkForUpdates({required int installedBuild}) async =>
      (await check(installedBuild: installedBuild)).info;

  /// `GET {base}/v1/{app}/{platform}/latest`. 404 = nothing newer for this
  /// till. A 200 is only trusted after [verify]; anything off returns no info.
  Future<UpdateCheck> check({required int installedBuild}) async {
    if (!platformSupported) return const UpdateCheck(false);
    final base = baseUrl;

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

      if (response.statusCode == 404) return const UpdateCheck(true);
      if (response.statusCode != 200) {
        _logger.warning('Update check returned HTTP ${response.statusCode}');
        return const UpdateCheck(false);
      }

      final data = response.data;
      if (data is! Map<String, dynamic> || data.isEmpty) {
        return const UpdateCheck(false);
      }

      final info = await verify(data, installedBuild);
      if (info != null) {
        _logger.info('Update available: ${info.version}+${info.buildNumber}');
      }
      return UpdateCheck(true, info);
    } on DioException catch (e) {
      _logger.error('Update check failed: ${e.message}');
      return const UpdateCheck(false);
    } catch (e) {
      _logger.error('Update check failed: $e');
      return const UpdateCheck(false);
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

  /// Downloads the update and stages it for the next restart.
  ///
  /// Android  — downloads APK to temp, verifies checksum, writes marker.
  /// Desktop  — downloads ZIP, extracts to temp, deletes ZIP, writes marker.
  ///
  /// Does NOT close the app. [applyStaged] installs it — at the next launch
  /// (from `main`) or right away when someone asks to restart.
  ///
  /// Throws on network or checksum failure.
  Future<void> downloadAndPrepare(
    UpdateInfo info, {
    Function(double)? onProgress,
  }) async {
    if (Platform.isIOS) return;

    // Whatever was staged before is superseded; drop it first so a failure
    // below can never leave the old marker pointing at half-written files.
    await discardStaged();
    final tmp = await getTemporaryDirectory();

    if (Platform.isAndroid) {
      final apkPath = _sJoin(tmp.path, _apkName);
      await _download(info, apkPath, onProgress);
      await _verifyChecksum(File(apkPath), info);
      await _writeMarker(tmp.path, info.version, info.buildNumber, apkPath, 0);
      return;
    }

    final zipPath = _sJoin(tmp.path, _zipName);
    final extractPath = _sJoin(tmp.path, _extractName);
    final zipFile = File(zipPath);

    await _download(info, zipPath, onProgress);
    await _verifyChecksum(zipFile, info);

    _logger.info('Extracting to: $extractPath');
    await Directory(extractPath).create(recursive: true);
    // Decoding a 30+ MB zip on the UI isolate freezes the till for seconds,
    // and this runs in the background while someone is taking orders.
    await _extract(zipPath, extractPath);
    await zipFile.delete();

    await _writeMarker(
        tmp.path, info.version, info.buildNumber, extractPath, 0);
    _logger.info('Update ${info.version} ready — will apply on next restart');
  }

  static Future<void> _extract(String zipPath, String extractPath) =>
      Isolate.run(() => extractFileToDisk(zipPath, extractPath));

  // ── Staged update ─────────────────────────────────────────────────────────

  static const _markerName = 'caisse212-update.ready';
  static const _zipName = 'caisse212-update.zip';
  static const _apkName = 'caisse212-update.apk';
  static const _extractName = 'caisse212-update-extracted';

  /// The staged update, or null. A marker that is unreadable, points at files
  /// that are gone (temp cleaned), or is not newer than what is installed
  /// (i.e. it was just applied) is discarded here.
  static Future<StagedUpdate?> readStaged() async {
    try {
      final tmp = await getTemporaryDirectory();
      final marker = File(_sJoin(tmp.path, _markerName));
      if (!await marker.exists()) return null;
      final raw =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      final path = raw['path'] as String?;
      final build = (raw['buildNumber'] as num?)?.toInt() ?? 0;
      final installed = await installedBuild();
      final present = path != null &&
          await FileSystemEntity.type(path) != FileSystemEntityType.notFound;
      if (!present || (installed > 0 && build <= installed)) {
        Logger.instance.info(
            'Discarding staged update $build (installed $installed, files ${present ? 'present' : 'missing'})');
        await discardStaged();
        return null;
      }
      return StagedUpdate(raw['version'] as String? ?? '?', build, path,
          (raw['attempts'] as num?)?.toInt() ?? 0);
    } catch (e) {
      Logger.instance.warning('Unreadable staged update, discarding: $e');
      await discardStaged();
      return null;
    }
  }

  /// Removes the marker and every staged file.
  static Future<void> discardStaged() async {
    try {
      final tmp = await getTemporaryDirectory();
      for (final name in [_markerName, _zipName, _apkName]) {
        final f = File(_sJoin(tmp.path, name));
        if (await f.exists()) await f.delete();
      }
      final dir = Directory(_sJoin(tmp.path, _extractName));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      Logger.instance.error('Discarding staged update failed: $e');
    }
  }

  /// 0 when it can't be read — callers then never treat a staged update as
  /// "already installed".
  static Future<int> installedBuild() async {
    try {
      final info =
          await PackageInfo.fromPlatform().timeout(const Duration(seconds: 5));
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Apply ─────────────────────────────────────────────────────────────────

  /// Called at the very start of `main()` after `WidgetsFlutterBinding`.
  /// If an update is staged, launches the updater and exits; otherwise (or on
  /// any error) returns so normal startup continues.
  static Future<void> applyPendingUpdateIfExists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(UpdateConfig.installOnStartPrefKey) == false) return;
    } catch (_) {}
    await applyStaged();
  }

  /// Installs the staged update: launches the updater script, which waits for
  /// this process to exit, copies the new files, and relaunches. Exits the app
  /// when the updater started; returns false when nothing was launched (no
  /// staged update, UAC declined, too many failed attempts) so the caller keeps
  /// running on the current version.
  ///
  /// The marker stays in place while the updater runs and is only removed by
  /// the script on success (or by [readStaged] once the new build is running).
  /// A rolled-back copy therefore relaunches the old build with the marker
  /// still there, and it tries again — at most [UpdateConfig.maxApplyAttempts]
  /// times, then the staged files are thrown away.
  static Future<bool> applyStaged({bool interactive = false}) async {
    try {
      final staged = await readStaged();
      if (staged == null) return false;
      final tmp = await getTemporaryDirectory();

      if (staged.attempts >= UpdateConfig.maxApplyAttempts) {
        Logger.instance.warning(
            'Update ${staged.version} failed to install ${staged.attempts} times — discarding it');
        await discardStaged();
        return false;
      }
      await _writeMarker(tmp.path, staged.version, staged.buildNumber,
          staged.path, staged.attempts + 1);

      if (Platform.isIOS) return false;

      if (Platform.isAndroid) {
        final result = await OpenFilex.open(staged.path);
        if (result.type != ResultType.done) return false;
        exit(0);
      }

      final exePath = Platform.resolvedExecutable;
      final appDir = File(exePath).parent.path;
      Logger.instance.info(
          'Applying update ${staged.version} (attempt ${staged.attempts + 1}) from ${staged.path}');

      final launched = Platform.isWindows
          ? await _launchWindows(
              staged.path, appDir, exePath, tmp.path, staged.version)
          : await _launchUnixSh(staged.path, appDir, exePath, tmp.path);

      // If the updater couldn't be launched — e.g. UAC elevation was DECLINED
      // on a Program Files install — do NOT exit: that would close the POS
      // without relaunching or updating.
      if (!launched) {
        Logger.instance
            .warning('Update apply not launched — staying on current version');
        // A refused UAC prompt after "Restart now" is the person's answer,
        // not a broken update, so it doesn't use up an attempt.
        if (interactive) {
          await _writeMarker(tmp.path, staged.version, staged.buildNumber,
              staged.path, staged.attempts);
        }
        return false;
      }

      await Future.delayed(const Duration(milliseconds: 600));
      exit(0);
    } catch (e) {
      // Never block normal startup.
      Logger.instance.error('Applying staged update failed: $e');
      return false;
    }
  }

  /// Returns the version string of the staged update, or null.
  static Future<String?> pendingUpdateVersion() async =>
      (await readStaged())?.version;

  // ── Updater scripts ────────────────────────────────────────────────────────

  static const _updaterExe = 'caisse212-updater.exe';

  /// The updater window (windows/updater/caisse212_updater.cs) when a build
  /// ships it: no console windows, a progress bar. Builds without it — dev
  /// runs, older packages — keep the .bat.
  static Future<bool> _launchWindows(String extractPath, String appDir,
      String exePath, String tmpPath, String version) async {
    final updater = await _stageUpdaterExe(extractPath, appDir, tmpPath);
    if (updater == null) {
      return _launchWindowsBat(extractPath, appDir, exePath, tmpPath);
    }
    String lang = 'fr';
    try {
      final prefs = await SharedPreferences.getInstance();
      lang = prefs.getString('language') ?? lang;
    } catch (_) {}
    final args = [
      '--source', _resolveUpdateSource(extractPath).replaceAll('/', '\\'),
      '--extract', extractPath.replaceAll('/', '\\'),
      '--app-dir', appDir.replaceAll('/', '\\'),
      '--exe', exePath.replaceAll('/', '\\'),
      '--tmp', tmpPath.replaceAll('/', '\\'),
      '--marker', _sJoin(tmpPath, _markerName).replaceAll('/', '\\'),
      '--pid', '$pid',
      '--version', version,
      '--lang', lang,
    ];
    try {
      if (await _isDirWritable(appDir)) {
        await Process.start(updater, args,
            mode: ProcessStartMode.detached, runInShell: false);
        return true;
      }
      // Protected install (Program Files): the updater asks UAC for itself
      // and answers 0 once the elevated copy is running, 2 when declined.
      Logger.instance.info('App dir not writable — launching elevated updater');
      final result =
          await Process.run(updater, ['--elevate', ...args], runInShell: false);
      if (result.exitCode != 0) {
        Logger.instance.warning(
            'Elevated updater not started (UAC declined?) exit=${result.exitCode}');
        return false;
      }
      return true;
    } catch (e) {
      Logger.instance.error('Updater window failed to start: $e — using the script');
      return _launchWindowsBat(extractPath, appDir, exePath, tmpPath);
    }
  }

  /// Copies the updater to [tmpPath] (it must not run from a folder it is
  /// about to overwrite or delete). The new build's copy wins over the
  /// installed one. Null when neither exists or the copy failed.
  static Future<String?> _stageUpdaterExe(
      String extractPath, String appDir, String tmpPath) async {
    final candidates = [
      _sJoin(_sJoin(_resolveUpdateSource(extractPath), 'updater'), _updaterExe),
      _sJoin(_sJoin(appDir, 'updater'), _updaterExe),
    ];
    for (final path in candidates) {
      if (!await File(path).exists()) continue;
      try {
        final target = _sJoin(tmpPath, _updaterExe);
        await File(path).copy(target);
        return target;
      } catch (e) {
        Logger.instance.warning('Could not stage the updater from $path: $e');
      }
    }
    return null;
  }

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
    await File(scriptPath).writeAsString(
        windowsUpdaterScript(extractPath, appDir, exePath, tmpPath, pid));

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

  /// The updater .bat: waits for [myPid] to exit, backs up, copies the new
  /// build over [appDir], rolls back on failure, relaunches.
  @visibleForTesting
  static String windowsUpdaterScript(String extractPath, String appDir,
      String exePath, String tmpPath, int myPid) {
    String w(String p) => p.replaceAll('/', '\\');
    final logPath = _sJoin(tmpPath, 'caisse212-update.log');
    final backupDir = _sJoin(tmpPath, 'caisse212-update-backup');
    final markerPath = _sJoin(tmpPath, _markerName);
    final source = _resolveUpdateSource(extractPath);
    final appSupport = '${w(appDir)}\\support';
    final srcSupport = '${w(source)}\\support';

    // robocopy tuning:
    //  /E                copy subdirs incl. empty (additive — never deletes
    //                    destination files absent from source, so files the
    //                    admin put in the install folder survive).
    //  /IS /IT           overwrite same/tweaked files (force new binaries in).
    //  /R:3 /W:2         bound retries — the DEFAULT is /R:1000000 /W:30, which
    //                    hangs effectively forever if any file is briefly
    //                    locked (AV / slow handle release), so the app would
    //                    never relaunch. Cap it hard.
    //  /XF *.db*         belt-and-braces: never copy a DB over a live one.
    const robo = '/E /IS /IT /R:3 /W:2 /NFL /NDL /NJH /NJS /NC /NS';
    const excl = '/XF "*.db" "*.db-wal" "*.db-shm"';

    // robocopy success is exit code < 8; >= 8 means at least one file failed.
    final script = StringBuffer()
      ..write('@echo off\r\n')
      // Delayed expansion is required by :relaunch, which reads a variable it
      // set inside the same parenthesised block.
      ..write('setlocal enabledelayedexpansion\r\n')
      // Full paths: a PATH carrying Git/MSYS tools puts a Unix `find`
      // first, and every process check below silently never matches.
      ..write('set "SYS=%SystemRoot%\\System32"\r\n')
      ..write('echo [%date% %time%] waiting for pid $myPid >"${w(logPath)}"\r\n')
      // Wait for THIS process to be gone, not a fixed delay: the exe is
      // single-instance, so relaunching while the old one is still shutting
      // down makes the new one see the mutex, focus a dying window and quit —
      // the till then stays closed. Also its files stay locked until it exits.
      // `ping` is the sleep because `timeout` needs a console, which a
      // detached process may not have.
      //
      // Process checks read tasklist through `for /f`, never `| find`: the
      // app starts this script detached (no console), and there a piped
      // find.exe never sees end-of-input — the update hung on it forever.
      // %SYS% stays unquoted inside the for /f command (quoting it there
      // breaks the 2^>nul); System32 has no spaces.
      ..write('set /a WAITN=0\r\n')
      ..write(':waitexit\r\n')
      ..write('set "ALIVE="\r\n')
      ..write('''for /f "tokens=2 delims=," %%A in ('%SYS%\\tasklist.exe /FI "PID eq $myPid" /FO CSV /NH 2^>nul') do if "%%~A"=="$myPid" set "ALIVE=1"\r\n''')
      ..write('if not defined ALIVE goto exited\r\n')
      ..write('set /a WAITN+=1\r\n')
      ..write('if !WAITN! geq 30 goto killit\r\n')
      ..write('"%SYS%\\PING.EXE" -n 2 127.0.0.1 >nul\r\n')
      ..write('goto waitexit\r\n')
      ..write(':killit\r\n')
      ..write('echo [%date% %time%] still running, killing >>"${w(logPath)}"\r\n')
      ..write('"%SYS%\\taskkill.exe" /F /PID $myPid >nul 2>&1\r\n')
      ..write('"%SYS%\\PING.EXE" -n 3 127.0.0.1 >nul\r\n')
      ..write(':exited\r\n')
      // A moment more for the OS to release the exe/dll handles.
      ..write('"%SYS%\\PING.EXE" -n 2 127.0.0.1 >nul\r\n')
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
      ..write('echo [%date% %time%] backup >>"${w(logPath)}"\r\n')
      // 1. Back up the current install so a failed copy can be rolled back.
      // support\ (the remote-support tool) is handled on its own below.
      ..write('rmdir /s /q "${w(backupDir)}" 2>nul\r\n')
      ..write('"%SYS%\\Robocopy.exe" "${w(appDir)}" "${w(backupDir)}" $robo $excl /XD "$appSupport" >>"${w(logPath)}" 2>&1\r\n')
      ..write('if %ERRORLEVEL% geq 8 goto backup_failed\r\n')
      // 2. Apply the update over the install.
      ..write('echo [%date% %time%] apply >>"${w(logPath)}"\r\n')
      ..write('"%SYS%\\Robocopy.exe" "${w(source)}" "${w(appDir)}" $robo $excl /XD "$srcSupport" >>"${w(logPath)}" 2>&1\r\n')
      ..write('if %ERRORLEVEL% geq 8 goto copy_failed\r\n')
      // 2b. The remote-support tool is started detached so a support session
      // outlives a POS update — its exe is then locked. Copying it would fail
      // and roll back the whole POS update over a side tool, so it is only
      // refreshed when it isn't running; otherwise the next update gets it.
      ..write('if not exist "$srcSupport" goto support_done\r\n')
      ..write('set "SUPBUSY="\r\n')
      ..write('''for %%I in (caisse212-support.exe caisse212-tech.exe) do for /f "delims=," %%A in ('%SYS%\\tasklist.exe /FI "IMAGENAME eq %%I" /FO CSV /NH 2^>nul') do if /i "%%~A"=="%%I" set "SUPBUSY=1"\r\n''')
      ..write('if defined SUPBUSY goto support_busy\r\n')
      ..write('"%SYS%\\Robocopy.exe" "$srcSupport" "$appSupport" $robo >>"${w(logPath)}" 2>&1\r\n')
      ..write('if %ERRORLEVEL% geq 8 echo [%date% %time%] support copy incomplete >>"${w(logPath)}"\r\n')
      ..write('goto support_done\r\n')
      ..write(':support_busy\r\n')
      ..write('echo [%date% %time%] support tool running, kept as is >>"${w(logPath)}"\r\n')
      ..write(':support_done\r\n')
      // 3. Success — clear the marker, relaunch (see :relaunch), clean temp,
      // self-delete.
      ..write('echo [%date% %time%] ok >>"${w(logPath)}"\r\n')
      ..write('del /f /q "${w(markerPath)}" 2>nul\r\n')
      ..write('rmdir /s /q "${w(backupDir)}" 2>nul\r\n')
      ..write('rmdir /s /q "${w(extractPath)}" 2>nul\r\n')
      ..write('call :relaunch_new\r\n')
      ..write('goto done\r\n')
      // Rollback: restore the backup over the partial copy, then relaunch old.
      // The marker stays, so the old build retries (bounded by its attempts).
      ..write(':copy_failed\r\n')
      ..write('echo [%date% %time%] copy failed, rolling back >>"${w(logPath)}"\r\n')
      ..write('"%SYS%\\Robocopy.exe" "${w(backupDir)}" "${w(appDir)}" $robo $excl >>"${w(logPath)}" 2>&1\r\n')
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

    return script.toString();
  }

  static Future<bool> _launchUnixSh(
    String extractPath,
    String appDir,
    String exePath,
    String tmpPath,
  ) async {
    final scriptPath = _sJoin(tmpPath, 'caisse212-updater.sh');
    final backupDir = _sJoin(tmpPath, 'caisse212-update-backup');
    final markerPath = _sJoin(tmpPath, _markerName);
    final source = _resolveUpdateSource(extractPath);

    // Prefer rsync (atomic-ish, supports excludes + a mirror we can roll back
    // from); fall back to cp when rsync is unavailable. The DB is excluded so
    // it's never clobbered, and a backup is taken for rollback on failure.
    final script = '#!/bin/sh\n'
        // Wait for this process to exit (see the Windows script), max ~30s.
        'n=0; while kill -0 $pid 2>/dev/null && [ \$n -lt 30 ]; do sleep 1; n=\$((n+1)); done\n'
        'kill -9 $pid 2>/dev/null\n'
        'sleep 1\n'
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
        '    rm -f "$markerPath"\n'
        '    rm -rf "\$BAK" "$extractPath"\n'
        '  else\n'
        '    rsync -a "\$BAK/" "\$APP/"\n'  // rollback — original EXE is correct
        '  fi\n'
        'else\n'
        '  cp -rf "\$SRC/." "\$APP/" && rm -f "$markerPath"\n'
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

  static String _sJoin(String base, String name) =>
      '$base${Platform.pathSeparator}$name';

  static Future<void> _writeMarker(String tmpPath, String version,
      int buildNumber, String filePath, int attempts) async {
    await File(_sJoin(tmpPath, _markerName)).writeAsString(jsonEncode({
      'version': version,
      'buildNumber': buildNumber,
      'path': filePath,
      'attempts': attempts,
    }), flush: true);
  }

  Future<void> _download(
    UpdateInfo info,
    String savePath,
    Function(double)? onProgress,
  ) async {
    final file = File(savePath);
    if (await file.exists()) await file.delete();
    try {
      await _dio.download(
        info.downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          // Some hosts stream without Content-Length; the manifest size is
          // the same number.
          final t = total > 0 ? total : (info.sizeBytes ?? 0);
          if (t > 0 && onProgress != null) {
            onProgress((received / t).clamp(0.0, 1.0));
          }
        },
        options: Options(
          // Dio's receiveTimeout is the silence allowed between two chunks,
          // not the whole transfer — a slow link still gets there.
          receiveTimeout: const Duration(minutes: 2),
          validateStatus: (code) => code == 200,
        ),
      );
    } catch (_) {
      // Never leave a partial file for the next attempt to trip over.
      if (await file.exists()) await file.delete();
      rethrow;
    }
    _logger.info('Download complete: $savePath');
  }

  /// Size and sha256 both come from the manifest, so a matching file is
  /// byte-for-byte the release that was published.
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

  Future<void> cleanup() => discardStaged();
}
