import '../../services/kds_stats_service.dart' show KdsSessionStats;

/// The kitchen's figures for a session. An interface because, linked to a
/// hub, the kitchen screens report to the hub: standalone, this till reads
/// its own database (`KdsStatsService`).
abstract interface class KdsStatsQueries {
  Future<KdsSessionStats> forSession(int? sessionId);
}
