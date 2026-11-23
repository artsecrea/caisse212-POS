import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../domain/models/reservation_models.dart';
import '../../providers/reservation_providers.dart';
import '../../providers/resource_providers.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import 'reservation_actions.dart';
import 'reservation_panel.dart';
import 'side_panel.dart';

Future<void> showReservationDetail(
  BuildContext context,
  Reservation reservation,
) {
  return showSidePanel<void>(
    context,
    ReservationDetailSheet(reservation: reservation),
  );
}

/// Everything about one reservation and what staff can do with it.
/// Offline only "Ring up" stays enabled; every other action is a write.
class ReservationDetailSheet extends ConsumerStatefulWidget {
  final Reservation reservation;
  const ReservationDetailSheet({super.key, required this.reservation});

  @override
  ConsumerState<ReservationDetailSheet> createState() =>
      _ReservationDetailSheetState();
}

class _ReservationDetailSheetState
    extends ConsumerState<ReservationDetailSheet> {
  late Reservation _r = widget.reservation;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The agenda may be minutes old; show what the server holds now.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fresh = await ref.read(reservationServiceProvider).refresh(_r);
      if (fresh != null && mounted) setState(() => _r = fresh);
    });
  }

  Future<void> _write(
    Future<Reservation> Function() write, {
    String? successKey,
    Future<Reservation> Function()? overbook,
  }) async {
    setState(() => _busy = true);
    final r = await runReservationWrite(
      ref,
      context,
      write,
      successKey: successKey,
      overbook: overbook,
      overbookLabel: 'res_confirm_anyway',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) _r = r;
    });
  }

  Future<void> _setStatus(String status) async {
    String? reason;
    if (status == ReservationStatus.canceled) {
      reason = await _askReason();
      if (reason == null) return; // dialog dismissed
    }
    final service = ref.read(reservationServiceProvider);
    await _write(
      () => service.setStatus(_r.id, status, reason: reason),
      successKey: 'res_saved',
      // Confirming over a firm booking is refused; a manager may insist.
      overbook: status == ReservationStatus.confirmed
          ? () => service.setStatus(_r.id, status, overbook: true)
          : null,
    );
  }

  Future<String?> _askReason() {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.translate('res_cancel')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.translate('res_cancel_reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(l10n.translate('back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text),
            child: Text(l10n.translate('res_cancel')),
          ),
        ],
      ),
    );
  }

  Future<void> _move() async {
    final l10n = AppLocalizations.of(context)!;
    final date = await showDatePicker(
      context: context,
      initialDate: _r.startAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_r.startAt),
      helpText: l10n.translate('res_move'),
    );
    if (time == null || !mounted) return;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final service = ref.read(reservationServiceProvider);
    await _write(
      () => service.move(_r.id, startAt: start),
      successKey: 'res_moved',
    );
  }

  Future<void> _edit() async {
    final saved = await showReservationPanel(
      context,
      existing: _r,
      start: _r.startAt,
    );
    if (saved is Reservation && mounted) setState(() => _r = saved);
  }

  Future<void> _ringUp() async {
    setState(() => _busy = true);
    final ok = await ringUpReservation(context, ref, _r);
    if (!ok && mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final online = ref.watch(canReserveProvider);
    final money = ref.watch(currencyFormatterProvider);
    final resources = ref.watch(resourcesByIdProvider);
    ref.watch(clockTickProvider);
    final colors = reservationStatusColors(_r.status, cs);
    final day = DateFormat(
      'EEE d MMM',
      Localizations.localeOf(context).toLanguageTag(),
    ).format(_r.startAt);

    Widget chip(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );

    final canWrite = online && !_busy;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          8,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _r.customerLabel.isEmpty ? _r.code : _r.customerLabel,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  chip(
                    reservationStatusLabel(_r.status, l10n),
                    colors.bg,
                    colors.fg,
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '$day · ${hmRange(_r.startAt, _r.endAt)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (_r.holdsSlot && !_r.isConverted)
                    Text(
                      timeStatusLabel(_r.timeStatus(), l10n),
                      style: TextStyle(color: cs.primary, fontSize: 12),
                    ),
                  SelectableText(
                    _r.code,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (_r.customer?.phone != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${l10n.translate('phone')}: ${_r.customer!.phone}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              const Divider(height: 24),
              for (final it in _r.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        // A retail line has no time of its own.
                        child: it.timed
                            ? Text(
                                hmRange(it.startAt, it.endAt),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : Icon(
                                Icons.shopping_bag_outlined,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.quantity == 1
                                  ? it.name
                                  : '${it.quantity.toStringAsFixed(0)} × ${it.name}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (it.resourceIds.isNotEmpty)
                              Text(
                                it.resourceIds
                                    .map((id) => resources[id]?.name ?? '#$id')
                                    .join(', '),
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            if (it.note != null)
                              Text(
                                it.note!,
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(money.format(it.value)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  money.format(_r.value),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_r.note != null)
                _noteLine(l10n.translate('res_note'), _r.note!),
              if (_r.internalNote != null)
                _noteLine(
                  l10n.translate('res_internal_note'),
                  _r.internalNote!,
                ),
              if (_r.cancelReason != null)
                _noteLine(
                  l10n.translate('res_cancel_reason'),
                  _r.cancelReason!,
                ),
              if (_r.orderCode != null)
                _noteLine(l10n.translate('res_linked_order'), _r.orderCode!),
              if (!online)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.translate('res_offline_writes'),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (_r.canConvert)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _ringUp,
                    icon: const Icon(Icons.point_of_sale_rounded),
                    label: Text(l10n.translate('res_convert')),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_r.status == ReservationStatus.booked)
                    OutlinedButton.icon(
                      onPressed: canWrite
                          ? () => _setStatus(ReservationStatus.confirmed)
                          : null,
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: Text(l10n.translate('res_mark_confirmed')),
                    ),
                  if (_r.status == ReservationStatus.booked ||
                      _r.status == ReservationStatus.confirmed)
                    OutlinedButton.icon(
                      onPressed: canWrite
                          ? () => _setStatus(ReservationStatus.arrived)
                          : null,
                      icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                      label: Text(l10n.translate('res_mark_arrived')),
                    ),
                  // A rung-up reservation keeps its basket but can still move.
                  if (_r.isEditable || _r.status == ReservationStatus.converted)
                    OutlinedButton.icon(
                      onPressed: canWrite ? _move : null,
                      icon: const Icon(Icons.schedule_outlined, size: 18),
                      label: Text(l10n.translate('res_move')),
                    ),
                  if (_r.isEditable) ...[
                    OutlinedButton.icon(
                      onPressed: canWrite ? _edit : null,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(l10n.translate('edit')),
                    ),
                    OutlinedButton.icon(
                      onPressed: canWrite
                          ? () => _setStatus(ReservationStatus.noShow)
                          : null,
                      icon: const Icon(Icons.person_off_outlined, size: 18),
                      label: Text(l10n.translate('res_mark_no_show')),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                      ),
                      onPressed: canWrite
                          ? () => _setStatus(ReservationStatus.canceled)
                          : null,
                      icon: const Icon(Icons.event_busy_outlined, size: 18),
                      label: Text(l10n.translate('res_cancel')),
                    ),
                  ],
                  // Restoring re-claims the slot, so it can 409.
                  if (_r.status == ReservationStatus.canceled ||
                      _r.status == ReservationStatus.noShow)
                    OutlinedButton.icon(
                      onPressed: canWrite
                          ? () => _setStatus(ReservationStatus.booked)
                          : null,
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: Text(l10n.translate('res_restore')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteLine(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: text),
        ],
      ),
    ),
  );
}
