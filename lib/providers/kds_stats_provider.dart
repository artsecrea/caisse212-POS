import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/kds_stats_service.dart';
import 'database_providers.dart';

final kdsStatsServiceProvider = Provider<KdsStatsService>((ref) {
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
