import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers/admin_elevation_provider.dart';
import '../../providers/business_day_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/permission_service.dart';
import '../../domain/services/day_service.dart' show ZRuleViolation;
import '../../services/local_day_service.dart';
import '../../utils/z_rule_message.dart';
import '../../services/z_service.dart';
import '../../utils/admin_auth.dart';
import '../../utils/app_localizations.dart';
import '../../utils/button_styles.dart';
import '../../utils/snackbar_helper.dart';
import 'blocking_progress.dart';
import 'close_session_dialog.dart'
    show runUnpaidOrdersGate, UnpaidGateResult;
import 'z_report_dialog.dart' show showPrintZReportDialog;
import 'products_sold_report_dialog.dart';

/// Manager dialog for the Z, launched from the login screen after a
/// credential gate. [elevation] identifies the authorized admin/manager, whose
/// permissions gate each action; the terminal's Z rules (set in the back
/// office) gate the rest.
Future<void> showZManagementDialog(
  BuildContext context,
  WidgetRef ref,
  AdminElevation elevation,
) async {
  final l10n = AppLocalizations.of(context)!;
  final zService = ref.read(zQueriesProvider);

  // Load the acting user's permissions for per-button gating.
  final actor =
      await ref.read(userRepositoryProvider).getUserById(elevation.adminId);
  bool can(String perm) => actor != null && userHasPermission(actor, perm);

  if (!context.mounted) return;
  await ref.read(dayServiceProvider).refreshConfig();
  if (!context.mounted) return;
  // A Z close in flight — a second tap must not start another.
  var closingZ = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final today = ref.read(businessDayProvider.notifier).currentZDay();

        return FutureBuilder<Z?>(
          future: zService.getOpenZ(),
          builder: (ctx, snap) {
            final z = snap.data;
            final hasOpen = z != null;

            // Surface the ACTUAL printer result, never a blind "printed".
            Future<void> printReport(int zId,
                {required bool isX, bool reprint = false}) async {
              try {
                final ok = await printZReport(ref, zId,
                    isX: isX, reprint: reprint);
                if (!ctx.mounted) return;
                ok
                    ? SnackBarHelper.success(
                        ctx, l10n.translate('report_printed_successfully'))
                    : SnackBarHelper.error(ctx, l10n.translate('print_error'));
              } catch (e) {
                if (ctx.mounted) SnackBarHelper.failure(ctx, e);
              }
            }

            Future<void> openZ() async {
              try {
                await ref.read(dayServiceProvider).openManually(
                  userId: elevation.adminId,
                  hasOpenPermission: can(Permissions.zOpen),
                  hasOverride: can(Permissions.zOverride),
                );
                if (ctx.mounted) {
                  SnackBarHelper.success(ctx, l10n.translate('z_opened'));
                  setLocal(() {});
                }
              } on ZRuleViolation catch (v) {
                if (ctx.mounted) SnackBarHelper.error(ctx, v.message(l10n));
              } catch (e) {
                if (ctx.mounted) SnackBarHelper.failure(ctx, e);
              }
            }

            // Every session of the Z must already be closed: the Z closes on
            // its last session, which carries the close to the server.
            Future<void> closeZ(Z open, {required bool printZ}) async {
              if (closingZ) return;
              closingZ = true;
              try {
                final block = await ref.read(dayServiceProvider).closeBlock(
                  open,
                  hasClosePermission: can(Permissions.zClose),
                  hasOverride: can(Permissions.zOverride),
                );
                if (block != null) {
                  if (ctx.mounted) SnackBarHelper.error(ctx, block.message(l10n));
                  return;
                }
                if (ref.read(settingsProvider).unpaidPromptOnZClose &&
                    ctx.mounted) {
                  final zService = ref.read(zQueriesProvider);
                  // Settled cash needs a session still open to count it; the
                  // close then ends that session with the cash in its totals.
                  final openSessions = await zService.openSessionsOf(open.id);
                  final zSessions = await zService.sessionsForZ(open.id);
                  if (!ctx.mounted) return;
                  final gate = await runUnpaidOrdersGate(
                    ctx,
                    ref,
                    sessionIds: [for (final s in zSessions) s.id],
                    cashSessionId: openSessions.isEmpty ? null : openSessions.last.id,
                    forZ: true,
                  );
                  if (gate == UnpaidGateResult.cancelled) return;
                }
                if (!ctx.mounted) return;
                final printOk = await BlockingProgress.run(
                    ctx, l10n.translate('closing_z_progress'), (progress) async {
                  await ref.read(dayServiceProvider).close(open,
                      closeMode: ZService.closeManual,
                      endedBy: elevation.adminId);
                  if (!printZ) return true;
                  progress.message =
                      l10n.translate('printing_reports_progress');
                  return printZReport(ref, open.id, isX: false);
                });
                if (ctx.mounted && !printOk) {
                  SnackBarHelper.error(ctx, l10n.translate('print_error'));
                }
                if (ctx.mounted) {
                  SnackBarHelper.success(ctx, l10n.translate('z_closed'));
                  setLocal(() {});
                }
              } catch (e) {
                if (ctx.mounted) SnackBarHelper.failure(ctx, e);
              } finally {
                closingZ = false;
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
                        isLarge: true,
                        backgroundColor: color,
                        foregroundColor: color != null ? Colors.white : null),
                    icon: Icon(icon),
                    label: Text(label),
                    onPressed: onTap,
                  ),
                ),
              );
            }

            String fmt(DateTime d) =>
                '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
                '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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
                                  ? '${l10n.translate('current_z')}: ${ZService.displayName(z)}\n${l10n.translate('started_at')}: ${fmt(z.startedAt)}'
                                  : l10n.translate('no_open_z'),
                              style: const TextStyle(fontSize: 15),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${l10n.translate('business_day')}: $today',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (!hasOpen && can(Permissions.zOpen))
                        bigBtn(l10n.translate('open_z'), Icons.play_circle,
                            openZ,
                            color: Colors.green),
                      // X prints while the Z is still open (snapshot); the Z
                      // report prints at close. Not separately gated: reaching
                      // this dialog already cost credentials.
                      if (hasOpen)
                        bigBtn(l10n.translate('print_x_report'),
                            Icons.receipt_long,
                            () => printReport(z.id, isX: true)),
                      if (hasOpen && can(Permissions.zClose)) ...[
                        bigBtn(l10n.translate('close_and_print_z'),
                            Icons.summarize, () => closeZ(z, printZ: true),
                            color: Colors.indigo),
                        bigBtn(l10n.translate('close_z'), Icons.stop_circle,
                            () => closeZ(z, printZ: false),
                            color: Colors.red),
                      ],

                      // A past day's Z, by date — reads cash sessions, so any
                      // trading day can be reported on.
                      if (!hasOpen)
                        bigBtn(l10n.translate('print_past_z_report'),
                            Icons.calendar_month,
                            () => showPrintZReportDialog(context: ctx, ref: ref)),

                      // Reports: period papers that are not closing
                      // documents, so they print whether a Z is open or not.
                      const Divider(height: 24),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          const Icon(Icons.bar_chart, size: 18),
                          const SizedBox(width: 6),
                          Text(l10n.translate('reports_section'),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      bigBtn(l10n.translate('report_products_sold'),
                          Icons.restaurant_menu,
                          () => showProductsSoldReportDialog(ctx, ref)),

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
                          if (zsSnap.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (zs.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(l10n.translate('no_zs_yet'),
                                  style: TextStyle(
                                      color: Theme.of(ctx)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            );
                          }
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
                                final subtitle =
                                    StringBuffer(fmt(item.startedAt));
                                if (item.endedAt != null) {
                                  subtitle.write(' → ${fmt(item.endedAt!)}');
                                }
                                if (item.closeMode != null) {
                                  subtitle.write(' (${item.closeMode})');
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
                                          : Theme.of(ctx)
                                              .colorScheme
                                              .onSurfaceVariant),
                                  title: Text(ZService.displayName(item),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    '${isOpen ? l10n.translate('status_open') : l10n.translate('status_closed')} · $subtitle',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  isThreeLine: item.totalPaid != null,
                                  // A closed Z printed again is a DUPLICATA.
                                  trailing: IconButton(
                                    tooltip: isOpen
                                        ? l10n.translate('print_x_report')
                                        : l10n.translate('print_z_report'),
                                    icon: Icon(isOpen
                                        ? Icons.receipt_long
                                        : Icons.summarize),
                                    onPressed: () => printReport(item.id,
                                        isX: isOpen, reprint: !isOpen),
                                  ),
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
