import '../../data/database/app_database.dart' show Customer;

/// The business's customers, as a till looks them up and adds them. An
/// interface because customers are shared by every till: standalone, this
/// till keeps its own copy (`CustomerRepository`); linked to a hub, the hub
/// will hold them.
///
/// A customer is one per phone: saving a phone that is already known updates
/// that customer instead of adding a second one.
abstract interface class CustomerService {
  /// Every customer, as it changes. Unfiltered: the picker narrows it on the
  /// display label, which is not stored.
  Stream<List<Customer>> watchAll();

  Future<List<Customer>> getAll();

  Future<Customer?> getById(int id);

  Future<List<Customer>> getByIds(Iterable<int> ids);

  /// Up to six customers whose name or phone contains [lowerText] (trimmed
  /// and lowercased).
  Future<List<Customer>> searchByNameOrPhone(String lowerText);

  /// A customer with this already-normalised phone, if any.
  Future<Customer?> findByPhoneNormalized(String phoneNorm);

  /// Add the customer of [phoneRaw], or update the one already known by it
  /// with the fields given non-empty. Returns its id; null when the phone is
  /// blank. [isSynced] marks a customer that came from the server.
  Future<int?> upsertByPhone({
    required String? phoneRaw,
    String firstName = '',
    String lastName = '',
    String? email,
    bool isSynced = false,
  });
}
