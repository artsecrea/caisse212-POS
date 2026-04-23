import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Update state
class UpdateState {
  final bool isChecking;
  final bool isDownloading;
  final double downloadProgress;
  final UpdateInfo? availableUpdate;
  final String? error;
  final bool updateRequired;
  final String? currentVersion;

  UpdateState({
    this.isChecking = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.availableUpdate,
    this.error,
    this.updateRequired = false,
    this.currentVersion,
  });

  UpdateState copyWith({
    bool? isChecking,
    bool? isDownloading,
    double? downloadProgress,
    UpdateInfo? availableUpdate,
    String? error,
    bool? updateRequired,
    String? currentVersion,
    bool clearUpdate = false,
  }) {
    return UpdateState(
      isChecking: isChecking ?? this.isChecking,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      availableUpdate: clearUpdate ? null : (availableUpdate ?? this.availableUpdate),
      error: error,
      updateRequired: updateRequired ?? this.updateRequired,
      currentVersion: currentVersion ?? this.currentVersion,
    );
  }

  bool get hasUpdate => availableUpdate != null;
}

/// Update notifier
class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _updateService;

  UpdateNotifier(this._updateService) : super(UpdateState());

  /// Check for updates by calling the API and comparing versions
  Future<bool> checkForUpdates() async {
    state = state.copyWith(isChecking: true, error: null);

    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      state = state.copyWith(currentVersion: currentVersion);

      // Call API to check for updates
      final updateInfo = await _updateService.checkForUpdates();

      if (updateInfo != null) {
        // Compare remote version with local version
        final comparisonResult = _compareVersions(updateInfo.version, currentVersion);

        if (comparisonResult > 0) {
          // Remote version is newer
          print('Update available: ${updateInfo.version} > $currentVersion');
          state = state.copyWith(
            isChecking: false,
            availableUpdate: updateInfo,
            updateRequired: updateInfo.isMandatory,
          );
          return true;
        } else {
          // Current version is up to date
          print('App is up to date: $currentVersion >= ${updateInfo.version}');
          state = state.copyWith(
            isChecking: false,
            clearUpdate: true,
          );
          return false;
        }
      } else {
        // No update info returned
        state = state.copyWith(isChecking: false);
        return false;
      }
    } catch (e) {
      print('Error checking for updates: $e');
      state = state.copyWith(
        isChecking: false,
        error: 'Failed to check for updates: $e',
      );
      return false;
    }
  }

  /// Download and install update
  Future<bool> downloadAndInstall() async {
    if (state.availableUpdate == null) return false;

    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0.0,
      error: null,
    );

    try {
      bool success = false;

      if (Platform.isAndroid) {
        // Android: Download and open installer
        success = await _updateService.downloadAndInstallUpdate(
          state.availableUpdate!,
          onProgress: (progress) {
            state = state.copyWith(downloadProgress: progress);
          },
        );
      } else if (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        // Desktop: handled by desktop_updater via UpdateDialogListener /
        // DesktopUpdateWidget in the widget tree. The controller (from
        // desktopUpdaterControllerProvider) drives the download & restart.
        // Nothing to do here – the user will see the update card / dialog
        // automatically once the archive JSON is fetched.
        state = state.copyWith(isDownloading: false);
        return true;
      }

      state = state.copyWith(
        isDownloading: false,
        downloadProgress: success ? 1.0 : 0.0,
      );

      return success;
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        downloadProgress: 0.0,
        error: 'Failed to download/install update: $e',
      );
      return false;
    }
  }

  /// Dismiss update notification (only if not mandatory)
  void dismissUpdate() {
    if (!state.updateRequired) {
      state = UpdateState();
    }
  }

  /// Compare semantic versions
  /// Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;

      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }

    return 0;
  }
}

/// Update provider
final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  final updateService = ref.watch(updateServiceProvider);
  return UpdateNotifier(updateService);
});
