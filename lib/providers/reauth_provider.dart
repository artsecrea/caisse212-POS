import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import 'database_providers.dart';

/// Whether the terminal must re-authenticate NOW. Turns true when the refresh
/// (session) token is expired or within the lead window of expiring, or when a
/// refresh was hard-rejected by the server. Watched at the app root so its
/// timer stays alive; drives the obligatory re-auth overlay.
class ReauthNotifier extends StateNotifier<bool> {
  final ApiService _api;
  Timer? _timer;
  StreamSubscription<void>? _sub;

  ReauthNotifier(this._api) : super(false) {
    _check();
    // Idle terminals need a poll (no requests fire to trigger the interceptor).
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _check());
    // Hard failure (refresh 4xx / revoked) → same obligatory dialog, at once.
    _sub = _api.forceLogoutStream.listen((_) {
      if (mounted) state = true;
    });
  }

  void _check() {
    if (!mounted) return;
    if (_api.isReauthDue()) state = true;
  }

  /// Re-evaluate after a re-auth attempt: clears the flag once the session is
  /// healthy again (new tokens saved), keeps it set otherwise.
  void reevaluate() {
    if (!mounted) return;
    state = _api.isReauthDue();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

final reauthRequiredProvider =
    StateNotifierProvider<ReauthNotifier, bool>((ref) {
  return ReauthNotifier(ref.watch(apiServiceProvider));
});

/// Set when somebody chooses to renew the sign-in EARLY, from the advance
/// notice, rather than being forced to by [reauthRequiredProvider].
///
/// Same dialog either way — the only difference is that this one can be waved
/// away, because nothing is broken yet.
final reauthVoluntaryProvider = StateProvider<bool>((ref) => false);
