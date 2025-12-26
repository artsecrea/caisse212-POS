// filepath: /home/arecrea/prj/posecrea/lib/presentation/paymen_screen/payment_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:loggecrea/loggecrea.dart';
import 'package:posecrea/providers/database_providers.dart';
import 'package:posecrea/data/database/app_database.dart';
import '../../domain/models/order_models.dart';
import '../../core/enums.dart';

// Model for ticket with its payment method
class TicketData {
  final int? ticketId; // Database ID (null for unpaid tickets)
  final String? ticketNum; // Format: 0001, 0002, etc.
  final List<OrderItem> items;
  final TransactionType paymentMethod;
  final bool isPaid;
  final int printCount;
  final double discountPercentage; // Manual discount percentage from order

  TicketData({
    this.ticketId,
    this.ticketNum,
    required this.items,
    this.paymentMethod = TransactionType.cash,
    this.isPaid = false,
    this.printCount = 0,
    this.discountPercentage = 0.0,
  });

  TicketData copyWith({
    int? ticketId,
    String? ticketNum,
    List<OrderItem>? items,
    TransactionType? paymentMethod,
    bool? isPaid,
    int? printCount,
    double? discountPercentage,
  }) {
    return TicketData(
      ticketId: ticketId ?? this.ticketId,
      ticketNum: ticketNum ?? this.ticketNum,
      items: items ?? this.items,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isPaid: isPaid ?? this.isPaid,
      printCount: printCount ?? this.printCount,
      discountPercentage: discountPercentage ?? this.discountPercentage,
    );
  }

  double get subtotal => items.fold<double>(0.0, (sum, item) => sum + (item.subtotalPerItem * item.quantity));
  double get finalePrice => items.fold<double>(0.0, (sum, item) => sum + (item.totalPrice * item.quantity));
  double get itemDiscount => items.fold<double>(0.0, (sum, item) => sum + item.totalDiscount);
  double get totalTva => items.fold<double>(0.0, (sum, item) => sum + item.totalTva);

  // Calculate manual discount amount based on percentage
  double get manualDiscountAmount {
    final base = (subtotal + totalTva - itemDiscount);
    if (base <= 0 || discountPercentage <= 0) return 0.0;
    return base * (discountPercentage / 100.0);
  }
  // Total discount includes both item-level discounts and manual discount
  double get totalDiscount => itemDiscount + manualDiscountAmount;

  double get total {
    final result = (subtotal + totalTva - itemDiscount) - manualDiscountAmount;
    return result < 0 ? 0.0 : result;
  }
}

// Provider for managing tickets (split orders with payment methods)
final ticketsProvider = StateProvider<List<TicketData>>((ref) => []);

// Provider for calculator state
class CalculatorState {
  final String display;
  final double? enteredAmount;
  final bool isEnteringAmount;

  CalculatorState({
    required this.display,
    this.enteredAmount,
    this.isEnteringAmount = false,
  });

  CalculatorState copyWith({
    String? display,
    double? enteredAmount,
    bool? isEnteringAmount,
  }) {
    return CalculatorState(
      display: display ?? this.display,
      enteredAmount: enteredAmount ?? this.enteredAmount,
      isEnteringAmount: isEnteringAmount ?? this.isEnteringAmount,
    );
  }
}

final calculatorProvider = StateProvider<CalculatorState>((ref) => CalculatorState(display: '0.00'));

class PaymentScreen extends ConsumerStatefulWidget {
  final CurrentOrder order;

  const PaymentScreen({
    super.key,
    required this.order,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {

  final _logger = Logger.instance;
  @override
  void initState() {
    super.initState();
    // Initialize tickets based on ticketNum
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTickets();
    });
  }

  void _initializeTickets() {
    final items = widget.order.items;
    final discountPercentage = widget.order.discountPercentage;

    // Group items by ticketId
    final Map<int?, List<OrderItem>> grouped = {};
    for (var item in items) {
      grouped.putIfAbsent(item.ticketId, () => []).add(item);
    }

    // Create tickets: paid ones first (sorted by ticketId), then unpaid in new ticket
    final tickets = <TicketData>[];
    final sortedKeys = grouped.keys.where((k) => k != null).toList()..sort();

    // Add paid tickets (with their ticket IDs and display numbers)
    for (var ticketId in sortedKeys) {
      tickets.add(TicketData(
        items: grouped[ticketId]!,
        isPaid: true,
        ticketNum: ticketId.toString().padLeft(4, '0'),
        ticketId: ticketId,
        discountPercentage: discountPercentage,
      ));
    }

    // Add unpaid items to a new unpaid ticket (never add to paid tickets)
    if (grouped.containsKey(null) && grouped[null]!.isNotEmpty) {
      // Always create a new ticket for unpaid items
      tickets.add(TicketData(
        items: grouped[null]!,
        discountPercentage: discountPercentage,
      ));
    }

    // If no tickets at all, create one empty
    if (tickets.isEmpty) {
      tickets.add(TicketData(
        items: [],
        discountPercentage: discountPercentage,
      ));
    }

    ref.read(ticketsProvider.notifier).state = tickets;
    ref.read(calculatorProvider.notifier).state = CalculatorState(
      display: widget.order.total.toStringAsFixed(2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.95,
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildTicketsArea(tickets),
                  ),
                  Container(width: 1, color: Colors.grey[300]),
                  Expanded(
                    flex: 2,
                    child: _buildCalculatorArea(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.payment, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          const Text(
            'Payment',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsArea(List<TicketData> tickets) {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tickets (${tickets.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _addNewTicket,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Ticket', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  backgroundColor: Colors.grey[900],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: tickets.isEmpty
                ? Center(
                    child: Text('No items', style: TextStyle(color: Colors.grey[600])),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: tickets.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _buildTicket(index, tickets[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicket(int ticketIndex, TicketData ticket) {
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) {
        // Don't accept items if this ticket is paid
        return !ticket.isPaid;
      },
      onAcceptWithDetails: (details) {
        if (!ticket.isPaid) {
          _moveItemToTicket(details.data, ticketIndex);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isDraggingOver = candidateData.isNotEmpty && !ticket.isPaid;

        return Container(
          width: 280,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: isDraggingOver
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).dividerColor,
              width: isDraggingOver ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              _buildTicketHeader(ticketIndex, ticket),
              Expanded(child: _buildTicketBody(ticketIndex, ticket)),
              _buildTicketFooter(ticketIndex, ticket),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTicketHeader(int ticketIndex, TicketData ticket) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ticket.isPaid ? Colors.green[50] : Colors.grey[100],
        border: Border(bottom: BorderSide(color: ticket.isPaid ? Colors.green[300]! : Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          if (ticket.isPaid) ...[
            Icon(Icons.lock, size: 16, color: Colors.green[700]),
            const SizedBox(width: 6),
          ],
          Text(
            ticket.isPaid ? 'Ticket #${ticket.ticketNum}' : 'Ticket #${ticketIndex + 1}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: ticket.isPaid ? Colors.green[900] : Colors.black87,
            ),
          ),
          const Spacer(),
          Text(
            '${ticket.items.length} items',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          if (ref.watch(ticketsProvider).length > 1 && !ticket.isPaid) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _removeTicket(ticketIndex),
              child: Icon(Icons.close, size: 16, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketBody(int ticketIndex, TicketData ticket) {
    if (ticket.items.isEmpty) {
      return Center(
        child: Text('Drag items here', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: ticket.items.length,
      itemBuilder: (context, itemIndex) {
        return _buildDraggableOrderItem(ticketIndex, itemIndex, ticket.items[itemIndex]);
      },
    );
  }

  Widget _buildDraggableOrderItem(int ticketIndex, int itemIndex, OrderItem item) {
    final isPaidItem = item.ticketId != null;

    // If item is paid, don't make it draggable
    if (isPaidItem) {
      return _buildOrderItemCard(item, isPaid: true);
    }

    return Draggable<Map<String, dynamic>>(
      data: {
        'ticketIndex': ticketIndex,
        'itemIndex': itemIndex,
        'item': item,
      },
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(2),
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
          ),
          child: _buildOrderItemContent(item),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildOrderItemCard(item),
      ),
      child: _buildOrderItemCard(item),
    );
  }

  Widget _buildOrderItemCard(OrderItem item, {bool isPaid = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isPaid ? Colors.green[50] : Theme.of(context).cardColor,
        border: Border.all(color: isPaid ? Colors.green[300]! : Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Stack(
        children: [
          _buildOrderItemContent(item),
          if (isPaid)
            Positioned(
              top: 0,
              right: 0,
              child: Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderItemContent(OrderItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Product Image
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: item.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      width: 45,
                      height: 45,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 45,
                        height: 45,
                        color: Colors.grey[200],
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 45,
                        height: 45,
                        color: Colors.grey[200],
                        child: const Icon(Icons.fastfood, size: 20),
                      ),
                    )
                  : Container(
                      width: 45,
                      height: 45,
                      color: Colors.grey[200],
                      child: const Icon(Icons.fastfood, size: 20),
                    ),
            ),
            const SizedBox(width: 10),
            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.productName} x${item.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${item.finalPrice.toStringAsFixed(2)} each',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            // Price
            Text(
              '\$${item.totalPrice.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
        // Components
        if (item.components.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modifications:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                ...item.components.map((comp) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Text(
                            '• ${comp.name}',
                            style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                          ),
                          if (comp.quantity > 1) ...[
                            const SizedBox(width: 4),
                            Text(
                              'x${comp.quantity}',
                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            ),
                          ],
                          const Spacer(),
                          if (comp.price > 0)
                            Text(
                              '+\$${(comp.price * comp.quantity).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
        // Discount and TVA if present
        if (item.discount > 0 || item.tva > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              if (item.discount > 0) ...[
                Text(
                  'Discount: -\$${item.totalDiscount.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 10, color: Colors.orange[700]),
                ),
                const SizedBox(width: 8),
              ],
              if (item.tva > 0)
                Text(
                  'TVA: +\$${item.totalTva.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 10, color: Colors.blue[700]),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTicketFooter(int ticketIndex, TicketData ticket) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ticket.isPaid ? Colors.green[50] : Colors.grey[50],
        border: Border(top: BorderSide(color: ticket.isPaid ? Colors.green[300]! : Colors.grey[300]!)),
      ),
      child: Column(
        children: [
          // Totals breakdown
          _buildTotalRow('Subtotal:', ticket.subtotal, false),
          if (ticket.itemDiscount > 0) _buildTotalRow('Item Discount:', -ticket.itemDiscount, false, color: Colors.orange[700]),
          if (ticket.discountPercentage > 0) _buildTotalRow('Manual (${ticket.discountPercentage.toStringAsFixed(0)}%):', -ticket.manualDiscountAmount, false, color: Colors.deepOrange[700]),
          if (ticket.totalTva > 0) _buildTotalRow('TVA:', ticket.totalTva, false, color: Colors.blue[700]),
          const Divider(height: 12, thickness: 1),
          _buildTotalRow('Total:', ticket.total, true),
          const SizedBox(height: 10),
          // Payment Method Dropdown
          _buildPaymentMethodDropdown(ticketIndex, ticket),
          const SizedBox(height: 8),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ticket.items.isEmpty ? null : () => _printTicket(ticketIndex),
                  icon: const Icon(Icons.print, size: 14),
                  label: Text(
                    ticket.isPaid ? 'Reprint' : 'Print',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    side: BorderSide(color: Colors.grey[400]!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (ticket.items.isEmpty || ticket.isPaid) ? null : () => _payTicket(ticketIndex),
                  icon: Icon(
                    ticket.isPaid ? Icons.check_circle : Icons.payment,
                    size: 14,
                  ),
                  label: Text(
                    ticket.isPaid ? 'Paid' : 'Pay',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    backgroundColor: ticket.isPaid ? Colors.green[700] : Colors.grey[900],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, bool isBold, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              color: color,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodDropdown(int ticketIndex, TicketData ticket) {
    return DropdownButtonFormField<TransactionType>(
      initialValue: ticket.paymentMethod,
      decoration: InputDecoration(
        labelText: 'Payment Method',
        labelStyle: const TextStyle(fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(2)),
        isDense: true,
        filled: ticket.isPaid,
        fillColor: ticket.isPaid ? Colors.green[50] : null,
      ),
      style: const TextStyle(fontSize: 12, color: Colors.black87),
      items: TransactionType.values.map((method) {
        IconData icon;
        switch (method) {
          case TransactionType.cash:
            icon = Icons.money;
            break;
          case TransactionType.card:
            icon = Icons.credit_card;
            break;
          case TransactionType.mobile:
            icon = Icons.phone_android;
            break;
          case TransactionType.other:
            icon = Icons.more_horiz;
            break;
        }

        return DropdownMenuItem(
          value: method,
          child: Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 8),
              Text(method.value),
            ],
          ),
        );
      }).toList(),
      onChanged: ticket.isPaid ? null : (value) {
        if (value != null) {
          _updateTicketPaymentMethod(ticketIndex, value);
        }
      },
    );
  }

  Widget _buildCalculatorArea(BuildContext context) {
    final calcState = ref.watch(calculatorProvider);
    final tickets = ref.watch(ticketsProvider);
    final totalAmount = tickets.fold<double>(0.0, (sum, ticket) => sum + ticket.total);

    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Total: \$${totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$${calcState.display}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                if (calcState.enteredAmount != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Change: \$${(calcState.enteredAmount! - totalAmount).toStringAsFixed(2)}',
                    style: TextStyle(
                      color: calcState.enteredAmount! >= totalAmount ? Colors.green[400] : Colors.red[400],
                      fontSize: 16,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Calculator Buttons
          Expanded(child: _buildCalculatorButtons()),
          const SizedBox(height: 16),
          // Action Buttons
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _resetCalculator,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reset', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey[600]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _clearCalculator,
                      icon: const Icon(Icons.backspace, size: 16),
                      label: const Text('Clear', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.orange[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmPayment(context),
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: const Text(
                    'Confirm Payment',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatorButtons() {
    final buttons = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['.', '0', '00'],
    ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.8,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        final row = index ~/ 3;
        final col = index % 3;
        final button = buttons[row][col];

        return ElevatedButton(
          onPressed: () => _onCalculatorButtonPressed(button),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            elevation: 0,
          ),
          child: Text(
            button,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
        );
      },
    );
  }

  void _onCalculatorButtonPressed(String button) {
    final currentState = ref.read(calculatorProvider);
    String newDisplay = currentState.display;

    if (button == '.') {
      if (!newDisplay.contains('.')) {
        newDisplay = newDisplay + button;
      }
    } else {
      // Number button
      if (newDisplay == '0.00' || newDisplay == '0' || !currentState.isEnteringAmount) {
        newDisplay = button;
      } else {
        newDisplay = newDisplay + button;
      }
    }

    final enteredAmount = double.tryParse(newDisplay);
    ref.read(calculatorProvider.notifier).state = CalculatorState(
      display: newDisplay,
      enteredAmount: enteredAmount,
      isEnteringAmount: true,
    );
  }

  void _resetCalculator() {
    ref.read(calculatorProvider.notifier).state = CalculatorState(
      display: widget.order.total.toStringAsFixed(2),
    );
  }

  void _clearCalculator() {
    ref.read(calculatorProvider.notifier).state = CalculatorState(display: '0.00');
  }

  void _updateTicketPaymentMethod(int ticketIndex, TransactionType method) {
    final tickets = ref.read(ticketsProvider);
    final updatedTickets = List<TicketData>.from(tickets);
    updatedTickets[ticketIndex] = tickets[ticketIndex].copyWith(paymentMethod: method);
    ref.read(ticketsProvider.notifier).state = updatedTickets;
  }

  void _addNewTicket() {
    final tickets = ref.read(ticketsProvider);
    ref.read(ticketsProvider.notifier).state = [
      ...tickets,
      TicketData(
        items: [],
        discountPercentage: widget.order.discountPercentage,
      )
    ];
  }

  void _removeTicket(int ticketIndex) {
    final tickets = ref.read(ticketsProvider);
    if (tickets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot remove the last ticket')),
      );
      return;
    }

    // Check if ticket contains paid items
    final ticketToPaid = tickets[ticketIndex];
    final hasPaidItems = ticketToPaid.items.any((item) => item.ticketId != null);

    if (hasPaidItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot remove ticket with paid items'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Move items to first ticket
    final removedItems = tickets[ticketIndex].items;
    final updatedTickets = List<TicketData>.from(tickets);
    updatedTickets.removeAt(ticketIndex);

    if (removedItems.isNotEmpty) {
      updatedTickets[0] = updatedTickets[0].copyWith(
        items: [...updatedTickets[0].items, ...removedItems],
      );
    }

    ref.read(ticketsProvider.notifier).state = updatedTickets;
  }

  void _moveItemToTicket(Map<String, dynamic> data, int targetTicketIndex) {
    final sourceTicketIndex = data['ticketIndex'] as int;
    final itemIndex = data['itemIndex'] as int;

    if (sourceTicketIndex == targetTicketIndex) return;

    final tickets = ref.read(ticketsProvider);
    final updatedTickets = List<TicketData>.from(
      tickets.map((ticket) => ticket.copyWith(items: List<OrderItem>.from(ticket.items))),
    );

    final item = updatedTickets[sourceTicketIndex].items[itemIndex];
    updatedTickets[sourceTicketIndex].items.removeAt(itemIndex);
    updatedTickets[targetTicketIndex].items.add(item);

    ref.read(ticketsProvider.notifier).state = updatedTickets;
  }

  void _printTicket(int ticketIndex) {
    // TODO: Implement printing logic
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Printing ticket #${ticketIndex + 1}...')),
    );
  }

  void _payTicket(int ticketIndex) async {
    final tickets = ref.read(ticketsProvider);
    final session = ref.read(currentSessionProvider);
    final ticket = tickets[ticketIndex];
    if (ticket.isPaid) return;
    if (ticket.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in ticket')),
      );
      return;
    }

    // Get database instance
    final database = ref.read(databaseProvider);
    final currentOrder = widget.order;

    try {
      // Get the next ticket number
      final existingTickets = await database.select(database.tickets).get();
      final maxTicketNum = existingTickets.isEmpty
          ? 0
          : existingTickets.map((t) => int.tryParse(t.num) ?? 0).reduce((a, b) => a > b ? a : b);
      final newTicketNum = maxTicketNum + 1;
      final ticketNumStr = newTicketNum.toString().padLeft(4, '0');

      // Insert the ticket into the database
      final ticketId = await database.into(database.tickets).insert(
        TicketsCompanion.insert(
          num: ticketNumStr,
          orderId: currentOrder.orderId ?? 0,
          paymentMethod: ticket.paymentMethod.value,
          amount: ticket.total,
          sessionId: Value(session?.id),
          isPaid: const Value(true),
          printCount: const Value(0),
        ),
      );
      _logger.info('Inserted ticket #$ticketNumStr with ID $ticketId');
      _logger.info('Inserted ticket amount #$ticketNumStr with ID ${ticket.total}');

      // Update all order items in this ticket with the ticket ID and set state to PAID
      for (final item in ticket.items) {
        if (item.id != null) {
          await (database.update(database.orderProducts)
                ..where((tbl) => tbl.id.equals(item.id!)))
              .write(OrderProductsCompanion(
            ticketId: Value(ticketId),
            state: const Value('PAID'),
            updatedAt: Value(DateTime.now()),
          ));
          Logger.instance.info('Updated order item ${item.id} with ticket ID $ticketId and state PAID');
        }
      }

      // Update the ticket in the UI to show it as paid
      final updatedTickets = List<TicketData>.from(tickets);
      updatedTickets[ticketIndex] = ticket.copyWith(
        isPaid: true,
        ticketId: newTicketNum,
        ticketNum: ticketNumStr,
      );

      // Update order items in the ticket to have the ticket ID and state PAID
      final updatedItems = ticket.items.map((item) => item.copyWith(
        ticketId: newTicketNum,
        state: 'PAID',
      )).toList();
      updatedTickets[ticketIndex] = updatedTickets[ticketIndex].copyWith(items: updatedItems);

      ref.read(ticketsProvider.notifier).state = updatedTickets;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ticket #$ticketNumStr paid: \$${ticket.total.toStringAsFixed(2)} via ${ticket.paymentMethod.value}',
          ),
          backgroundColor: Colors.green[700],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing payment: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  void _confirmPayment(BuildContext context) {
    final tickets = ref.read(ticketsProvider);
    final allItems = tickets.expand((ticket) => ticket.items).toList();

    if (allItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items to pay')),
      );
      return;
    }

    final totalAmount = tickets.fold<double>(0.0, (sum, ticket) => sum + ticket.total);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Text(
          'Process payment for ${allItems.length} items across ${tickets.length} ticket(s)?\n\nTotal: \$${totalAmount.toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // pay all the tickets
              for (int i = 0; i < tickets.length; i++) {
                _payTicket(i);
              }
              Navigator.pop(context);
              Navigator.pop(context, true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment processed successfully')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

