import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';
import 'database_providers.dart';

class UpdateState {
  final bool isChecking;
  final bool isDownloading;
  final double downloadProgress;
  final UpdateInfo? availableUpdate;
  final bool updateReady;       // downloaded + extracted, waiting for restart
  final String? pendingVersion; // version that's ready to apply
  final String? error;
  final bool updateRequired;    // mandatory flag
  final String? currentVersion;

  UpdateState({
    this.isChecking = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.availableUpdate,
    this.updateReady = false,
    this.pendingVersion,
    this.error,
    this.updateRequired = false,
    this.currentVersion,
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
    bool clearAvailableUpdate = false,
    bool clearError = false,
  }) {
    return UpdateState(
      isChecking: isChecking ?? this.isChecking,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      availableUpdate:
          clearAvailableUpdate ? null : (availableUpdate ?? this.availableUpdate),
      updateReady: updateReady ?? this.updateReady,
      pendingVersion: pendingVersion ?? this.pendingVersion,
      error: clearError ? null : (error ?? this.error),
      updateRequired: updateRequired ?? this.updateRequired,
      currentVersion: currentVersion ?? this.currentVersion,
    );
  }

  bool get hasUpdate => availableUpdate != null;
  bool get isBusy => isChecking || isDownloading;
}

class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _updateService;
  final _logger = Logger.instance;

  UpdateNotifier(this._updateService) : super(UpdateState());

  /// Checks the API for an update and surfaces it in state — does NOT start
  /// downloading. The login screen listens and shows the dialog when
  /// [UpdateState.availableUpdate] becomes non-null.
  Future<void> checkOnly() async {
    if (state.isBusy || state.updateReady || state.hasUpdate) return;

    state = state.copyWith(isChecking: true, clearError: true);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      state = state.copyWith(currentVersion: currentVersion);

      // A previous session already prepared an update — surface it immediately.
      final pending = await UpdateService.pendingUpdateVersion();
      if (pending != null) {
        _logger.info('Pending update ready: $pending');
        state = state.copyWith(
          isChecking: false,
          updateReady: true,
          pendingVersion: pending,
        );
        return;
      }

      final info = await _updateService.checkForUpdates();
      if (info == null || _compareVersions(info.version, currentVersion) <= 0) {
        state = state.copyWith(isChecking: false);
        return;
      }

      _logger.info('Update available: ${info.version}');
      state = state.copyWith(
        isChecking: false,
        availableUpdate: info,
        updateRequired: info.isMandatory,
      );

      // Mandatory updates start downloading immediately — the user has no choice.
      if (info.isMandatory) startDownload();
    } catch (e) {
      _logger.error('Update check failed: $e');
      state = state.copyWith(isChecking: false, error: e.toString());
    }
  }

  /// Downloads and prepares the update in the background. Safe to call
  /// multiple times — guards against duplicate downloads.
  /// Called by "Update Now", by [dismissUpdate] ("Later"), and auto-called
  /// for mandatory updates.
  Future<void> startDownload() async {
    final info = state.availableUpdate;
    if (info == null || state.isDownloading || state.updateReady) return;

    state = state.copyWith(
        isDownloading: true, downloadProgress: 0.0, clearError: true);
    try {
      await _updateService.downloadAndPrepare(
        info,
        onProgress: (p) => state = state.copyWith(downloadProgress: p),
      );
      state = state.copyWith(
        isDownloading: false,
        downloadProgress: 1.0,
        updateReady: true,
        pendingVersion: info.version,
      );
      _logger.info('Update ${info.version} ready for next restart');
    } catch (e) {
      _logger.error('Download failed: $e');
      state = state.copyWith(isDownloading: false, error: e.toString());
    }
  }

  /// Applies a prepared update immediately: launches the updater script,
  /// which closes this app, copies the new files, and relaunches. Called
  /// from the dialog when the user chose "Update Now" (foreground apply).
  /// If no update is prepared or the apply fails, returns silently.
  Future<void> applyNow() => UpdateService.applyPendingUpdateIfExists();

  /// "Later" — kicks off a silent background download then hides the dialog.
  /// The status bar in the login screen shows download progress.
  void dismissUpdate() {
    if (!state.updateRequired) {
      // startDownload captures state.availableUpdate synchronously before the
      // first await, so clearing it below does not interrupt the download.
      startDownload();
      state = state.copyWith(clearAvailableUpdate: true, clearError: true);
    }
  }

  // ── Legacy stubs (kept for existing callers) ──────────────────────────────

  Future<void> checkAndDownloadInBackground() => checkOnly();

  Future<bool> checkForUpdates() async {
    await checkOnly();
    return state.hasUpdate || state.updateReady;
  }

  Future<bool> downloadAndInstall() async {
    await startDownload();
    return state.updateReady;
  }

  // ── Version comparison ─────────────────────────────────────────────────────

  int _compareVersions(String v1, String v2) {
    final p1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final p2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final a = i < p1.length ? p1[i] : 0;
      final b = i < p2.length ? p2[i] : 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return UpdateService(apiService);
});

final updateProvider =
    StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  return UpdateNotifier(ref.watch(updateServiceProvider));
});

/// The version the user tapped "Later" on for the auto-update "ready" banner.
/// The banner hides while `pendingVersion == this`; a newer staged version
/// (different string) makes it reappear automatically — no manual reset. Held
/// in RAM only (resets each launch, which is fine: `applyPendingUpdateIfExists`
/// applies any staged update at the next launch before this ever matters).
final dismissedUpdateBannerProvider = StateProvider<String?>((ref) => null);
