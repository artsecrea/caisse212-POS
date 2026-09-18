import 'package:drift/drift.dart' show OrderingTerm, OrderingMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../utils/app_localizations.dart';

/// Conflicts nobody has said they have seen yet.
final unacknowledgedSerialConflictsProvider =
    StreamProvider<List<SerialConflict>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.serialConflicts)
        ..where((c) => c.acknowledgedAt.isNull())
        ..orderBy([
          (c) => OrderingTerm(expression: c.detectedAt, mode: OrderingMode.desc)
        ]))
      .watch();
});

/// Tells the cashier that a unit they sold went to another till.
///
/// This is the one thing in the sync path that a person genuinely has to act
/// on. A customer left with a box and a receipt naming a serial that now
/// belongs to somebody else's order — two people hold paperwork for one unit,
/// and no amount of syncing settles that. So it interrupts, and it does not
/// go away until somebody says they have read it.
///
/// It is not phrased as an error, because nothing failed: the sale went
/// through, the money is banked, the order is on the server. Only the claim on
/// that particular box did not survive.
Future<void> showSerialConflictAlert(
  BuildContext context,
  WidgetRef ref,
  List<SerialConflict> conflicts,
) async {
  if (conflicts.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final cs = Theme.of(context).colorScheme;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.inventory_2_outlined, color: cs.error, size: 32),
      title: Text(
        l10n?.translate('serial_conflict_title') ??
            'A unit was sold twice',
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n?.translate('serial_conflict_body') ??
                  'Another till sold these units first, so they have been '
                      'taken off our orders. The sales themselves went '
                      'through — only the claim on the specific box did not.',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final c in conflicts)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(Icons.qr_code_2, color: cs.error),
                          title: Text(
                            c.serialNumber ?? '#${c.serialId}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            c.winningOrderCode == null
                                ? '${c.orderCode} — ${l10n?.translate('serial_conflict_unclaimed') ?? 'could not be claimed'}'
                                : '${c.orderCode} → ${c.winningOrderCode}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n?.translate('serial_conflict_action') ??
                  'Check with the other till before the customer comes back: '
                      'two receipts now name the same box.',
              style: TextStyle(
                  fontSize: 14, color: cs.error, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () async {
            final database = ref.read(databaseProvider);
            final now = DateTime.now();
            for (final c in conflicts) {
              // Acknowledged, not deleted. Somebody will ask what happened to
              // that box weeks from now.
              await (database.update(database.serialConflicts)
                    ..where((row) => row.id.equals(c.id)))
                  .write(SerialConflictsCompanion(
                      acknowledgedAt: Value(now)));
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
          child: Text(l10n?.translate('serial_conflict_ack') ??
              'I have seen this'),
        ),
      ],
    ),
  );
}
