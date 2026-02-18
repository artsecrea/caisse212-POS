// import 'package:flutter/material.dart';
// import 'package:flutter/scheduler.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:drift/drift.dart' hide Column;
// import 'package:loggecrea/loggecrea.dart';
// import 'package:posecrea/providers/database_providers.dart';
// import 'package:posecrea/data/database/app_database.dart';
// import 'package:posecrea/utils/app_localizations.dart';
// import 'package:posecrea/utils/currency_formatter.dart';
// import '../../domain/models/order_models.dart';
// import '../../core/enums.dart';
//
// /// Calculator mode enum
// enum CalculatorMode {
//   amount, // Direct amount entry
//   quick,  // Quick preset buttons (10, 20, 50, 100)
// }
//
// /// Ticket data model for split payments
// class TicketData {
//   final int? ticketId;
//   final String? ticketNum;
//   final List<OrderItem> items;
//   final TransactionType paymentMethod;
//   final bool isPaid;
//   final int printCount;
//   final double discountPercentage;
//
//   TicketData({
//     this.ticketId,
//     this.ticketNum,
//     required this.items,
//     this.paymentMethod = TransactionType.cash,
//     this.isPaid = false,
//     this.printCount = 0,
//     this.discountPercentage = 0.0,
//   });
//
//   TicketData copyWith({
//     int? ticketId,
//     String? ticketNum,
//     List<OrderItem>? items,
//     TransactionType? paymentMethod,
//     bool? isPaid,
//     int? printCount,
//     double? discountPercentage,
//   }) {
//     return TicketData(
//       ticketId: ticketId ?? this.ticketId,
//       ticketNum: ticketNum ?? this.ticketNum,
//       items: items ?? this.items,
//       paymentMethod: paymentMethod ?? this.paymentMethod,
//       isPaid: isPaid ?? this.isPaid,
//       printCount: printCount ?? this.printCount,
//       discountPercentage: discountPercentage ?? this.discountPercentage,
//     );
//   }
//
//   double get subtotal => items.fold<double>(0.0, (sum, item) => sum + (item.subtotalPerItem * item.quantity));
//   double get itemDiscount => items.fold<double>(0.0, (sum, item) => sum + item.totalDiscount);
//   double get totalTva => items.fold<double>(0.0, (sum, item) => sum + item.totalTva);
//
//   double get manualDiscountAmount {
//     final base = (subtotal + totalTva - itemDiscount);
//     if (base <= 0 || discountPercentage <= 0) return 0.0;
//     return base * (discountPercentage / 100.0);
//   }
//
//   double get total {
//     final result = (subtotal + totalTva - itemDiscount) - manualDiscountAmount;
//     return result < 0 ? 0.0 : result;
//   }
// }
//
// /// Calculator state
// class CalculatorState {
//   final String display;
//   final double enteredAmount;
//   final CalculatorMode mode;
//
//   CalculatorState({
//     this.display = '0',
//     this.enteredAmount = 0.0,
//     this.mode = CalculatorMode.amount,
//   });
//
//   CalculatorState copyWith({
//     String? display,
//     double? enteredAmount,
//     CalculatorMode? mode,
//   }) {
//     return CalculatorState(
//       display: display ?? this.display,
//       enteredAmount: enteredAmount ?? this.enteredAmount,
//       mode: mode ?? this.mode,
//     );
//   }
// }
//
// // Providers
// final ticketsProvider = StateProvider<List<TicketData>>((ref) => []);
// final calculatorProvider = StateProvider<CalculatorState>((ref) => CalculatorState());
// final selectedTicketProvider = StateProvider<int?>((ref) => null);
//
// /// Modern Payment Screen - Rebuilt for touch screens
// class PaymentScreen extends ConsumerStatefulWidget {
//   final CurrentOrder order;
//
//   const PaymentScreen({
//     super.key,
//     required this.order,
//   });
//
//   @override
//   ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
// }
//
// class _PaymentScreenState extends ConsumerState<PaymentScreen> {
//   final _logger = Logger.instance;
//
//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _initializeTickets();
//     });
//   }
//
//   void _initializeTickets() {
//     final items = widget.order.items;
//
//     // Group items by ticketId
//     final Map<int?, List<OrderItem>> grouped = {};
//     for (var item in items) {
//       grouped.putIfAbsent(item.ticketId, () => []).add(item);
//     }
//
//     final List<TicketData> tickets = [];
//
//     // Create tickets for paid items
//     grouped.forEach((ticketId, ticketItems) {
//       if (ticketId != null) {
//         // Generate ticket number from ID and get payment method from order data
//         final ticketNumStr = ticketId.toString().padLeft(4, '0');
//
//         tickets.add(TicketData(
//           ticketId: ticketId,
//           ticketNum: ticketNumStr,
//           items: ticketItems,
//           paymentMethod: TransactionType.cash, // Will be overridden by actual payment method if available
//           isPaid: true,
//           discountPercentage: widget.order.discountPercentage,
//         ));
//       }
//     });
//
//     // Create ticket for unpaid items
//     final unpaidItems = grouped[null] ?? [];
//     if (unpaidItems.isNotEmpty) {
//       tickets.add(TicketData(
//         items: unpaidItems,
//         discountPercentage: widget.order.discountPercentage,
//       ));
//     }
//
//     // Ensure at least one ticket exists
//     if (tickets.isEmpty) {
//       tickets.add(TicketData(
//         items: [],
//         discountPercentage: widget.order.discountPercentage,
//       ));
//     }
//
//     ref.read(ticketsProvider.notifier).state = tickets;
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final tickets = ref.watch(ticketsProvider);
//     final theme = Theme.of(context);
//     final isDark = theme.brightness == Brightness.dark;
//
//     return Dialog(
//       backgroundColor: Colors.transparent,
//       insetPadding: const EdgeInsets.all(8),
//       child: Container(
//         constraints: BoxConstraints(
//           maxWidth: MediaQuery.of(context).size.width * 0.98,
//           maxHeight: MediaQuery.of(context).size.height * 0.98,
//         ),
//         decoration: BoxDecoration(
//           color: theme.colorScheme.surface,
//           borderRadius: BorderRadius.circular(16),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.3),
//               blurRadius: 24,
//               offset: const Offset(0, 8),
//             ),
//           ],
//         ),
//         child: Column(
//           children: [
//             _buildHeader(),
//             Expanded(
//               child: Row(
//                 children: [
//                   // Tickets area - 60% width
//                   Expanded(
//                     flex: 6,
//                     child: _buildTicketsArea(tickets),
//                   ),
//
//                   // Divider
//                   Container(
//                     width: 1,
//                     color: theme.dividerColor,
//                   ),
//
//                   // Payment calculator - 40% width
//                   Expanded(
//                     flex: 4,
//                     child: _buildPaymentPanel(),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildHeader() {
//     final theme = Theme.of(context);
//     final l10n = AppLocalizations.of(context)!;
//
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
//       decoration: BoxDecoration(
//         color: theme.colorScheme.primaryContainer,
//         borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
//       ),
//       child: Row(
//         children: [
//           Icon(
//             Icons.payments_rounded,
//             size: 32,
//             color: theme.colorScheme.onPrimaryContainer,
//           ),
//           const SizedBox(width: 16),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   l10n.translate('split_payment'),
//                   style: TextStyle(
//                     fontSize: 22,
//                     fontWeight: FontWeight.bold,
//                     color: theme.colorScheme.onPrimaryContainer,
//                   ),
//                 ),
//                 Text(
//                   'Order: ${widget.order.orderCode}',
//                   style: TextStyle(
//                     fontSize: 14,
//                     color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           IconButton(
//             onPressed: () => Navigator.of(context).pop(),
//             icon: Icon(
//               Icons.close_rounded,
//               size: 28,
//               color: theme.colorScheme.onPrimaryContainer,
//             ),
//             tooltip: l10n.translate('close'),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildTicketsArea(List<TicketData> tickets) {
//     return Column(
//       children: [
//         // Tickets header with add button
//         Padding(
//           padding: const EdgeInsets.all(16),
//           child: Row(
//             children: [
//               Text(
//                 'Tickets (${tickets.length})',
//                 style: const TextStyle(
//                   fontSize: 20,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const Spacer(),
//               ElevatedButton.icon(
//                 onPressed: _addNewTicket,
//                 icon: const Icon(Icons.add_rounded, size: 22),
//                 label: const Text('New Ticket', style: TextStyle(fontSize: 16)),
//                 style: ElevatedButton.styleFrom(
//                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//
//         // Tickets grid
//         Expanded(
//           child: tickets.isEmpty
//               ? const Center(child: Text('No tickets'))
//               : GridView.builder(
//                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                   gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
//                     maxCrossAxisExtent: 450,
//                     childAspectRatio: 0.75,
//                     crossAxisSpacing: 16,
//                     mainAxisSpacing: 16,
//                   ),
//                   itemCount: tickets.length,
//                   itemBuilder: (context, index) => _buildTicketCard(index, tickets[index]),
//                 ),
//         ),
//       ],
//     );
//   }
//
//   Widget _buildTicketCard(int index, TicketData ticket) {
//     final theme = Theme.of(context);
//     final isDark = theme.brightness == Brightness.dark;
//     final selectedIndex = ref.watch(selectedTicketProvider);
//     final isSelected = selectedIndex == index;
//     final currencyFormatter = ref.watch(currencyFormatterProvider);
//
//     return GestureDetector(
//       onTap: () => _selectTicket(index),
//       child: Container(
//         decoration: BoxDecoration(
//           color: ticket.isPaid
//               ? (isDark ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.green.shade50)
//               : (isSelected ? theme.colorScheme.primaryContainer : theme.cardColor),
//           borderRadius: BorderRadius.circular(16),
//           border: Border.all(
//             color: isSelected
//                 ? theme.colorScheme.primary
//                 : (ticket.isPaid ? Colors.green : theme.dividerColor),
//             width: isSelected ? 3 : 2,
//           ),
//           boxShadow: isSelected
//               ? [
//                   BoxShadow(
//                     color: theme.colorScheme.primary.withValues(alpha: 0.3),
//                     blurRadius: 12,
//                     offset: const Offset(0, 4),
//                   ),
//                 ]
//               : null,
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // Ticket header
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: ticket.isPaid
//                     ? (isDark ? Colors.green.shade800 : Colors.green.shade100)
//                     : (isSelected
//                         ? theme.colorScheme.primary.withValues(alpha: 0.1)
//                         : theme.colorScheme.surfaceContainerHighest),
//                 borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
//               ),
//               child: Row(
//                 children: [
//                   Icon(
//                     ticket.isPaid ? Icons.check_circle_rounded : Icons.receipt_rounded,
//                     size: 28,
//                     color: ticket.isPaid ? Colors.green.shade700 : theme.colorScheme.primary,
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           ticket.ticketNum != null ? 'Ticket #${ticket.ticketNum}' : 'Ticket ${index + 1}',
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                             color: ticket.isPaid ? Colors.green.shade700 : null,
//                           ),
//                         ),
//                         Text(
//                           '${ticket.items.length} items',
//                           style: TextStyle(
//                             fontSize: 14,
//                             color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   if (!ticket.isPaid && tickets.length > 1)
//                     IconButton(
//                       onPressed: () => _removeTicket(index),
//                       icon: const Icon(Icons.close_rounded),
//                       tooltip: 'Remove ticket',
//                     ),
//                 ],
//               ),
//             ),
//
//             // Ticket items
//             Expanded(
//               child: ticket.items.isEmpty
//                   ? Center(
//                       child: Text(
//                         'Drag items here\nor add from order',
//                         textAlign: TextAlign.center,
//                         style: TextStyle(
//                           color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
//                           fontSize: 16,
//                         ),
//                       ),
//                     )
//                   : ListView.builder(
//                       padding: const EdgeInsets.all(12),
//                       itemCount: ticket.items.length,
//                       itemBuilder: (context, i) => _buildTicketItem(ticket.items[i]),
//                     ),
//             ),
//
//             // Ticket footer with total and payment method
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: theme.colorScheme.surfaceContainerHighest,
//                 borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
//                 border: Border(
//                   top: BorderSide(color: theme.dividerColor, width: 2),
//                 ),
//               ),
//               child: Column(
//                 children: [
//                   // Payment method
//                   if (!ticket.isPaid)
//                     Padding(
//                       padding: const EdgeInsets.only(bottom: 12),
//                       child: _buildPaymentMethodSelector(index, ticket),
//                     ),
//
//                   // Total
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       Text(
//                         'TOTAL',
//                         style: TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.bold,
//                           color: ticket.isPaid ? Colors.green.shade700 : theme.colorScheme.primary,
//                         ),
//                       ),
//                       Text(
//                         currencyFormatter.format(ticket.total),
//                         style: TextStyle(
//                           fontSize: 24,
//                           fontWeight: FontWeight.bold,
//                           color: ticket.isPaid ? Colors.green.shade700 : theme.colorScheme.primary,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildTicketItem(OrderItem item) {
//     final theme = Theme.of(context);
//     final currencyFormatter = ref.watch(currencyFormatterProvider);
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 8),
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         color: theme.colorScheme.surface,
//         borderRadius: BorderRadius.circular(8),
//         border: Border.all(color: theme.dividerColor),
//       ),
//       child: Row(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(8),
//             decoration: BoxDecoration(
//               color: theme.colorScheme.primaryContainer,
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: Text(
//               '${item.quantity}x',
//               style: TextStyle(
//                 fontSize: 16,
//                 fontWeight: FontWeight.bold,
//                 color: theme.colorScheme.onPrimaryContainer,
//               ),
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   item.productName,
//                   style: const TextStyle(
//                     fontSize: 16,
//                     fontWeight: FontWeight.w600,
//                   ),
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                 ),
//                 if (item.components.isNotEmpty)
//                   Text(
//                     item.components.map((c) => c.name).join(', '),
//                     style: TextStyle(
//                       fontSize: 12,
//                       color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
//                     ),
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//               ],
//             ),
//           ),
//           const SizedBox(width: 8),
//           Text(
//             currencyFormatter.format(item.totalPrice * item.quantity),
//             style: const TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildPaymentMethodSelector(int index, TicketData ticket) {
//     final theme = Theme.of(context);
//
//     return Container(
//       decoration: BoxDecoration(
//         border: Border.all(color: theme.dividerColor),
//         borderRadius: BorderRadius.circular(8),
//       ),
//       child: DropdownButtonFormField<TransactionType>(
//         initialValue: ticket.paymentMethod,
//         decoration: const InputDecoration(
//           contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//           border: InputBorder.none,
//         ),
//         items: TransactionType.values.map((method) {
//           return DropdownMenuItem(
//             value: method,
//             child: Row(
//               children: [
//                 Icon(_getPaymentIcon(method), size: 24),
//                 const SizedBox(width: 12),
//                 Text(method.value, style: const TextStyle(fontSize: 16)),
//               ],
//             ),
//           );
//         }).toList(),
//         onChanged: (value) {
//           if (value != null) {
//             _updatePaymentMethod(index, value);
//           }
//         },
//       ),
//     );
//   }
//
//   IconData _getPaymentIcon(TransactionType type) {
//     switch (type) {
//       case TransactionType.cash:
//         return Icons.money_rounded;
//       case TransactionType.card:
//         return Icons.credit_card_rounded;
//       case TransactionType.mobile:
//         return Icons.phone_android_rounded;
//       case TransactionType.other:
//         return Icons.more_horiz_rounded;
//     }
//   }
//
//   Widget _buildPaymentPanel() {
//     final selectedIndex = ref.watch(selectedTicketProvider);
//     final tickets = ref.watch(ticketsProvider);
//     final theme = Theme.of(context);
//
//     if (selectedIndex == null || selectedIndex >= tickets.length) {
//       return Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Icon(
//               Icons.touch_app_rounded,
//               size: 80,
//               color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
//             ),
//             const SizedBox(height: 24),
//             Text(
//               'Select a ticket\nto process payment',
//               textAlign: TextAlign.center,
//               style: TextStyle(
//                 fontSize: 18,
//                 color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
//               ),
//             ),
//           ],
//         ),
//       );
//     }
//
//     final ticket = tickets[selectedIndex];
//
//     if (ticket.isPaid) {
//       return _buildPaidTicketPanel(ticket);
//     }
//
//     return _buildActivePaymentPanel(selectedIndex, ticket);
//   }
//
//   Widget _buildPaidTicketPanel(TicketData ticket) {
//     final theme = Theme.of(context);
//     final currencyFormatter = ref.watch(currencyFormatterProvider);
//
//     return Container(
//       padding: const EdgeInsets.all(24),
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(
//             Icons.check_circle_rounded,
//             size: 100,
//             color: Colors.green.shade600,
//           ),
//           const SizedBox(height: 24),
//           Text(
//             'Ticket Paid',
//             style: TextStyle(
//               fontSize: 28,
//               fontWeight: FontWeight.bold,
//               color: Colors.green.shade700,
//             ),
//           ),
//           const SizedBox(height: 16),
//           Text(
//             'Ticket #${ticket.ticketNum}',
//             style: const TextStyle(fontSize: 20),
//           ),
//           const SizedBox(height: 8),
//           Text(
//             currencyFormatter.format(ticket.total),
//             style: TextStyle(
//               fontSize: 32,
//               fontWeight: FontWeight.bold,
//               color: Colors.green.shade700,
//             ),
//           ),
//           const SizedBox(height: 32),
//           SizedBox(
//             width: double.infinity,
//             child: ElevatedButton.icon(
//               onPressed: () => _printTicket(ticket),
//               icon: const Icon(Icons.print_rounded, size: 28),
//               label: const Text('Print Receipt', style: TextStyle(fontSize: 18)),
//               style: ElevatedButton.styleFrom(
//                 padding: const EdgeInsets.all(20),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildActivePaymentPanel(int ticketIndex, TicketData ticket) {
//     final calcState = ref.watch(calculatorProvider);
//     final theme = Theme.of(context);
//     final currencyFormatter = ref.watch(currencyFormatterProvider);
//
//     return Column(
//       children: [
//         // Ticket summary
//         Container(
//           padding: const EdgeInsets.all(20),
//           decoration: BoxDecoration(
//             color: theme.colorScheme.surfaceContainerHighest,
//             border: Border(bottom: BorderSide(color: theme.dividerColor, width: 2)),
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Payment for Ticket ${ticketIndex + 1}',
//                 style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//               ),
//               const SizedBox(height: 12),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text('Amount Due:', style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
//                   Text(
//                     currencyFormatter.format(ticket.total),
//                     style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//
//         // Calculator mode toggle
//         Padding(
//           padding: const EdgeInsets.all(16),
//           child: SegmentedButton<CalculatorMode>(
//             segments: const [
//               ButtonSegment(
//                 value: CalculatorMode.amount,
//                 label: Text('Amount', style: TextStyle(fontSize: 16)),
//                 icon: Icon(Icons.dialpad_rounded),
//               ),
//               ButtonSegment(
//                 value: CalculatorMode.quick,
//                 label: Text('Quick Pay', style: TextStyle(fontSize: 16)),
//                 icon: Icon(Icons.flash_on_rounded),
//               ),
//             ],
//             selected: {calcState.mode},
//             onSelectionChanged: (Set<CalculatorMode> modes) {
//               _switchCalculatorMode(modes.first);
//             },
//             style: ButtonStyle(
//               padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
//             ),
//           ),
//         ),
//
//         // Calculator display
//         Container(
//           margin: const EdgeInsets.symmetric(horizontal: 16),
//           padding: const EdgeInsets.all(20),
//           decoration: BoxDecoration(
//             color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
//             borderRadius: BorderRadius.circular(12),
//             border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 2),
//           ),
//           child: Column(
//             children: [
//               Text(
//                 'Amount Received',
//                 style: TextStyle(
//                   fontSize: 14,
//                   color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
//                 ),
//               ),
//               const SizedBox(height: 8),
//               Text(
//                 currencyFormatter.format(calcState.enteredAmount),
//                 style: TextStyle(
//                   fontSize: 48,
//                   fontWeight: FontWeight.bold,
//                   color: theme.colorScheme.primary,
//                 ),
//               ),
//               if (calcState.enteredAmount >= ticket.total) ...[
//                 const Divider(height: 24),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Text(
//                       'Change:',
//                       style: TextStyle(fontSize: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
//                     ),
//                     Text(
//                       currencyFormatter.format(calcState.enteredAmount - ticket.total),
//                       style: TextStyle(
//                         fontSize: 28,
//                         fontWeight: FontWeight.bold,
//                         color: Colors.green.shade700,
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ],
//           ),
//         ),
//
//         const SizedBox(height: 16),
//
//         // Calculator or quick buttons
//         Expanded(
//           child: calcState.mode == CalculatorMode.amount
//               ? _buildCalculatorPad()
//               : _buildQuickPayButtons(ticket.total),
//         ),
//
//         // Payment action buttons
//         Padding(
//           padding: const EdgeInsets.all(16),
//           child: Column(
//             children: [
//               SizedBox(
//                 width: double.infinity,
//                 height: 64,
//                 child: ElevatedButton.icon(
//                   onPressed: calcState.enteredAmount >= ticket.total
//                       ? () => _processPayment(ticketIndex, ticket)
//                       : null,
//                   icon: const Icon(Icons.check_circle_rounded, size: 28),
//                   label: const Text('Complete Payment', style: TextStyle(fontSize: 20)),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.green.shade600,
//                     foregroundColor: Colors.white,
//                     disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
//                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 12),
//               SizedBox(
//                 width: double.infinity,
//                 height: 56,
//                 child: OutlinedButton.icon(
//                   onPressed: _clearCalculator,
//                   icon: const Icon(Icons.clear_rounded, size: 24),
//                   label: const Text('Clear', style: TextStyle(fontSize: 18)),
//                   style: OutlinedButton.styleFrom(
//                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
//
//   Widget _buildCalculatorPad() {
//     final theme = Theme.of(context);
//
//     final buttons = [
//       ['7', '8', '9'],
//       ['4', '5', '6'],
//       ['1', '2', '3'],
//       ['0', '.', '⌫'],
//     ];
//
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: GridView.builder(
//         physics: const NeverScrollableScrollPhysics(),
//         gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//           crossAxisCount: 3,
//           childAspectRatio: 1.5,
//           crossAxisSpacing: 12,
//           mainAxisSpacing: 12,
//         ),
//         itemCount: 12,
//         itemBuilder: (context, index) {
//           final row = index ~/ 3;
//           final col = index % 3;
//           final button = buttons[row][col];
//
//           return ElevatedButton(
//             onPressed: () => _onCalculatorButton(button),
//             style: ElevatedButton.styleFrom(
//               backgroundColor: button == '⌫'
//                   ? theme.colorScheme.errorContainer
//                   : theme.colorScheme.secondaryContainer,
//               foregroundColor: button == '⌫'
//                   ? theme.colorScheme.onErrorContainer
//                   : theme.colorScheme.onSecondaryContainer,
//               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//               padding: const EdgeInsets.all(20),
//             ),
//             child: Text(
//               button,
//               style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
//             ),
//           );
//         },
//       ),
//     );
//   }
//
//   Widget _buildQuickPayButtons(double ticketTotal) {
//     final amounts = [
//       ticketTotal.ceil().toDouble(), // Exact amount
//       20.0,
//       50.0,
//       100.0,
//       200.0,
//       500.0,
//     ];
//
//     return ListView.builder(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       itemCount: amounts.length,
//       itemBuilder: (context, index) {
//         final amount = amounts[index];
//         final currencyFormatter = ref.watch(currencyFormatterProvider);
//
//         return Padding(
//           padding: const EdgeInsets.only(bottom: 12),
//           child: SizedBox(
//             height: 70,
//             child: ElevatedButton(
//               onPressed: () => _setQuickAmount(amount),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: index == 0
//                     ? Theme.of(context).colorScheme.primaryContainer
//                     : Theme.of(context).colorScheme.secondaryContainer,
//                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//               ),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     index == 0 ? 'Exact Amount' : currencyFormatter.format(amount),
//                     style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
//                   ),
//                   if (amount >= ticketTotal)
//                     Text(
//                       'Change: ${currencyFormatter.format(amount - ticketTotal)}',
//                       style: TextStyle(
//                         fontSize: 16,
//                         color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
//                       ),
//                     ),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }
//
//   // Event handlers
//   void _selectTicket(int index) {
//     SchedulerBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//       ref.read(selectedTicketProvider.notifier).state = index;
//     });
//   }
//
//   void _addNewTicket() {
//     SchedulerBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//
//       final tickets = ref.read(ticketsProvider);
//       ref.read(ticketsProvider.notifier).state = [
//         ...tickets,
//         TicketData(
//           items: [],
//           discountPercentage: widget.order.discountPercentage,
//         ),
//       ];
//     });
//   }
//
//   void _removeTicket(int index) {
//     SchedulerBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//
//       final tickets = ref.read(ticketsProvider);
//       if (tickets.length <= 1) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Cannot remove the last ticket')),
//         );
//         return;
//       }
//
//       if (tickets[index].isPaid) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Cannot remove paid ticket')),
//         );
//         return;
//       }
//
//       // Move items to first ticket
//       final removedItems = tickets[index].items;
//       final updatedTickets = List<TicketData>.from(tickets);
//       updatedTickets.removeAt(index);
//
//       if (removedItems.isNotEmpty) {
//         updatedTickets[0] = updatedTickets[0].copyWith(
//           items: [...updatedTickets[0].items, ...removedItems],
//         );
//       }
//
//       ref.read(ticketsProvider.notifier).state = updatedTickets;
//     });
//   }
//
//   void _updatePaymentMethod(int index, TransactionType method) {
//     SchedulerBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//
//       final tickets = ref.read(ticketsProvider);
//       final updatedTickets = List<TicketData>.from(tickets);
//       updatedTickets[index] = tickets[index].copyWith(paymentMethod: method);
//       ref.read(ticketsProvider.notifier).state = updatedTickets;
//     });
//   }
//
//   void _switchCalculatorMode(CalculatorMode mode) {
//     SchedulerBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//
//       final calcState = ref.read(calculatorProvider);
//       ref.read(calculatorProvider.notifier).state = calcState.copyWith(mode: mode);
//     });
//   }
//
//   void _onCalculatorButton(String button) {
//     SchedulerBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//
//       final calcState = ref.read(calculatorProvider);
//       String newDisplay = calcState.display;
//
//       if (button == '⌫') {
//         if (newDisplay.length > 1) {
//           newDisplay = newDisplay.substring(0, newDisplay.length - 1);
//         } else {
//           newDisplay = '0';
//         }
//       } else if (button == '.') {
//         if (!newDisplay.contains('.')) {
//           newDisplay += '.';
//         }
//       } else {
//         if (newDisplay == '0') {
//           newDisplay = button;
//         } else {
//           newDisplay += button;
//         }
//       }
//
//       final amount = double.tryParse(newDisplay) ?? 0.0;
//       ref.read(calculatorProvider.notifier).state = CalculatorState(
//         display: newDisplay,
//         enteredAmount: amount,
//         mode: calcState.mode,
//       );
//     });
//   }
//
//   void _setQuickAmount(double amount) {
//     SchedulerBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//
//       final calcState = ref.read(calculatorProvider);
//       ref.read(calculatorProvider.notifier).state = CalculatorState(
//         display: amount.toString(),
//         enteredAmount: amount,
//         mode: calcState.mode,
//       );
//     });
//   }
//
//   void _clearCalculator() {
//     SchedulerBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;
//
//       ref.read(calculatorProvider.notifier).state = CalculatorState();
//     });
//   }
//
//   void _processPayment(int ticketIndex, TicketData ticket) async {
//     final database = ref.read(databaseProvider);
//     final session = ref.read(currentSessionProvider);
//     final printingService = ref.read(printingServiceProvider);
//     final currentUser = ref.read(currentUserProvider);
//
//     try {
//       // Get next ticket number
//       final orderId = widget.order.orderId;
//       final existingTickets = orderId != null
//           ? await (database.select(database.tickets)..where((t) => t.orderId.equals(orderId))).get()
//           : <Ticket>[];
//
//       final maxTicketNum = existingTickets.isEmpty
//           ? 0
//           : existingTickets.map((t) => int.tryParse(t.num) ?? 0).reduce((a, b) => a > b ? a : b);
//
//       final newTicketNum = maxTicketNum + 1;
//       final ticketNumStr = newTicketNum.toString().padLeft(4, '0');
//
//       // Insert ticket
//       final ticketId = await database.into(database.tickets).insert(
//         TicketsCompanion.insert(
//           num: ticketNumStr,
//           orderId: widget.order.orderId ?? 0,
//           paymentMethod: ticket.paymentMethod.value,
//           amount: ticket.total,
//           sessionId: Value(session?.id),
//           isPaid: const Value(true),
//           printCount: const Value(0),
//         ),
//       );
//
//       // Update order items
//       for (final item in ticket.items) {
//         if (item.id != null) {
//           await (database.update(database.orderProducts)..where((tbl) => tbl.id.equals(item.id!))).write(
//             OrderProductsCompanion(
//               ticketId: Value(ticketId),
//               state: const Value('PAID'),
//               updatedAt: Value(DateTime.now()),
//             ),
//           );
//         }
//       }
//
//       // Update UI
//       final updatedItems = ticket.items.map((item) => item.copyWith(ticketId: ticketId, state: 'PAID')).toList();
//
//       SchedulerBinding.instance.addPostFrameCallback((_) {
//         if (!mounted) return;
//
//         final tickets = ref.read(ticketsProvider);
//         final updatedTickets = List<TicketData>.from(tickets);
//         updatedTickets[ticketIndex] = ticket.copyWith(
//           isPaid: true,
//           ticketId: ticketId,
//           ticketNum: ticketNumStr,
//           items: updatedItems,
//         );
//
//         ref.read(ticketsProvider.notifier).state = updatedTickets;
//         ref.read(calculatorProvider.notifier).state = CalculatorState();
//
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Ticket #$ticketNumStr paid successfully!'),
//             backgroundColor: Colors.green.shade700,
//           ),
//         );
//       });
//
//       // Print ticket
//       try {
//         final prefs = ref.read(sharedPreferencesProvider);
//         final businessName = prefs.getString('business_name') ?? 'THANK YOU FOR YOUR PURCHASE';
//
//         final itemsForPrint = ticket.items.map((item) {
//           return {
//             'name': item.productName,
//             'quantity': item.quantity,
//             'price': item.totalPrice,
//             'components': item.components.map((c) => {'name': c.name, 'quantity': c.quantity}).toList(),
//           };
//         }).toList();
//
//         await printingService.printTicketReceipt(
//           ticketId: ticketId,
//           ticketNumber: ticketNumStr,
//           amount: ticket.total,
//           paymentMethod: ticket.paymentMethod.value,
//           createdAt: DateTime.now(),
//           items: itemsForPrint,
//           orderCode: widget.order.orderCode,
//           cashierName: currentUser?.firstName,
//           storeName: businessName,
//         );
//
//         await database.customStatement(
//           'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
//           [ticketId],
//         );
//       } catch (e) {
//         _logger.error('Print failed: $e');
//       }
//     } catch (e) {
//       _logger.error('Payment failed: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Payment failed: $e'), backgroundColor: Colors.red),
//         );
//       }
//     }
//   }
//
//   void _printTicket(TicketData ticket) async {
//     // Similar to _processPayment print logic
//     _logger.info('Reprinting ticket #${ticket.ticketNum}');
//   }
//
//   List<TicketData> get tickets => ref.read(ticketsProvider);
// }
//
//
//
//
