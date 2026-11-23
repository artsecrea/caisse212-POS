import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/account_status.dart';
import '../../providers/admin_elevation_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../services/kick_store.dart';
import '../../utils/pos_log.dart';

/// Sends whoever is signed in back to the login screen the moment the server
/// says the tenant, business or terminal was deactivated. The login screen then
/// holds sign-in until the account is active again.
///
/// Invisible, mounted once above the Navigator (like UpdateWatcher). Works for
/// every trigger: a 423 on any call, the `account_disabled` SSE push, or a
/// login/refresh body saying `accountStatus.active: false` — and for the
/// `force_kick` push, which signs out without locking.
///
/// What is kept: every saved order, ticket and the open cash session stay in
/// the local database, and queued sync work waits untouched. The shift resumes
/// after reactivation, exactly as after a normal sign-out.
class AccountBlockWatcher extends ConsumerWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const AccountBlockWatcher({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AccountBlock?>(accountBlockProvider, (prev, next) {
      if (prev != null || next == null) return;
      posLog('Account disabled (${next.scope.name}): signing the cashier out');
      _signOut(ref);
    });
    // force_kick: the session was already paused by the command handler.
    ref.listen<KickNotice?>(kickNoticeProvider, (prev, next) {
      if (next == null || identical(prev, next)) return;
      posLog('Kicked (${next.code}): signing the cashier out');
      _signOut(ref);
    });
    return const SizedBox.shrink();
  }

  void _signOut(WidgetRef ref) {
    if (ref.read(currentUserProvider) == null) return; // already on login
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(currentSessionProvider.notifier).state = null;
    ref.read(adminElevationProvider.notifier).state = null;
    ref.read(orderProvider.notifier).clearOrder();
    FocusManager.instance.primaryFocus?.unfocus();
    navigatorKey.currentState
        ?.pushNamedAndRemoveUntil('/login', (route) => false);
  }
}
