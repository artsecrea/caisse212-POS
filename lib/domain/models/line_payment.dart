/// Whether money has been taken for an order line.
///
/// Paid-ness is the ticket claiming the line (`ticketId`). `state` is the
/// KITCHEN stage and payment leaves it alone, so a line paid up front still
/// reaches the KDS as food to cook. `state == 'PAID'` is still honoured for
/// rows written before the two were separated, and for a line the cloud
/// reports paid that no ticket on this till covers.
bool isLinePaid(String state, int? ticketId) =>
    ticketId != null || state == 'PAID';

/// [state] as the settlement checks read it ([isOrderSettled]): `PAID` for a
/// paid line, the stored state otherwise.
String settlementState(String state, int? ticketId) =>
    isLinePaid(state, ticketId) ? 'PAID' : state;
