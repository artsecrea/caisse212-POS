import '../../data/database/app_database.dart' show Product;

/// What creating a product from the till gave back.
class QuickCreateResult {
  /// The product row as it now exists locally — ready to add to the ticket.
  final Product product;

  /// False when the barcode already existed and the server returned the
  /// existing product. **This is a success**, not an error: the cashier scanned
  /// something that is already in the catalogue, and what they want is to sell
  /// it, not to be told off.
  final bool created;

  const QuickCreateResult({required this.product, required this.created});
}
