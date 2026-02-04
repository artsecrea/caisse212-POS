// filepath: /home/arecrea/prj/posecrea/lib/presentation/paymen_screen/payment_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:loggecrea/loggecrea.dart';
import 'package:posecrea/providers/database_providers.dart';
import 'package:posecrea/data/database/app_database.dart';
import 'package:posecrea/providers/settings_provider.dart';
import 'package:posecrea/providers/sync_manager_provider.dart';
import 'package:posecrea/services/printing_service.dart';
import 'package:posecrea/utils/app_localizations.dart';
import 'package:posecrea/utils/currency_formatter.dart';
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

// Provider for calculator visibility
final calculatorVisibleProvider = StateProvider<bool>((ref) => false);

// Provider for selected ticket index for calculator
final selectedTicketForCalcProvider = StateProvider<int?>((ref) => null);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final calcVisible = ref.watch(calculatorVisibleProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.95,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
              blurRadius: 20,
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
                    flex: calcVisible ? 3 : 1,
                    child: _buildTicketsArea(tickets),
                  ),
                  if (calcVisible)
                    Container(
                      width: 1,
                      color: Theme.of(context).dividerColor,
                    ),
                  if (calcVisible)
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
    final l10n = AppLocalizations.of(context)!;
    final calcVisible = ref.watch(calculatorVisibleProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.payment,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.translate('split_payment'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Calculator toggle button
          IconButton(
            onPressed: () {
              ref.read(calculatorVisibleProvider.notifier).state = !calcVisible;
            },
            icon: Icon(
              calcVisible ? Icons.calculate : Icons.calculate_outlined,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            tooltip: calcVisible ? 'Hide Calculator' : 'Show Calculator',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            tooltip: l10n.translate('close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsArea(List<TicketData> tickets) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${l10n.translate('tickets')} (${tickets.length})',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _addNewTicket,
                icon: const Icon(Icons.add, size: 20),
                label: Text(l10n.translate('new_ticket'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: tickets.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.translate('no_items'),
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: tickets.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 16),
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
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          width: 320,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDraggingOver
                  ? Theme.of(context).colorScheme.primary
                  : ticket.isPaid
                      ? (isDark ? Colors.green[700]! : Colors.green[400]!)
                      : Theme.of(context).dividerColor,
              width: isDraggingOver ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ticket.isPaid
            ? (isDark ? Colors.green[900]!.withValues(alpha: 0.3) : Colors.green[50])
            : Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: ticket.isPaid
                ? (isDark ? Colors.green[700]! : Colors.green[300]!)
                : Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          if (ticket.isPaid) ...[
            Icon(
              Icons.lock,
              size: 16,
              color: isDark ? Colors.green[400] : Colors.green[700],
            ),
            const SizedBox(width: 6),
          ],
          Text(
            ticket.isPaid ? 'Ticket #${ticket.ticketNum}' : 'Ticket #${ticketIndex + 1}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: ticket.isPaid
                  ? (isDark ? Colors.green[300] : Colors.green[900])
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            '${ticket.items.length} items',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          if (ref.watch(ticketsProvider).length > 1 && !ticket.isPaid) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _removeTicket(ticketIndex),
              child: Icon(
                Icons.close,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketBody(int ticketIndex, TicketData ticket) {
    if (ticket.items.isEmpty) {
      return Center(
        child: Text(
          'Drag items here',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            fontSize: 13,
          ),
        ),
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
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        if (!ticket.isPaid) {
          // Show calculator and load ticket total
          ref.read(calculatorVisibleProvider.notifier).state = true;
          ref.read(selectedTicketForCalcProvider.notifier).state = ticketIndex;
          ref.read(calculatorProvider.notifier).state = CalculatorState(
            display: ticket.total.toStringAsFixed(2),
            enteredAmount: ticket.total,
            isEnteringAmount: true,
          );

          // Show feedback
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Calculator ready for Ticket #${ticketIndex + 1}'),
              duration: const Duration(seconds: 1),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ticket.isPaid
              ? (isDark ? Colors.green[900] : Colors.green[50])
              : (isDark ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.surfaceContainerHigh),
          border: Border(
            top: BorderSide(
              color: ticket.isPaid
                  ? (isDark ? Colors.green[700]! : Colors.green[400]!)
                  : Theme.of(context).dividerColor,
              width: 2,
            ),
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: Column(
          children: [
            // Totals breakdown
            _buildTotalRow(
              '${l10n.translate('subtotal')}:',
              ticket.subtotal,
              false,
              currencyFormatter,
            ),
            if (ticket.itemDiscount > 0)
              _buildTotalRow(
                '${l10n.translate('item_discount')}:',
                -ticket.itemDiscount,
                false,
                currencyFormatter,
                color: Colors.orange[700],
              ),
            if (ticket.discountPercentage > 0)
              _buildTotalRow(
                'Manual (${ticket.discountPercentage.toStringAsFixed(0)}%):',
                -ticket.manualDiscountAmount,
                false,
                currencyFormatter,
                color: Colors.deepOrange[700],
              ),
            if (ticket.totalTva > 0)
              _buildTotalRow(
                '${l10n.translate('tax')}:',
                ticket.totalTva,
                false,
                currencyFormatter,
                color: Colors.blue[700],
              ),
            const Divider(height: 16, thickness: 2),
            // Clickable total - highlighted to indicate it's clickable
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ticket.isPaid ? Colors.green[600]! : Colors.blue[600]!,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (ticket.isPaid ? Colors.green : Colors.blue).withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.touch_app,
                        size: 20,
                        color: ticket.isPaid ? Colors.green[700] : Colors.blue[700],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.translate('total')}:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: ticket.isPaid ? Colors.green[700] : Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  Text(
                    currencyFormatter.format(ticket.total),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: ticket.isPaid ? Colors.green[700] : Colors.blue[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Payment Method Dropdown
            _buildPaymentMethodDropdown(ticketIndex, ticket),
            const SizedBox(height: 10),
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ticket.items.isEmpty ? null : () => _printTicket(ticketIndex),
                    icon: const Icon(Icons.print, size: 16),
                    label: Text(
                      ticket.isPaid ? l10n.translate('reprint') : l10n.translate('print'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2),
                      ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, bool isBold, CurrencyFormatter currencyFormatter, {Color? color}) {
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
            currencyFormatter.format(amount),
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
    final l10n = AppLocalizations.of(context)!;
    final calcState = ref.watch(calculatorProvider);
    final selectedTicketIndex = ref.watch(selectedTicketForCalcProvider);
    final tickets = ref.watch(ticketsProvider);
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (selectedTicketIndex == null || selectedTicketIndex >= tickets.length) {
      // Empty state
      return Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app,
                size: 64,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Click a ticket\nto calculate',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final ticket = tickets[selectedTicketIndex];
    final totalAmount = ticket.total;
    final enteredAmount = calcState.enteredAmount ?? 0.0;
    final change = enteredAmount - totalAmount;

    return Column(
      children: [
        // Ticket info header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.receipt,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ticket #${selectedTicketIndex + 1}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Display area
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total:', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  Text(
                    currencyFormatter.format(totalAmount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cash:', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                  Text(
                    currencyFormatter.format(enteredAmount),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: enteredAmount >= totalAmount ? Colors.green : Colors.red,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              if (change > 0) ...[
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Change:', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    Text(
                      currencyFormatter.format(change),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Number pad
        Expanded(child: _buildCalculatorButtons()),

        // Pay button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: enteredAmount >= totalAmount ? () => _payTicket(selectedTicketIndex) : null,
              icon: const Icon(Icons.payment),
              label: Text(l10n.translate('pay_ticket'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalculatorButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final buttons = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['.', '0', 'C'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.5,
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
              backgroundColor: button == 'C'
                  ? Colors.red[isDark ? 700 : 600]
                  : (isDark ? Colors.grey[800] : Colors.grey[300]),
              foregroundColor: button == 'C'
                  ? Colors.white
                  : (isDark ? Colors.white : Colors.black87),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: Text(
              button,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    );
  }

  void _onCalculatorButtonPressed(String button) {
    final currentState = ref.read(calculatorProvider);
    String newDisplay = currentState.display;

    if (button == 'C') {
      // Clear button
      newDisplay = '0.00';
    } else if (button == '.') {
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

  void _printTicket(int ticketIndex) async {
    final tickets = ref.read(ticketsProvider);
    final ticket = tickets[ticketIndex];
    final currentUser = ref.read(currentUserProvider);
    final printingService = ref.read(printingServiceProvider);
    final database = ref.read(databaseProvider);

    if (ticket.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in ticket')),
      );
      return;
    }

    // Build items list for printing
    final itemsForPrint = ticket.items.map((item) => {
      'name': item.productName,
      'quantity': item.quantity,
      'price': item.totalPrice,
    }).toList();

    final ticketNum = ticket.ticketNum ?? '${ticketIndex + 1}'.padLeft(4, '0');

    try {
      final success = await printingService.printTicketReceipt(
        ticketId: ticket.ticketId ?? ticketIndex,
        ticketNumber: ticketNum,
        amount: ticket.total,
        paymentMethod: ticket.paymentMethod.value,
        createdAt: DateTime.now(),
        items: itemsForPrint,
        cashierName: currentUser?.firstName,
        storeName: 'POS Store',
      );

      if (success) {
        // Update print count in database if ticket is saved
        if (ticket.ticketId != null) {
          await database.customStatement(
            'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
            [ticket.ticketId],
          );
        }

        // Update local state
        final updatedTickets = List<TicketData>.from(tickets);
        updatedTickets[ticketIndex] = ticket.copyWith(
          printCount: ticket.printCount + 1,
        );
        ref.read(ticketsProvider.notifier).state = updatedTickets;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ticket #$ticketNum printed successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to print. Check printer connection.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _payTicket(int ticketIndex) async {
    final tickets = ref.read(ticketsProvider);
    final session = ref.read(currentSessionProvider);
    final ticket = tickets[ticketIndex];
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);

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
// Dart
      final orderId = currentOrder.orderId;
      final existingTickets = orderId != null
          ? await (database.select(database.tickets)
        ..where((t) => t.orderId.equals(orderId)))
          .get()
          : <Ticket>[];

      final maxTicketNum = existingTickets.isEmpty
          ? 0
          : existingTickets
          .map((t) => int.tryParse(t.num) ?? 0)
          .reduce((a, b) => a > b ? a : b);

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
        ticketId: ticketId,
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

      // Print the ticket after successful payment
      try {
        final itemsForPrint = ticket.items.map((item) => {
          'name': item.productName,
          'quantity': item.quantity,
          'price': item.totalPrice,
        }).toList();

        await printingService.printTicketReceipt(
          ticketId: ticketId,
          ticketNumber: ticketNumStr,
          amount: ticket.total,
          paymentMethod: ticket.paymentMethod.value,
          createdAt: DateTime.now(),
          items: itemsForPrint,
          cashierName: currentUser?.firstName,
          storeName: 'POS Store',
        );

        // Update print count
        await database.customStatement(
          'UPDATE tickets SET print_count = 1 WHERE id = ?',
          [ticketId],
        );
      } catch (printError) {
        _logger.error('Failed to print ticket: $printError');
        // Don't fail the payment if printing fails
      }

      // Note: We do NOT automatically change order status to COMPLETED after payment
      // The order status should be managed separately through order management screen

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing payment: $e'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  void _confirmPayment(BuildContext context) async {
    final tickets = ref.read(ticketsProvider);
    final allItems = tickets.expand((ticket) => ticket.items).toList();
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);

    if (allItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items to pay')),
      );
      return;
    }

    final totalAmount = tickets.fold<double>(0.0, (sum, ticket) => sum + ticket.total);

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Text(
          'Process payment for ${allItems.length} items across ${tickets.length} ticket(s)?\n\nTotal: \$${totalAmount.toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    // Pay all the tickets
    for (int i = 0; i < tickets.length; i++) {
      await Future(() => _payTicket(i));
    }

    // Print order receipt and KDS ticket
    try {
      // Print receipt
      await printingService.printOrderReceipt(
        order: widget.order,
        cashierName: currentUser?.firstName,
        storeName: 'POS Store',
      );

      // Print KDS ticket if enabled
      if (printingService.config.kdsEnabled) {
        await printingService.printKdsTicket(
          order: widget.order,
          cashierName: currentUser?.firstName,
        );
      }
    } catch (e) {
      _logger.error('Failed to print after payment: $e');
    }

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment processed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

