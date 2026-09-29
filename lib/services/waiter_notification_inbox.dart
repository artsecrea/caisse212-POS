import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One notification as the waiter's inbox lists it.
class InboxEntry {
  /// `eventId` for kitchen events, `callId` for calls — the same id the live
  /// SSE frame carried, so the app can match history to what it already showed.
  final String id;

  /// null = broadcast (rupture): every waiter sees it.
  final int? waiterId;

  /// The SSE event name: `kitchen-ready`, `kitchen-canceled`,
  /// `product-availability`, `waiter-call`.
  final String type;
  final Map<String, dynamic> data;
  final DateTime at;

  InboxEntry({
    required this.id,
    required this.waiterId,
    required this.type,
    required this.data,
    required this.at,
  });
}

/// The waiter's notification history, held in memory only.
///
/// Push is a moment; this is what lets a waiter look back ("which table was
/// that tajine for?") at any time during the shift. Deliberately not in the
/// database: it is a convenience, not a record, so it lives as long as the POS
/// process does and a restart starts it empty. Bounded by count and age so a
/// till left running for a week does not grow without limit.
class WaiterNotificationInbox {
  static const int maxEntries = 1000;
  static const Duration maxAge = Duration(hours: 24);

  final List<InboxEntry> _entries = [];

  /// Read ids per waiter. A broadcast is read or unread per waiter, not once
  /// for the whole floor.
  final Map<int, Set<String>> _read = {};

  void add({
    required String id,
    required int? waiterId,
    required String type,
    required Map<String, dynamic> data,
    DateTime? at,
  }) {
    _purge();
    _entries.add(InboxEntry(
      id: id,
      waiterId: waiterId,
      type: type,
      data: data,
      at: at ?? DateTime.now(),
    ));
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  Iterable<InboxEntry> _visibleTo(int waiterId) =>
      _entries.where((e) => e.waiterId == null || e.waiterId == waiterId);

  /// Newest first.
  List<Map<String, dynamic>> listFor(int waiterId, {int limit = 100}) {
    _purge();
    final read = _read[waiterId] ?? const <String>{};
    return _visibleTo(waiterId)
        .toList()
        .reversed
        .take(limit)
        .map((e) => {
              'id': e.id,
              'type': e.type,
              'at': e.at.toIso8601String(),
              'read': read.contains(e.id),
              'data': e.data,
            })
        .toList();
  }

  int unreadCount(int waiterId) {
    _purge();
    final read = _read[waiterId] ?? const <String>{};
    return _visibleTo(waiterId).where((e) => !read.contains(e.id)).length;
  }

  bool isRead(int waiterId, String id) =>
      _read[waiterId]?.contains(id) ?? false;

  /// Marks [ids] read for [waiterId] — or everything they can see when null.
  void markRead(int waiterId, [Iterable<String>? ids]) {
    final set = _read[waiterId] ??= <String>{};
    set.addAll(ids ?? _visibleTo(waiterId).map((e) => e.id));
  }

  void _purge() {
    final cutoff = DateTime.now().subtract(maxAge);
    _entries.removeWhere((e) => e.at.isBefore(cutoff));
    if (_entries.isEmpty) {
      _read.clear();
      return;
    }
    final live = _entries.map((e) => e.id).toSet();
    for (final s in _read.values) {
      s.retainAll(live);
    }
  }
}

final waiterNotificationInboxProvider =
    Provider<WaiterNotificationInbox>((ref) => WaiterNotificationInbox());
