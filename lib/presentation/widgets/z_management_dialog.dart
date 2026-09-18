import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers/admin_elevation_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/z_day_provider.dart';
import '../../services/activity_log_service.dart' show activityLogServiceProvider;
import '../../services/daily_summary_service.dart';
import '../../services/permission_service.dart';
import '../../services/z_actions.dart';
import '../../utils/admin_auth.dart';
import '../../utils/app_localizations.dart';
import '../../utils/button_styles.dart';
import '../../utils/snackbar_helper.dart';

/// Close-Z dialog: offers **Print Z** (top) and **Print X**, then a plain
/// **Close** (which no longer auto-prints). Returns true if the Z was closed.
/// Reused by the in-app top-bar close and the login-screen manager dialog.
Future<bool> showZCloseDialog(
  BuildContext context,
  WidgetRef ref, {
  int? endedBy,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final z = ref.read(currentZProvider) ?? await ref.read(zServiceProvider).getOpenZ();
  if (z == null || !context.mounted) return false;
  var closed = false;
  final settings = ref.read(settingsProvider);
  final dayLock = settings.zDayLockEnabled;
  // Closing the Z from this dialog IS the end-of-day gesture, so the day-close
  // box starts ticked here (unlike the session-close dialog, where the usual
  // case is just ending a shift).
  var closeDay = dayLock;
  var printOrdersList = settings.printOrdersListOnClose;
  var printProdSummary = settings.printProductSummaryOnClose;
  final endedByName = () {
    final u = ref.read(currentUserProvider);
    return u == null ? null : '${u.firstName} ${u.lastName}'.trim();
  }();

  /// Shared close path: end the Z (and optionally the day) then fire the
  /// selected extra tickets, each isolated so one failure can't block the rest.
  Future<void> doClose(BuildContext ctx, {required bool printZ}) async {
    try {
      if (closeDay) {
        await closeBusinessDay(ref, endedBy: endedBy, endedByName: endedByName);
      } else {
        await closeActiveZ(ref, endedBy: endedBy);
      }
      closed = true;
      if (printZ) {
        try {
          await printZReport(ref, z.id, isX: false);
        } catch (_) {/* Z already closed — print is non-fatal */}
      }
      final summary = DailySummaryService(ref.read(databaseProvider));
      if (printOrdersList) {
        try {
          final r = await summary.ordersListForZ(z.id);
          await ref.read(printingServiceProvider).printOrdersList(report: r);
        } catch (_) {}
      }
      if (printProdSummary) {
        try {
          final r = await summary.productsSummaryForZ(z.id);
          await ref
              .read(printingServiceProvider)
              .printProductsSummary(report: r);
        } catch (_) {}
      }
      if (ctx.mounted) Navigator.pop(ctx);
    } catch (e) {
      if (ctx.mounted) SnackBarHelper.failure(ctx, e);
    }
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      Future<void> tryPrint(bool isX) async {
        try {
          final ok = await printZReport(ref, z.id, isX: isX);
          if (ctx.mounted) {
            ok
                ? SnackBarHelper.success(ctx, l10n.translate('printed_successfully'))
                : SnackBarHelper.error(ctx, l10n.translate('print_error'));
          }
        } catch (e) {
          if (ctx.mounted) SnackBarHelper.failure(ctx, e);
        }
      }

      Widget bigBtn(String label, IconData icon, VoidCallback onTap,
          {Color? color}) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: AppButtonStyles.elevatedButtonStyle(
                  isLarge: true,
                  backgroundColor: color,
                  // Force white text/icon on the colored (red/indigo/green)
                  // buttons — the theme default was low-contrast on them.
                  foregroundColor: color != null ? Colors.white : null),
              icon: Icon(icon),
              label: Text(label),
              onPressed: onTap,
            ),
          ),
        );
      }

      return AlertDialog(
        title: Row(children: [
          const Icon(Icons.point_of_sale, color: Colors.indigo),
          const SizedBox(width: 8),
          Text(l10n.translate('close_z')),
        ]),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('${l10n.translate('current_z')}: ${z.code}'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: printOrdersList,
                onChanged: (v) {
                  setLocal(() => printOrdersList = v ?? false);
                  ref
                      .read(settingsProvider.notifier)
                      .setPrintOrdersListOnClose(v ?? false);
                },
                title: Text(l10n.translate('print_orders_list')),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: printProdSummary,
                onChanged: (v) {
                  setLocal(() => printProdSummary = v ?? false);
                  ref
                      .read(settingsProvider.notifier)
                      .setPrintProductSummaryOnClose(v ?? false);
                },
                title: Text(l10n.translate('print_product_summary')),
              ),
              if (dayLock)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: closeDay,
                  onChanged: (v) => setLocal(() => closeDay = v ?? false),
                  title: Text(
                    l10n.translate('close_the_day'),
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.translate('day_close_warning')),
                ),
              const SizedBox(height: 8),
              // X can print while the Z is still open (snapshot). A Z report can
              // only be printed AFTER close, so it's bundled into "Close & print".
              bigBtn(l10n.translate('print_x_report'), Icons.receipt_long,
                  () => tryPrint(true)),
              bigBtn(l10n.translate('close_and_print_z'), Icons.summarize,
                  () => doClose(ctx, printZ: true), color: Colors.indigo),
              bigBtn(l10n.translate('close_z'), Icons.stop_circle,
                  () => doClose(ctx, printZ: false), color: Colors.red),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('cancel')),
          ),
        ],
      );
    }),
  );
  return closed;
}

/// Manager dialog for the Z (shift), launched from the login screen after a
/// credential gate. [elevation] identifies the authorized admin/manager, whose
/// permissions gate each action.
Future<void> showZManagementDialog(
  BuildContext context,
  WidgetRef ref,
  AdminElevation elevation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final db = ref.read(databaseProvider);
  final zService = ref.read(zServiceProvider);

  // Load the acting user's permissions for per-button gating.
  final actor = await (db.select(db.users)
        ..where((u) => u.id.equals(elevation.adminId)))
      .getSingleOrNull();
  bool can(String perm) => actor != null && userHasPermission(actor, perm);

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        Future<Z?> loadZ() => zService.getOpenZ();

        // Read (not watch) — setLocal drives the rebuild after a reopen.
        final dayState = ref.read(zDayStateProvider);
        final today = zBusinessDayKey(
            DateTime.now(), ref.read(settingsProvider).zDayStartHour);
        final dayLocked = dayState.isLockedFor(today);

        return FutureBuilder<Z?>(
          future: loadZ(),
          builder: (ctx, snap) {
            final z = snap.data;
            final hasOpen = z != null;

            // Print an X/Z and surface the ACTUAL printer result — not a blind
            // "printed successfully" (that was the bug: the snackbar ignored the
            // returned bool, so a failed/absent print still claimed success).
            Future<void> printReport(int zId, {required bool isX}) async {
              try {
                final ok = await printZReport(ref, zId, isX: isX);
                if (!ctx.mounted) return;
                ok
                    ? SnackBarHelper.success(
                        ctx, l10n.translate('printed_successfully'))
                    : SnackBarHelper.error(ctx, l10n.translate('print_error'));
              } catch (e) {
                if (ctx.mounted) SnackBarHelper.failure(ctx, e);
              }
            }

            Future<void> openZ() async {
              try {
                await openActiveZ(ref, createdBy: elevation.adminId);
                if (ctx.mounted) {
                  SnackBarHelper.success(ctx, l10n.translate('z_opened'));
                  setLocal(() {});
                }
              } catch (e) {
                if (ctx.mounted) SnackBarHelper.failure(ctx, e);
              }
            }

            // Close the active Z inline — no nested dialog. Optionally print the
            // Z report right after (the row still resolves by zId once closed).
            Future<void> closeZ(int zId, {required bool printZ}) async {
              try {
                await closeActiveZ(ref, endedBy: elevation.adminId);
                if (printZ) {
                  final ok = await printZReport(ref, zId, isX: false);
                  if (ctx.mounted && !ok) {
                    SnackBarHelper.error(ctx, l10n.translate('print_error'));
                  }
                }
                if (ctx.mounted) {
                  SnackBarHelper.success(ctx, l10n.translate('z_closed'));
                  setLocal(() {});
                }
              } catch (e) {
                if (ctx.mounted) SnackBarHelper.failure(ctx, e);
              }
            }

            Widget bigBtn(String label, IconData icon, VoidCallback? onTap,
                {Color? color}) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: AppButtonStyles.elevatedButtonStyle(
                        isLarge: true, backgroundColor: color),
                    icon: Icon(icon),
                    label: Text(label),
                    onPressed: onTap,
                  ),
                ),
              );
            }

            return AlertDialog(
              title: Row(children: [
                const Icon(Icons.point_of_sale, color: Colors.green),
                const SizedBox(width: 8),
                Text(l10n.translate('manage_z')),
              ]),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasOpen
                                ? '${l10n.translate('current_z')}: ${z.code}\n${l10n.translate('started_at')}: ${z.startedAt}'
                                : l10n.translate('no_open_z'),
                            style: const TextStyle(fontSize: 15),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${l10n.translate('business_day')}: ${dayState.businessDay.isEmpty ? today : dayState.businessDay}'
                            '   ·   ${l10n.translate('z_number')}: '
                            '${dayState.zNumber == 0 ? 1 : dayState.zNumber}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          Text(
                            dayLocked
                                ? (dayState.closedByName == null
                                    ? l10n.translate('day_closed')
                                    : l10n
                                        .translate('day_closed_by')
                                        .replaceAll(
                                            '{0}', dayState.closedByName!))
                                : l10n.translate('day_open'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: dayLocked
                                  ? Theme.of(ctx).colorScheme.error
                                  : Theme.of(ctx).colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // The day lock's escape hatch, reachable from the login
                    // screen so a mis-clicked day close never strands a shop.
                    if (dayLocked && can(Permissions.zClose))
                      bigBtn(l10n.translate('reopen_day'), Icons.lock_open,
                          () async {
                        await ref
                            .read(zDayStateProvider.notifier)
                            .reopenDay(byUserId: elevation.adminId);
                        ref.read(activityLogServiceProvider).logZDayReopened(
                              today,
                              userId: elevation.adminId,
                              username: elevation.adminUsername,
                            );
                        if (ctx.mounted) {
                          SnackBarHelper.success(
                              ctx, l10n.translate('day_reopened'));
                          setLocal(() {});
                        }
                      }, color: Colors.orange),
                    if (!hasOpen && can(Permissions.zOpen))
                      bigBtn(l10n.translate('open_z'), Icons.play_circle, openZ,
                          color: Colors.green),
                    // X prints while the Z is still open (snapshot). The Z report
                    // can only be printed after close, so it's bundled into
                    // "Close & Print Z".
                    if (hasOpen && can(Permissions.zPrint))
                      bigBtn(l10n.translate('print_x_report'), Icons.receipt_long,
                          () => printReport(z.id, isX: true)),
                    if (hasOpen && can(Permissions.zClose)) ...[
                      bigBtn(l10n.translate('close_and_print_z'), Icons.summarize,
                          () => closeZ(z.id, printZ: true),
                          color: Colors.indigo),
                      bigBtn(l10n.translate('close_z'), Icons.stop_circle,
                          () => closeZ(z.id, printZ: false),
                          color: Colors.red),
                    ],

                    // ── History of past Z shifts ──────────────────────────
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        const Icon(Icons.history, size: 18),
                        const SizedBox(width: 6),
                        Text(l10n.translate('z_history'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    FutureBuilder<List<Z>>(
                      future: zService.recentZs(),
                      builder: (ctx, zsSnap) {
                        final zs = zsSnap.data ?? const <Z>[];
                        if (zsSnap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (zs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(l10n.translate('no_zs_yet'),
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          );
                        }
                        String fmt(DateTime d) =>
                            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
                            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                        final currency = ref.read(settingsProvider).currency;
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: zs.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final item = zs[i];
                              final isOpen = item.status == 'open';
                              final subtitle = StringBuffer(fmt(item.startedAt));
                              if (item.endedAt != null) {
                                subtitle.write(' → ${fmt(item.endedAt!)}');
                              }
                              if (item.totalPaid != null) {
                                subtitle.write(
                                    '\n${l10n.translate('total_paid')}: ${item.totalPaid!.toStringAsFixed(2)} $currency');
                              }
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.circle,
                                    size: 12,
                                    color: isOpen
                                        ? Colors.green
                                        : Theme.of(context).colorScheme.onSurfaceVariant),
                                title: Text(item.code,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${isOpen ? l10n.translate('status_open') : l10n.translate('status_closed')} · ${subtitle.toString()}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                isThreeLine: item.totalPaid != null,
                                trailing: can(Permissions.zPrint)
                                    ? IconButton(
                                        tooltip: isOpen
                                            ? l10n.translate('print_x_report')
                                            : l10n.translate('print_z_report'),
                                        icon: Icon(isOpen
                                            ? Icons.receipt_long
                                            : Icons.summarize),
                                        onPressed: () =>
                                            printReport(item.id, isX: isOpen),
                                      )
                                    : null,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.translate('close')),
                ),
              ],
            );
          },
        );
      });
    },
  );
}
