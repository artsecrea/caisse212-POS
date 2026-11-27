import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import 'reservation_providers.dart' show reservationServiceProvider;

/// All active bookable resources (staff, rooms, chairs, equipment), reactive
/// to the local Resources table. In the back office's order.
final resourcesProvider = StreamProvider<List<Resource>>(
    (ref) => ref.watch(reservationServiceProvider).watchResources());

/// Quick id → resource lookup for rendering assigned resources on the agenda.
final resourcesByIdProvider = Provider<Map<int, Resource>>((ref) {
  final list = ref.watch(resourcesProvider).valueOrNull ?? const [];
  return {for (final r in list) r.id: r};
});

