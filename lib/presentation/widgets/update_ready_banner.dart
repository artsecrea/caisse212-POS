import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../providers/update_provider.dart';
import 'update_dialog.dart';

/// Invisible: starts the daily update check and puts up the optional-update
/// dialog at the right moment. The cashier never sees a download — no bar, no
/// progress, no errors (those are logged and retried hourly).
///
///  - auto-update on: the dialog appears once the update is fully downloaded.
///  - auto-update off: it appears as soon as an update is found.
///  - "Show update notifications" off: never opens; the Update button and
///    Settings still offer it.
///  - mandatory: never here, never while someone works — the login screen
///    asks after the next logout.
///
/// Mounted once in `main.dart`'s `MaterialApp.builder`, i.e. above the
/// Navigator, so dialogs go through [navigatorKey].
class UpdateWatcher extends ConsumerStatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const UpdateWatcher({super.key, required this.navigatorKey});

  @override
  ConsumerState<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends ConsumerState<UpdateWatcher> {
  /// Build already offered this run, so a state change doesn't re-open it.
  int? _offered;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    // Idempotent; also restarts the checker if the notifier was rebuilt.
    ref.read(updateProvider.notifier).start();

    ref.listen<UpdateState>(updateProvider, (_, next) => _maybeOffer(next));
    return const SizedBox.shrink();
  }

  void _maybeOffer(UpdateState s) {
    if (s.updateRequired || s.isBusy || s.isApplying) return;
    if (!ref.read(updateServiceProvider).notify) return;
    final build = s.availableUpdate?.buildNumber ?? -1;
    if (s.dismissedBuild == build || _offered == build) return;

    final ready = s.updateReady;
    final announce = s.hasUpdate && !ref.read(settingsProvider).autoUpdate;
    if (!ready && !announce) return;

    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null) return;
    _offered = build;
    showUpdateDialog(ctx, isMandatory: false);
  }
}
