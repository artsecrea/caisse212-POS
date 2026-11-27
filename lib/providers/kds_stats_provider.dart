import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kds_stats_service.dart';
import 'database_providers.dart';
import '../domain/services/kds_stats_queries.dart';

/// The kitchen stats for the screens. A hub-linked till overrides this one
/// provider; nothing else changes.
final kdsStatsServiceProvider = Provider<KdsStatsQueries>((ref) {
  return KdsStatsService(ref.read(databaseProvider));
});

/// Kitchen stats for the CURRENT session. Recomputes whenever the session
/// changes. LAN/local only — never touches the cloud. `.refresh()` for a
/// manual re-read (KDS states change out-of-band via the LAN endpoints).
final kdsSessionStatsProvider = FutureProvider<KdsSessionStats>((ref) async {
  final session = ref.watch(currentSessionProvider);
  final service = ref.read(kdsStatsServiceProvider);
  return service.forSession(session?.id);
});
