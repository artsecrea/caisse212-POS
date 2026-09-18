import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../domain/models/external_order_models.dart';
import '../services/api_service.dart' show QueueItemTakenException;
import '../services/external_order_queue_service.dart';
import 'database_providers.dart';

// ── Service provider ──────────────────────────────────────────────────────────

final externalOrderQueueServiceProvider =
    Provider<ExternalOrderQueueService>((ref) {
  return ExternalOrderQueueService(
    ref.watch(apiServiceProvider),
    ref.watch(databaseProvider),
  );
});

// ── State ─────────────────────────────────────────────────────────────────────

class ExternalOrderState {
  final List<ExternalQueueItem> items;
  final bool isLoading;
  final String? error;
  /// IDs of items currently being confirmed
  final Set<int> confirming;

  /// Active filters. `null` source = all sources. Status defaults to PENDING —
  /// the actionable set, and what the screen existed to show before browsing
  /// history was possible.
  final String? sourceFilter;
  final String statusFilter;

  // Server-reported paging. Held rather than derived so the pager can say
  // "page 2 of 4 - 64 orders" truthfully on a partially-filled last page.
  final int page;
  final int pageSize;
  final int totalElements;
  final int totalPages;
  final bool isFirstPage;
  final bool isLastPage;

  /// Per-source tallies for the chips, scoped to [statusFilter].
  final QueueCounts counts;

  const ExternalOrderState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.confirming = const {},
    this.sourceFilter,
    this.statusFilter = 'PENDING',
    this.page = 0,
    this.pageSize = 20,
    this.totalElements = 0,
    this.totalPages = 0,
    this.isFirstPage = true,
    this.isLastPage = true,
    this.counts = const QueueCounts(),
  });

  bool get hasFilters => sourceFilter != null || statusFilter != 'PENDING';

  /// 1-based, and never 0 — an empty result still reads "page 1 of 1".
  int get displayPage => page + 1;
  int get displayTotalPages => totalPages < 1 ? 1 : totalPages;

  ExternalOrderState copyWith({
    List<ExternalQueueItem>? items,
    bool? isLoading,
    String? error,
    Set<int>? confirming,
    String? sourceFilter,
    bool clearSourceFilter = false,
    String? statusFilter,
    int? page,
    int? pageSize,
    int? totalElements,
    int? totalPages,
    bool? isFirstPage,
    bool? isLastPage,
    QueueCounts? counts,
    bool clearError = false,
  }) =>
      ExternalOrderState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        confirming: confirming ?? this.confirming,
        // Explicit clear flag: copyWith treats null as "keep", so selecting the
        // "All" chip needs its own signal.
        sourceFilter: clearSourceFilter ? null : (sourceFilter ?? this.sourceFilter),
        statusFilter: statusFilter ?? this.statusFilter,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
        totalElements: totalElements ?? this.totalElements,
        totalPages: totalPages ?? this.totalPages,
        isFirstPage: isFirstPage ?? this.isFirstPage,
        isLastPage: isLastPage ?? this.isLastPage,
        counts: counts ?? this.counts,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ExternalOrderNotifier extends StateNotifier<ExternalOrderState> {
  final ExternalOrderQueueService _service;

  ExternalOrderNotifier(this._service) : super(const ExternalOrderState()) {
    load();
  }

  /// Load the current page with the current filters, and refresh the chip
  /// counts alongside it.
  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await _service.browse(
        page: state.page,
        size: state.pageSize,
        source: state.sourceFilter,
        status: state.statusFilter,
      );

      // A page can go out of range when rows are confirmed away underneath us,
      // or after the 7-day purge. Step back rather than showing an empty screen
      // with a pager that says "page 3 of 2".
      if (page.isEmpty && page.page > 0 && page.totalPages <= page.page) {
        state = state.copyWith(
            page: page.totalPages > 0 ? page.totalPages - 1 : 0);
        await load();
        return;
      }

      state = state.copyWith(
        items: page.content,
        isLoading: false,
        page: page.page,
        totalElements: page.totalElements,
        totalPages: page.totalPages,
        isFirstPage: page.first,
        isLastPage: page.last,
      );
    } catch (e) {
      Logger.instance.error('ExternalOrderNotifier: load error: $e');
      state = state.copyWith(
          isLoading: false, error: 'Failed to load: $e');
    }
    await refreshCounts();
  }

  /// Chip tallies, scoped to the active status filter so the badges match what
  /// tapping a chip will actually show. Never fails the screen.
  Future<void> refreshCounts() async {
    try {
      final c = await _service.counts(status: state.statusFilter);
      state = state.copyWith(counts: c);
    } catch (e) {
      Logger.instance.warning('ExternalOrderNotifier: counts failed: $e');
    }
  }

  /// Filter by platform. Passing null (the "All" chip) clears it.
  /// Always returns to page 0 — staying on page 3 of the previous filter would
  /// land the cashier in the middle of a different result set.
  Future<void> setSource(String? source) async {
    state = state.copyWith(
      sourceFilter: source,
      clearSourceFilter: source == null,
      page: 0,
    );
    await load();
  }

  Future<void> setStatus(String status) async {
    state = state.copyWith(statusFilter: status, page: 0);
    await load();
  }

  Future<void> goToPage(int page) async {
    if (page < 0 || page == state.page) return;
    state = state.copyWith(page: page);
    await load();
  }

  Future<void> nextPage() =>
      state.isLastPage ? Future.value() : goToPage(state.page + 1);

  Future<void> previousPage() =>
      state.isFirstPage ? Future.value() : goToPage(state.page - 1);

  /// SSE `new-order`. Inserted at the TOP (the list is newest-first) and only
  /// when it belongs in the current view: pushing a GLOVO order into a KOOUL
  /// filter, or onto page 3, would be lying about what the page contains.
  /// A queued order was cancelled on the platform (or by an admin).
  ///
  /// Removes it from the visible list so nobody works a dead ticket, and reports
  /// whether it had already been CONFIRMED — the caller escalates that case,
  /// because confirmed means the kitchen may already be cooking food that nobody
  /// is coming to collect.
  bool onOrderCancelledEvent({int? queueItemId, String? orderCode}) {
    if (queueItemId == null && orderCode == null) return false;

    ExternalQueueItem? hit;
    for (final i in state.items) {
      if ((queueItemId != null && i.id == queueItemId) ||
          (orderCode != null && i.orderCode == orderCode)) {
        hit = i;
        break;
      }
    }

    if (hit != null) {
      state = state.copyWith(
        items: state.items.where((i) => i.id != hit!.id).toList(),
        totalElements:
            state.totalElements > 0 ? state.totalElements - 1 : 0,
      );
    }
    refreshCounts();

    // Not in the current view does not mean not confirmed — it may simply be on
    // another page or behind a filter. Reload so the list is truthful either way.
    if (hit == null) load();

    return hit != null && (hit.isConfirmed || hit.isAcknowledged);
  }

  void onNewOrderEvent(ExternalQueueItem item) {
    final matchesStatus = item.status.toUpperCase() == state.statusFilter;
    final matchesSource = state.sourceFilter == null ||
        ExternalOrderQueueService.matchesSource(item.source, state.sourceFilter!);
    if (!matchesStatus || !matchesSource || state.page != 0) {
      // Not visible here — but the badge should still move, so the cashier sees
      // that something arrived under another chip.
      refreshCounts();
      return;
    }
    if (state.items.any((i) => i.id == item.id)) return;
    state = state.copyWith(
      items: [item, ...state.items],
      totalElements: state.totalElements + 1,
    );
    refreshCounts();
  }

  /// Confirms a queue item and writes the resulting order to local
  /// SQLite via [ExternalOrderQueueService.confirmAndSave].
  ///
  /// [userId] is stored as `createdBy` on the resulting order row.
  /// [overrideClientId] short-circuits the phone-based customer upsert
  /// (used by [ExternalCustomerReviewDialog] so the cashier's choice
  /// flows through).
  ///
  /// Returns the local order ID on success.
  /// Returns `null` and surfaces a specific error string when the
  /// server responds 409 (another POS already took or cancelled this
  /// item) — the item is dropped from the queue view either way.
  Future<int?> confirm(int itemId,
      {int? userId, int? overrideClientId}) async {
    final newConfirming = Set<int>.from(state.confirming)..add(itemId);
    state = state.copyWith(confirming: newConfirming, clearError: true);
    try {
      final item = state.items.firstWhere((i) => i.id == itemId);
      final orderId = await _service.confirmAndSave(
        item,
        confirmedByUserId: userId,
        overrideClientId: overrideClientId,
      );

      final remaining = state.items.where((i) => i.id != itemId).toList();
      final newConf = Set<int>.from(state.confirming)..remove(itemId);
      state = state.copyWith(items: remaining, confirming: newConf);
      return orderId;
    } on QueueItemTakenException catch (_) {
      // Another POS / admin already confirmed or cancelled this item.
      // Drop it from the queue view; the cashier should see a "taken"
      // toast rather than a generic error.
      Logger.instance.info(
          'ExternalOrderNotifier: queue item $itemId already taken — dropping');
      final remaining = state.items.where((i) => i.id != itemId).toList();
      final newConf = Set<int>.from(state.confirming)..remove(itemId);
      state = state.copyWith(
        items: remaining,
        confirming: newConf,
        error: 'TAKEN', // call-site key, mapped to a translated toast
      );
      return null;
    } catch (e) {
      Logger.instance.error('ExternalOrderNotifier: confirm error: $e');
      final newConf = Set<int>.from(state.confirming)..remove(itemId);
      state = state.copyWith(
          confirming: newConf, error: 'Failed to confirm: $e');
      return null;
    }
  }

  /// Cancels a queue item — server flips state to CANCELLED, DealUp is
  /// notified, and the order is saved locally with `status=CANCELED`
  /// (for the audit trail).
  ///
  /// 409 (already cancelled elsewhere) is treated as success by the
  /// service layer — we still drop the item from the queue view.
  ///
  /// Returns the local order ID on success, null on transport failure.
  Future<int?> cancel(int itemId, {int? userId}) async {
    final newConfirming = Set<int>.from(state.confirming)..add(itemId);
    state = state.copyWith(confirming: newConfirming, clearError: true);
    try {
      final item = state.items.firstWhere((i) => i.id == itemId);
      final orderId = await _service.cancelAndSave(
        item,
        confirmedByUserId: userId,
      );
      final remaining = state.items.where((i) => i.id != itemId).toList();
      final newConf = Set<int>.from(state.confirming)..remove(itemId);
      state = state.copyWith(items: remaining, confirming: newConf);
      return orderId;
    } catch (e) {
      Logger.instance.error('ExternalOrderNotifier: cancel error: $e');
      final newConf = Set<int>.from(state.confirming)..remove(itemId);
      state = state.copyWith(
          confirming: newConf, error: 'Failed to cancel: $e');
      return null;
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final externalOrderProvider =
    StateNotifierProvider<ExternalOrderNotifier, ExternalOrderState>((ref) {
  final service = ref.watch(externalOrderQueueServiceProvider);
  return ExternalOrderNotifier(service);
});
