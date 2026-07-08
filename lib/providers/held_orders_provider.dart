import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/order_models.dart';

/// In-RAM "wait" stack. Holds carts that the cashier parked temporarily
/// without saving to the DB. Lost on app restart — by design.
final heldOrdersProvider =
    StateProvider<List<CurrentOrder>>((ref) => const []);
