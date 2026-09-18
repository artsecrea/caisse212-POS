import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/held_orders_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/update_provider.dart';
import '../../utils/app_localizations.dart';

/// Slim, non-blocking bar shown at the top of every screen once a NON-mandatory
/// update has been silently downloaded and staged (auto-update flow). Offers
/// "Restart now" (apply immediately) and "Later" (keep working — the staged
/// update applies automatically on the next launch via
/// `UpdateService.applyPendingUpdateIfExists`).
///
/// Mandatory updates never reach this banner — they go through the blocking
/// modal that force-applies. Rendered as an overlay in `main.dart`'s
/// `MaterialApp.builder`; returns an empty box when there's nothing to show.
///
/// Because it lives ABOVE the app's Navigator, it can't use `showDialog`; the
/// "unsaved work" confirmation is therefore done INLINE (the bar swaps to a
/// confirm row) instead of via a modal.
class UpdateReadyBanner extends ConsumerStatefulWidget {
  const UpdateReadyBanner({super.key});

  @override
  ConsumerState<UpdateReadyBanner> createState() => _UpdateReadyBannerState();
}

class _UpdateReadyBannerState extends ConsumerState<UpdateReadyBanner> {
  // True after "Restart now" is tapped while unsaved work exists — the bar then
  // shows an inline "will be lost — confirm/cancel" row.
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    final update = ref.watch(updateProvider);
    final dismissed = ref.watch(dismissedUpdateBannerProvider);
    final version = update.pendingVersion;

    // Show only for a staged, non-mandatory update the user hasn't dismissed.
    if (!update.updateReady ||
        update.updateRequired ||
        version == null ||
        version == dismissed) {
      _confirming = false; // reset for next time the banner appears
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (_confirming) {
      return _bar(cs, [
        Icon(Icons.warning_amber_rounded,
            size: 18, color: cs.onPrimaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n?.translate('update_restart_confirm_message') ??
                'Unsaved orders held in memory will be lost. Restart now?',
            style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _confirming = false),
          child: Text(l10n?.translate('cancel') ?? 'Cancel'),
        ),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: () => ref.read(updateProvider.notifier).applyNow(),
          child:
              Text(l10n?.translate('update_restart_now') ?? 'Restart now'),
        ),
      ]);
    }

    return _bar(cs, [
      Icon(Icons.system_update_alt_rounded,
          size: 18, color: cs.onPrimaryContainer),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          (l10n?.translate('update_ready_banner') ?? 'Update {0} ready')
              .replaceAll('{0}', version),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onPrimaryContainer,
          ),
        ),
      ),
      TextButton(
        onPressed: () =>
            ref.read(dismissedUpdateBannerProvider.notifier).state = version,
        child: Text(l10n?.translate('update_later') ?? 'Later'),
      ),
      const SizedBox(width: 4),
      FilledButton(
        onPressed: _onRestart,
        child: Text(l10n?.translate('update_restart_now') ?? 'Restart now'),
      ),
    ]);
  }

  /// Applying = exit + relaunch, which loses all in-RAM state. If there are
  /// held orders or an active cart, show the inline confirm first; otherwise
  /// apply immediately.
  void _onRestart() {
    final hasUnsaved = ref.read(heldOrdersProvider).isNotEmpty ||
        ref.read(orderProvider).items.isNotEmpty;
    if (hasUnsaved) {
      setState(() => _confirming = true);
      return;
    }
    ref.read(updateProvider.notifier).applyNow();
  }

  Widget _bar(ColorScheme cs, List<Widget> children) {
    return Material(
      color: cs.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: children),
        ),
      ),
    );
  }
}
