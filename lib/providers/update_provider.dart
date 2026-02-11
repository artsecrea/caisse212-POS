import 'dart:io';
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

  UpdateState({
    this.isChecking = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.availableUpdate,
    this.error,
    this.updateRequired = false,
  });

  UpdateState copyWith({
    bool? isChecking,
    bool? isDownloading,
    double? downloadProgress,
    UpdateInfo? availableUpdate,
    String? error,
    bool? updateRequired,
  }) {
    return UpdateState(
      isChecking: isChecking ?? this.isChecking,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      availableUpdate: availableUpdate ?? this.availableUpdate,
      error: error ?? this.error,
      updateRequired: updateRequired ?? this.updateRequired,
    );
  }
}

/// Update notifier
class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _updateService;

  UpdateNotifier(this._updateService) : super(UpdateState());

  /// Check for updates
  Future<void> checkForUpdates() async {
    state = state.copyWith(isChecking: true, error: null);

    try {
      final updateInfo = await _updateService.checkForUpdates();

      if (updateInfo != null) {
        // Compare versions
        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        final shouldUpdate = _compareVersions(updateInfo.version, currentVersion) > 0;

        if (shouldUpdate) {
          state = state.copyWith(
            availableUpdate: updateInfo,
            updateRequired: updateInfo.isMandatory,
          );
        }
      }

      state = state.copyWith(isChecking: false);
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        error: 'Failed to check for updates: $e',
      );
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
      } else if (Platform.isWindows) {
        // Windows: Download and launch updater
        final updatePath = await _updateService.downloadUpdateForWindows(
          state.availableUpdate!,
          onProgress: (progress) {
            state = state.copyWith(downloadProgress: progress);
          },
        );

        if (updatePath != null) {
          // Launch Windows updater
          success = await _updateService.launchWindowsUpdater(
            updateArchivePath: updatePath,
            appDirectory: Directory.current.path,
            executableName: 'posecrea.exe', // Adjust based on your app name
            excludeFolders: ['logs', 'data', 'config'],
            checksum: state.availableUpdate!.checksum,
          );

          if (success) {
            // Exit the app to allow updater to work
            exit(0);
          }
        }
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
