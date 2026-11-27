import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/reservation_models.dart';
import '../../providers/reservation_providers.dart';
import '../../domain/services/reservation_service.dart';
import '../../utils/app_localizations.dart';
import 'reservation_actions.dart';
import 'reservation_detail_sheet.dart';
import 'reservation_panel.dart' show ResourceAvatar;
import 'side_panel.dart';

/// Bookings on one person or room that overlap beyond what it can hold at
/// once. Unconfirmed bookings are allowed to land like this (a phone booking
/// taken in a rush, two requests for the same slot); the agenda flags them
/// until someone decides.
class ConflictGroup {
  final AgendaResource resource;
  final List<({Reservation reservation, ReservationItem item})> entries;
  const ConflictGroup(this.resource, this.entries);

  DateTime get start => entries
      .map((e) => e.item.startAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get end =>
      entries.map((e) => e.item.endAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Every cluster of overlapping services on a resource whose peak exceeds
/// its capacity.
List<ConflictGroup> findConflicts(
  AgendaDay day,
  List<AgendaResource> resources,
) {
  // The server's list wins when it sends one, so the web back office and
  // the till flag the same cards. Otherwise work it out from the day.
  final server = day.serverConflicts;
  final flagged = server == null
      ? null
      : {for (final c in server) (c.itemId, c.resourceId)};
  final out = <ConflictGroup>[];
  for (final res in resources) {
    final items = [
      for (final r in day.reservations)
        if (r.holdsSlot)
          for (final it in r.items)
            if (it.timed &&
                it.resourceIds.contains(res.id) &&
                (flagged == null || flagged.contains((it.id, res.id))))
              (reservation: r, item: it),
    ]..sort((a, b) => a.item.startAt.compareTo(b.item.startAt));

    var cluster = <({Reservation reservation, ReservationItem item})>[];
    DateTime? clusterEnd;
    void close() {
      // A flagged service may stand alone (it clashes with another shop's
      // booking on shared staff); a local guess needs a real overlap.
      if (flagged != null
          ? cluster.isNotEmpty
          : cluster.length > 1 && _peak(cluster) > math.max(1, res.capacity)) {
        out.add(ConflictGroup(res, cluster));
      }
      cluster = [];
    }

    for (final e in items) {
      if (clusterEnd != null && !e.item.startAt.isBefore(clusterEnd)) {
        close();
        clusterEnd = null;
      }
      cluster.add(e);
      if (clusterEnd == null || e.item.endAt.isAfter(clusterEnd)) {
        clusterEnd = e.item.endAt;
      }
    }
    close();
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Most services running at the same instant within [entries].
int _peak(List<({Reservation reservation, ReservationItem item})> entries) {
  final events =
      <(DateTime, int)>[
        for (final e in entries) ...[(e.item.startAt, 1), (e.item.endAt, -1)],
      ]..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2); // ends before starts
      });
  var now = 0, peak = 0;
  for (final (_, d) in events) {
    now += d;
    peak = math.max(peak, now);
  }
  return peak;
}

/// Ids of the items involved in a conflict, for flagging cards.
Set<int> conflictItemIds(List<ConflictGroup> groups) => {
  for (final g in groups)
    for (final e in g.entries)
      if (e.item.id != null) e.item.id!,
};

/// Resources of the same kind that could take [item] as it is: open then,
/// no block, nothing booked there at that time.
List<AgendaResource> freeResourcesFor(
  AgendaDay day,
  List<AgendaResource> resources,
  ReservationItem item,
  int fromId,
) {
  final from = resources.where((r) => r.id == fromId).firstOrNull;
  return [
    for (final r in resources)
      if (r.id != fromId &&
          (from == null || r.isStaff == from.isStaff) &&
          _isOpen(day, r, item) &&
          !day.blocks.any(
            (b) =>
                b.resourceId == r.id &&
                b.startAt.isBefore(item.endAt) &&
                b.endAt.isAfter(item.startAt),
          ) &&
          !day.foreignBusy.any(
            (b) =>
                b.resourceId == r.id &&
                b.start.isBefore(item.endAt) &&
                b.end.isAfter(item.startAt),
          ) &&
          !day.reservations.any(
            (other) =>
                other.holdsSlot &&
                other.items.any(
                  (o) =>
                      o.timed &&
                      o.resourceIds.contains(r.id) &&
                      o.startAt.isBefore(item.endAt) &&
                      o.endAt.isAfter(item.startAt),
                ),
          ))
        r,
  ];
}

bool _isOpen(AgendaDay day, AgendaResource r, ReservationItem item) {
  if (day.fetchedAt == null) return true; // never pulled: do not guess
  final windows = r.availabilityOn(day.day);
  return windows.any((w) => w.contains(item.startAt, item.endAt));
}

Future<void> showConflictsPanel(
  BuildContext context,
  DateTime date,
  List<AgendaResource> resources,
) {
  return showSidePanel<void>(
    context,
    ConflictsPanel(date: date, resources: resources),
  );
}

/// Every overlap of the day, with what can be done about each booking.
class ConflictsPanel extends ConsumerWidget {
  final DateTime date;
  final List<AgendaResource> resources;
  const ConflictsPanel({
    super.key,
    required this.date,
    required this.resources,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final online = ref.watch(canReserveProvider);
    final day = ref.watch(agendaDayProvider(date)).valueOrNull;
    final groups = day == null
        ? const <ConflictGroup>[]
        : findConflicts(day, resources);
    final service = ref.read(reservationServiceProvider);

    return Column(
      children: [
        SidePanelHeader(
          title: l10n.translate('res_conflicts_title'),
          subtitle: l10n.translate('res_conflicts_hint'),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 48,
                        color: cs.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(l10n.translate('res_conflicts_none')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final g in groups)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ResourceAvatar(
                                    resource: g.resource,
                                    radius: 14,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${g.resource.name} · ${hmRange(g.start, g.end)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(),
                              for (final e in g.entries)
                                _entry(
                                  context,
                                  ref,
                                  l10n,
                                  cs,
                                  day!,
                                  g,
                                  e,
                                  online,
                                  service,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _entry(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ColorScheme cs,
    AgendaDay day,
    ConflictGroup g,
    ({Reservation reservation, ReservationItem item}) e,
    bool online,
    ReservationService service,
  ) {
    final r = e.reservation;
    final it = e.item;
    final colors = reservationStatusColors(r.status, cs);
    final free = freeResourcesFor(day, resources, it, g.resource.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => showReservationDetail(context, r),
                  child: Text(
                    '${hmRange(it.startAt, it.endAt)} · '
                    '${r.customerLabel.isEmpty ? r.code : r.customerLabel} · ${it.name}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  reservationStatusLabel(r.status, l10n),
                  style: TextStyle(fontSize: 11, color: colors.fg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (r.status == ReservationStatus.booked)
                FilledButton.tonalIcon(
                  onPressed: online
                      ? () => runReservationWrite(
                          ref,
                          context,
                          () => service.setStatus(
                            r.id,
                            ReservationStatus.confirmed,
                          ),
                          successKey: 'res_saved',
                          overbook: () => service.setStatus(
                            r.id,
                            ReservationStatus.confirmed,
                            overbook: true,
                          ),
                          overbookLabel: 'res_confirm_anyway',
                        )
                      : null,
                  icon: const Icon(Icons.verified_rounded, size: 16),
                  label: Text(l10n.translate('res_keep_this')),
                ),
              // Hand the service to someone free at that time, one tap.
              for (final f in free.take(4))
                OutlinedButton.icon(
                  onPressed: online && it.id != null
                      ? () => runReservationWrite(
                          ref,
                          context,
                          () => r.items.where((i) => i.timed).length == 1
                              ? service.move(
                                  r.id,
                                  startAt: it.startAt,
                                  resourceId: f.id,
                                )
                              : service.moveItem(
                                  it.id!,
                                  startAt: it.startAt,
                                  endAt: it.endAt,
                                  resourceIds: [
                                    for (final id in it.resourceIds)
                                      if (id == g.resource.id) f.id else id,
                                  ],
                                ),
                          successKey: 'res_moved',
                        )
                      : null,
                  icon: ResourceAvatar(resource: f, radius: 9),
                  label: Text(
                    l10n.translate('res_move_to').replaceAll('{name}', f.name),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => showReservationDetail(context, r),
                icon: const Icon(Icons.schedule_rounded, size: 16),
                label: Text(l10n.translate('res_move')),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: cs.error),
                onPressed: online
                    ? () => runReservationWrite(
                        ref,
                        context,
                        () =>
                            service.setStatus(r.id, ReservationStatus.canceled),
                        successKey: 'res_saved',
                      )
                    : null,
                child: Text(l10n.translate('res_cancel')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
