import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/update_config.dart';
import '../services/update_resume_service.dart';
import '../services/update_service.dart';
import 'database_providers.dart';
import 'settings_provider.dart';

class UpdateState {
  final bool isChecking;
  final bool isDownloading;
  final double downloadProgress;
  final UpdateInfo? availableUpdate;
  final bool updateReady;       // staged, waiting for a restart
  final String? pendingVersion; // version that's staged
  final String? error;
  final bool updateRequired;    // mandatory flag
  final String? currentVersion;
  /// Someone asked to install now: apply as soon as the download is staged.
  final bool installRequested;
  /// The updater is being launched — the app is about to close.
  final bool isApplying;
  final int failedDownloads;
  /// Build whose notice the person closed with "Later" (non-mandatory only).
  final int? dismissedBuild;

  const UpdateState({
    this.isChecking = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.availableUpdate,
    this.updateReady = false,
    this.pendingVersion,
    this.error,
    this.updateRequired = false,
    this.currentVersion,
    this.installRequested = false,
    this.isApplying = false,
    this.failedDownloads = 0,
    this.dismissedBuild,
  });

  UpdateState copyWith({
    bool? isChecking,
    bool? isDownloading,
    double? downloadProgress,
    UpdateInfo? availableUpdate,
    bool? updateReady,
    String? pendingVersion,
    String? error,
    bool? updateRequired,
    String? currentVersion,
    bool? installRequested,
    bool? isApplying,
    int? failedDownloads,
    int? dismissedBuild,
    bool clearAvailableUpdate = false,
    bool clearPendingVersion = false,
    bool clearError = false,
  }) {
    return UpdateState(
      isChecking: isChecking ?? this.isChecking,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      availableUpdate:
          clearAvailableUpdate ? null : (availableUpdate ?? this.availableUpdate),
      updateReady: updateReady ?? this.updateReady,
      pendingVersion:
          clearPendingVersion ? null : (pendingVersion ?? this.pendingVersion),
      error: clearError ? null : (error ?? this.error),
      updateRequired: updateRequired ?? this.updateRequired,
      currentVersion: currentVersion ?? this.currentVersion,
      installRequested: installRequested ?? this.installRequested,
      isApplying: isApplying ?? this.isApplying,
      failedDownloads: failedDownloads ?? this.failedDownloads,
      dismissedBuild: dismissedBuild ?? this.dismissedBuild,
    );
  }

  bool get hasUpdate => availableUpdate != null;
  bool get isBusy => isChecking || isDownloading;

  /// Version to show: the one offered, else the one staged from a previous run.
  String? get version => availableUpdate?.version ?? pendingVersion;
}

/// Checks the updates service every [UpdateService.checkHours] (daily by default) and
/// drives download → stage → install.
///
/// Nothing here ever stops the cashier: downloads are silent (no progress,
/// errors only logged and retried hourly), and nothing restarts on its own
/// while someone is signed in.
///
/// - Optional: downloaded silently when auto-update is on; once staged,
///   UpdateWatcher offers "Restart now" / "Later" (Later = installs at the next
///   launch). With auto-update off it is offered as soon as it is found.
/// - Mandatory: always downloaded silently; once staged, the login screen
///   asks to install it after the next logout. A restart that does happen
///   while signed in keeps the cashier, session and orders ([UpdateResume]).
class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _updateService;
  final SharedPreferences _prefs;
  final bool Function() _autoUpdate;
  final Future<void> Function() _beforeRestart;
  final Future<void> Function() _restartAborted;
  final _logger = Logger.instance;

  Timer? _tick;
  bool _started = false;

  UpdateNotifier(this._updateService, this._prefs, this._autoUpdate,
      {Future<void> Function()? beforeRestart,
      Future<void> Function()? restartAborted})
      : _beforeRestart = beforeRestart ?? (() async {}),
        _restartAborted = restartAborted ?? (() async {}),
        super(const UpdateState());

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Idempotent. Surfaces an update staged by a previous run, runs the day's
  /// check if it is due, and keeps an hourly timer that re-checks when due.
  void start() {
    if (_started || !UpdateService.platformSupported) return;
    _started = true;
    // Spread a fleet of tills that all boot at opening time.
    final jitterMs = UpdateConfig.tickJitter.inMilliseconds;
    _tick = Timer.periodic(
      UpdateConfig.tickInterval +
          Duration(milliseconds: Random().nextInt(jitterMs + 1)),
      (_) {
        if (mounted) maybeCheck();
      },
    );
    unawaited(_updateService
        .bakeDefaultBaseUrl()
        .then((_) => _loadStaged())
        .then((_) => maybeCheck()));
  }

  Future<void> _loadStaged() async {
    final staged = await UpdateService.readStaged();
    if (staged == null || !mounted) return;
    state = state.copyWith(updateReady: true, pendingVersion: staged.version);
  }

  bool get _checkDue {
    final hours = _updateService.checkHours;
    if (hours <= 0) return false;
    final last = _prefs.getInt(UpdateConfig.lastCheckPrefKey);
    if (last == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    // Negative = the clock was moved back; don't wait for it to catch up.
    return elapsed < 0 || elapsed >= Duration(hours: hours).inMilliseconds;
  }

  Future<void> maybeCheck() async {
    if (_checkDue) await check();
  }

  /// Asks the server now. Returns false when it could not be reached.
  Future<bool> check() async {
    if (!UpdateService.platformSupported) return true;
    if (state.isBusy || state.isApplying) return true;

    state = state.copyWith(isChecking: true, clearError: true);
    try {
      await _updateService.bakeDefaultBaseUrl();
      final packageInfo = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      state = state.copyWith(currentVersion: packageInfo.version);

      final result =
          await _updateService.check(installedBuild: installedBuild);
      if (!mounted) return result.answered;
      if (!result.answered) {
        // Not counted as the day's check: the next hourly tick tries again.
        state = state.copyWith(isChecking: false);
        return false;
      }
      await _prefs.setInt(UpdateConfig.lastCheckPrefKey,
          DateTime.now().millisecondsSinceEpoch);

      final info = result.info;

      // The server is the authority on what may be installed. A staged build
      // it no longer offers was withdrawn (or superseded) — never install it.
      final staged = await UpdateService.readStaged();
      if (staged != null &&
          (info == null || info.buildNumber != staged.buildNumber)) {
        _logger.info(
            'Staged update ${staged.version}+${staged.buildNumber} no longer offered — discarding');
        await UpdateService.discardStaged();
      }
      final alreadyStaged =
          staged != null && info != null && info.buildNumber == staged.buildNumber;

      if (!mounted) return true;
      if (info == null) {
        state = state.copyWith(
          isChecking: false,
          updateReady: false,
          updateRequired: false,
          installRequested: false,
          clearAvailableUpdate: true,
          clearPendingVersion: true,
        );
        return true;
      }

      final changed = state.availableUpdate?.buildNumber != info.buildNumber;
      state = state.copyWith(
        isChecking: false,
        availableUpdate: info,
        updateRequired: info.isMandatory,
        updateReady: alreadyStaged,
        pendingVersion: alreadyStaged ? info.version : null,
        clearPendingVersion: !alreadyStaged,
        failedDownloads: changed ? 0 : null,
        installRequested: changed ? false : null,
      );

      if (!alreadyStaged && (info.isMandatory || _autoUpdate())) {
        unawaited(startDownload());
      }
      return true;
    } catch (e) {
      _logger.error('Update check failed: $e');
      if (mounted) state = state.copyWith(isChecking: false);
      return false;
    }
  }

  /// Downloads and stages the offered update. Safe to call repeatedly.
  Future<void> startDownload() async {
    final info = state.availableUpdate;
    if (info == null || state.isDownloading || state.updateReady) return;

    state = state.copyWith(
        isDownloading: true, downloadProgress: 0.0, clearError: true);
    var lastPct = -1;
    try {
      await _updateService.downloadAndPrepare(
        info,
        onProgress: (p) {
          // One rebuild per percent, not one per network chunk.
          final pct = (p * 100).floor();
          if (pct == lastPct || !mounted) return;
          lastPct = pct;
          state = state.copyWith(downloadProgress: p);
        },
      );
      if (!mounted) return;
      state = state.copyWith(
        isDownloading: false,
        downloadProgress: 1.0,
        updateReady: true,
        pendingVersion: info.version,
        failedDownloads: 0,
      );
      _logger.info('Update ${info.version} ready for next restart');
      if (state.installRequested) await applyNow();
    } catch (e) {
      _logger.error('Download failed: $e');
      // Retry at the next hourly tick instead of tomorrow.
      await _prefs.remove(UpdateConfig.lastCheckPrefKey);
      if (!mounted) return;
      state = state.copyWith(
        isDownloading: false,
        error: e.toString(),
        failedDownloads: state.failedDownloads + 1,
      );
    }
  }

  /// "Install now": applies the staged update, downloading it first if
  /// needed. Callers check for unsaved work before calling this.
  Future<void> installNow() async {
    state = state.copyWith(installRequested: true, clearError: true);
    if (state.updateReady) {
      await applyNow();
    } else {
      await startDownload();
    }
  }

  /// Launches the updater (the app exits). Only returns when nothing was
  /// launched — UAC declined, staged files gone — and the till keeps going.
  Future<bool> applyNow() async {
    if (state.isApplying) return false;
    state = state.copyWith(isApplying: true, clearError: true);
    try {
      await _beforeRestart();
    } catch (e) {
      _logger.error('Saving the session before the update failed: $e');
    }
    final launched = await UpdateService.applyStaged(interactive: true);
    // Only reached when nothing was launched; the app keeps running.
    try {
      await _restartAborted();
    } catch (_) {}
    if (!mounted) return launched;
    final staged = await UpdateService.readStaged();
    if (!mounted) return launched;
    state = state.copyWith(
      isApplying: false,
      installRequested: false,
      updateReady: staged != null,
      pendingVersion: staged?.version,
      clearPendingVersion: staged == null,
      error: 'update_install_not_started',
    );
    return launched;
  }

  /// Settings "Delete download": throws away the staged files. The update is
  /// still known, so it can be downloaded again.
  Future<void> discardDownload() async {
    if (state.isApplying || state.isDownloading) return;
    await UpdateService.discardStaged();
    if (!mounted) return;
    state = state.copyWith(updateReady: false, clearPendingVersion: true);
  }

  /// "Later" on an optional update: hides its notice until the next one.
  void dismiss() {
    if (state.updateRequired) return;
    final build = state.availableUpdate?.buildNumber ?? -1;
    state = state.copyWith(dismissedBuild: build, installRequested: false);
  }

  /// Manual "check for updates": true = an update is offered or staged,
  /// false = up to date, null = server unreachable.
  Future<bool?> checkForUpdates() async {
    start();
    final answered = await check();
    if (!answered) return null;
    // A manual check re-shows a notice dismissed earlier.
    state = UpdateState(
      isChecking: state.isChecking,
      isDownloading: state.isDownloading,
      downloadProgress: state.downloadProgress,
      availableUpdate: state.availableUpdate,
      updateReady: state.updateReady,
      pendingVersion: state.pendingVersion,
      error: state.error,
      updateRequired: state.updateRequired,
      currentVersion: state.currentVersion,
      installRequested: state.installRequested,
      isApplying: state.isApplying,
      failedDownloads: state.failedDownloads,
    );
    return state.hasUpdate || state.updateReady;
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return UpdateService(apiService, ref.watch(sharedPreferencesProvider));
});

final updateProvider =
    StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  return UpdateNotifier(
    ref.watch(updateServiceProvider),
    ref.watch(sharedPreferencesProvider),
    () => ref.read(settingsProvider).autoUpdate,
    beforeRestart: () => UpdateResume.save(ref.read),
    restartAborted: () => UpdateResume.clear(ref.read),
  );
});
