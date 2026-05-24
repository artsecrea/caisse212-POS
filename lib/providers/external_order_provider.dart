import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../domain/models/external_order_models.dart';
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

  const ExternalOrderState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.confirming = const {},
  });

  ExternalOrderState copyWith({
    List<ExternalQueueItem>? items,
    bool? isLoading,
    String? error,
    Set<int>? confirming,
    bool clearError = false,
  }) =>
      ExternalOrderState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        confirming: confirming ?? this.confirming,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ExternalOrderNotifier extends StateNotifier<ExternalOrderState> {
  final ExternalOrderQueueService _service;

  ExternalOrderNotifier(this._service) : super(const ExternalOrderState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _service.fetchPending();
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      Logger.instance.error('ExternalOrderNotifier: load error: $e');
      state = state.copyWith(
          isLoading: false, error: 'Failed to load: $e');
    }
  }

  /// Called when an SSE `new-order` event arrives — adds to list if not already present.
  void onNewOrderEvent(ExternalQueueItem item) {
    final exists = state.items.any((i) => i.id == item.id);
    if (!exists) {
      state = state.copyWith(items: [...state.items, item]);
    }
  }

  /// Acknowledges an item and writes it to local SQLite.
  /// [userId] is stored as [createdBy] on the resulting order row.
  /// Returns the local order ID on success, null on failure.
  Future<int?> confirm(int itemId, {int? userId}) async {
    final newConfirming = Set<int>.from(state.confirming)..add(itemId);
    state = state.copyWith(confirming: newConfirming, clearError: true);
    try {
      final item = state.items.firstWhere((i) => i.id == itemId);
      final orderId = await _service.acknowledgeAndSave(item,
          confirmedByUserId: userId);

      final remaining = state.items.where((i) => i.id != itemId).toList();
      final newConf = Set<int>.from(state.confirming)..remove(itemId);
      state = state.copyWith(items: remaining, confirming: newConf);
      return orderId;
    } catch (e) {
      Logger.instance.error('ExternalOrderNotifier: confirm error: $e');
      final newConf = Set<int>.from(state.confirming)..remove(itemId);
      state = state.copyWith(
          confirming: newConf, error: 'Failed to confirm: $e');
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
