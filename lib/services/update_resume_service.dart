import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../domain/models/order_models.dart';
import '../domain/models/order_snapshot.dart';
import '../providers/admin_elevation_provider.dart';
import '../providers/database_providers.dart';
import '../providers/held_orders_provider.dart';
import '../providers/order_provider.dart';
import 'session_service.dart';

typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Carries the signed-in cashier across the restart an update forces, so the
/// till comes back on the same user, cash session and Z with the cart and the
/// held orders intact — instead of the login screen and empty baskets.
///
/// Written right before the updater takes over, read once on the next start.
/// Single use and short-lived: it lets exactly one start skip the password,
/// and only within [ttl] of the restart.
class UpdateResume {
  UpdateResume._();

  static const _key = 'update_resume';
  static const ttl = Duration(minutes: 15);

  static Future<void> save(Reader read) async {
    final prefs = read(sharedPreferencesProvider);
    final user = read(currentUserProvider);
    final session = read(currentSessionProvider);
    if (user == null || session == null) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(
        _key,
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'userId': user.id,
          'sessionId': session.id,
          'zId': read(currentZProvider)?.id,
          'cart': orderToSnapshot(read(orderProvider)),
          'held': read(heldOrdersProvider).map(orderToSnapshot).toList(),
        }));
    Logger.instance.info(
        'Update resume saved for user ${user.id}, session ${session.id}');
  }

  /// The restart didn't happen (UAC declined…): nothing to resume.
  static Future<void> clear(Reader read) =>
      read(sharedPreferencesProvider).remove(_key);

  /// Restores the saved state. True when the till is signed back in and the
  /// caller should go straight to the main screen.
  static Future<bool> tryRestore(Reader read) async {
    final prefs = read(sharedPreferencesProvider);
    final raw = prefs.getString(_key);
    if (raw == null) return false;
    await prefs.remove(_key); // single use, whatever happens below

    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(j['savedAt'] as String? ?? '');
      final age = savedAt == null ? null : DateTime.now().difference(savedAt);
      if (age == null || age.isNegative || age > ttl) {
        Logger.instance.info('Update resume expired — normal login');
        return false;
      }

      final database = read(databaseProvider);
      final userId = (j['userId'] as num).toInt();
      final user = await (database.select(database.users)
            ..where((u) => u.id.equals(userId)))
          .getSingleOrNull();
      if (user == null) return false;

      final sessionService = SessionService(database);
      var session =
          await sessionService.getSessionById((j['sessionId'] as num).toInt());
      if (session == null ||
          session.cashierId != userId ||
          !(session.status == 'active' || session.status == 'paused')) {
        Logger.instance.info('Update resume: session no longer open');
        return false;
      }
      if (session.status == 'paused') {
        await sessionService.resumeSession(session.id);
        session = await sessionService.getSessionById(session.id);
        if (session == null) return false;
      }

      final zId = (j['zId'] as num?)?.toInt();
      final z = zId == null ? null : await read(zServiceProvider).getById(zId);
      if (zId != null && (z == null || z.status != 'open')) {
        // Closed while the till was restarting: the normal login decides
        // what happens next.
        Logger.instance.info('Update resume: Z $zId no longer open');
        return false;
      }

      read(currentUserProvider.notifier).state = CurrentUser.fromUser(user);
      // Admin elevation is never carried across.
      read(adminElevationProvider.notifier).state = null;
      read(currentZProvider.notifier).state = z;
      read(currentSessionProvider.notifier).state = session;

      final cart = j['cart'];
      read(orderProvider.notifier).loadOrder(cart is Map
          ? orderFromSnapshot(Map<String, dynamic>.from(cart))
          : CurrentOrder());
      read(heldOrdersProvider.notifier).state = ((j['held'] as List?) ?? const [])
          .map((e) => orderFromSnapshot(Map<String, dynamic>.from(e as Map)))
          .toList();

      Logger.instance
          .info('Update resume: user $userId back on session ${session.id}');
      return true;
    } catch (e) {
      Logger.instance.error('Update resume failed — normal login: $e');
      return false;
    }
  }
}
