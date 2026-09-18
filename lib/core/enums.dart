// Order Status
enum OrderStatus {
  onHold('ONHOLD'),
  pending('PENDING'),
  preparing('PREPARING'),
  ready('READY'),
  delivered('DELIVERED');

  final String value;
  const OrderStatus(this.value);

  static OrderStatus fromString(String value) {
    return OrderStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OrderStatus.onHold,
    );
  }
}

// Order Type
enum OrderType {
  dineIn('DINE_IN'),
  takeAway('TAKE_AWAY'),
  delivery('DELIVERY');

  final String value;
  const OrderType(this.value);

  static OrderType fromString(String value) {
    return OrderType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OrderType.dineIn,
    );
  }
}

// Table State
enum TableState {
  available('AVAILABLE'),
  occupied('OCCUPIED'),
  reserved('RESERVED');

  final String value;
  const TableState(this.value);

  static TableState fromString(String value) {
    return TableState.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TableState.available,
    );
  }
}

// Transaction Type
enum TransactionType {
  card('CARD'),
  cash('CASH'),
  mobile('MOBILE'),
  other('OTHER');

  final String value;
  const TransactionType(this.value);

  static TransactionType fromString(String value) {
    return TransactionType.values.firstWhere(
      (e) => e.value == value,
      // Unknown → `other`, NOT `cash`.
      //
      // The money has to land in some bucket (dropping it would understate
      // takings), but claiming an unrecognised method is physical cash inflates
      // `expectedCashAtEnd` and produces a phantom drawer shortage the cashier
      // gets blamed for. `other` keeps it in the takings total while leaving the
      // expected-cash figure alone.
      //
      // This is reachable: the backend's own vocabulary already includes
      // TRANSFER and CHECK (see the refund contract), neither of which is in
      // this enum. If a ticket ever carries one, mis-filing it as cash is the
      // expensive mistake and mis-filing it as other is the cheap one.
      orElse: () => TransactionType.other,
    );
  }
}

