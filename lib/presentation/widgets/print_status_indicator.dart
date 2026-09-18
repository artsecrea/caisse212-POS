import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../services/printing_service.dart';
import '../../utils/app_localizations.dart';

/// Small, non-blocking print status pill.
///
/// Replaces the full-screen scrim + spinner that used to sit over the POS and
/// payment screens while a ticket printed. That overlay made sense when the
/// cashier's tap waited for the printer; now that prints are detached and
/// queued ([PrintingService] / `SerialJobQueue`), blocking the till to report
/// on a background job is exactly backwards — the whole point is that the
/// cashier can carry on.
///
/// Two states, and nothing in between:
///
///  * **Working** — transient, shows what the printer is doing and how many
///    jobs are behind it. Disappears on its own.
///  * **Failed** — sticky, and the reason this widget exists. With printing off
///    the critical path there is no stalled button to notice any more, so a
///    kitchen ticket that never reached paper has to be visible until somebody
///    acknowledges it. Tap to dismiss.
///
/// Drop it into a [Stack] over the screen content; it aligns itself and never
/// intercepts a tap except on the pill itself.
class PrintStatusIndicator extends ConsumerWidget {
  const PrintStatusIndicator({
    super.key,
    this.alignment = Alignment.bottomRight,
    this.margin = const EdgeInsets.all(12),
  });

  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final printingService = ref.watch(printingServiceProvider);

    return Align(
      alignment: alignment,
      child: Padding(
        padding: margin,
        child: StreamBuilder<PrintAlert?>(
          stream: printingService.printAlertStream,
          initialData: printingService.printAlert,
          builder: (context, alertSnap) {
            final alert = alertSnap.data;
            if (alert != null) {
              return _FailurePill(
                alert: alert,
                onDismiss: printingService.clearPrintAlert,
              );
            }

            // No failure outstanding: show progress only while there is work.
            return StreamBuilder<int>(
              stream: printingService.printQueueDepthStream,
              initialData: printingService.printQueueDepth,
              builder: (context, depthSnap) {
                final depth = depthSnap.data ?? 0;
                if (depth <= 0) return const SizedBox.shrink();

                return StreamBuilder<String?>(
                  stream: printingService.printingStatusStream,
                  builder: (context, statusSnap) =>
                      _WorkingPill(depth: depth, status: statusSnap.data),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _WorkingPill extends StatelessWidget {
  const _WorkingPill({required this.depth, this.status});

  final int depth;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // Prefer the printer's own message ("Connecting to printer...") when there
    // is one — it says more than a generic label.
    final label = status ??
        (depth > 1
            ? l10n.translate('print_pending_count').replaceAll('{0}', '$depth')
            : l10n.translate('print_pending'));

    return _Pill(
      background: theme.colorScheme.surfaceContainerHighest,
      foreground: theme.colorScheme.onSurfaceVariant,
      leading: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      label: label,
      // Trailing count when the printer's own message is showing, so a queue
      // building up behind a slow job is still visible.
      trailing: (status != null && depth > 1) ? '$depth' : null,
    );
  }
}

class _FailurePill extends StatelessWidget {
  const _FailurePill({required this.alert, required this.onDismiss});

  final PrintAlert alert;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final title = alert.count > 1
        ? l10n.translate('print_failed_count').replaceAll('{0}', '${alert.count}')
        : l10n.translate('print_failed_title');

    return Tooltip(
      message: '${alert.reason}\n${l10n.translate('print_failed_dismiss')}',
      child: InkWell(
        onTap: onDismiss,
        borderRadius: BorderRadius.circular(999),
        child: _Pill(
          background: theme.colorScheme.errorContainer,
          foreground: theme.colorScheme.onErrorContainer,
          leading: Icon(
            Icons.print_disabled_rounded,
            size: 16,
            color: theme.colorScheme.onErrorContainer,
          ),
          label: title,
          trailingIcon: Icons.close_rounded,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.background,
    required this.foreground,
    required this.leading,
    required this.label,
    this.trailing,
    this.trailingIcon,
  });

  final Color background;
  final Color foreground;
  final Widget leading;
  final String label;
  final String? trailing;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      elevation: 2,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ],
            if (trailingIcon != null) ...[
              const SizedBox(width: 6),
              Icon(trailingIcon, size: 15, color: foreground),
            ],
          ],
        ),
      ),
    );
  }
}
