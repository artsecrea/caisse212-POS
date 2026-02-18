import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:loggecrea/loggecrea.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/utils/app_localizations.dart';
import 'package:caisse212/utils/currency_formatter.dart';
import '../../domain/models/order_models.dart';
import '../../core/enums.dart';
import '../../utils/app_localizations.dart';

/// Calculator mode enum
enum CalculatorMode {
  amount, // Direct amount entry
  quick,  // Quick preset buttons (10, 20, 50, 100)
}

/// Ticket data model for split payments
class TicketData {
  final int? ticketId;
  final String? ticketNum;
  final List<OrderItem> items;
  final TransactionType paymentMethod;
  final bool isPaid;
  final int printCount;
  final double discountPercentage;

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
  double get itemDiscount => items.fold<double>(0.0, (sum, item) => sum + item.totalDiscount);
  double get totalTva => items.fold<double>(0.0, (sum, item) => sum + item.totalTva);

  double get manualDiscountAmount {
    final base = (subtotal + totalTva - itemDiscount);
    if (base <= 0 || discountPercentage <= 0) return 0.0;
    return base * (discountPercentage / 100.0);
  }

  double get total {
    final result = (subtotal + totalTva - itemDiscount) - manualDiscountAmount;
    return result < 0 ? 0.0 : result;
  }
}

/// Calculator state
class CalculatorState {
  final String display;
  final double enteredAmount;
  final CalculatorMode mode;

  CalculatorState({
    this.display = '0',
    this.enteredAmount = 0.0,
    this.mode = CalculatorMode.amount,
  });

  CalculatorState copyWith({
    String? display,
    double? enteredAmount,
    CalculatorMode? mode,
  }) {
    return CalculatorState(
      display: display ?? this.display,
      enteredAmount: enteredAmount ?? this.enteredAmount,
      mode: mode ?? this.mode,
    );
  }
}

// Providers
final ticketsProvider = StateProvider<List<TicketData>>((ref) => []);
final calculatorProvider = StateProvider<CalculatorState>((ref) => CalculatorState());
final selectedTicketProvider = StateProvider<int?>((ref) => null);

/// Modern Payment Screen - Rebuilt for touch screens
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTickets();
    });
  }

  void _initializeTickets() {
    final items = widget.order.items;

    // Group items by ticketId
    final Map<int?, List<OrderItem>> grouped = {};
    for (var item in items) {
      grouped.putIfAbsent(item.ticketId, () => []).add(item);
    }

    final List<TicketData> tickets = [];

    // Create tickets for paid items
    grouped.forEach((ticketId, ticketItems) {
      if (ticketId != null) {
        // Generate ticket number from ID and get payment method from order data
        final ticketNumStr = ticketId.toString().padLeft(4, '0');

        tickets.add(TicketData(
          ticketId: ticketId,
          ticketNum: ticketNumStr,
          items: ticketItems,
          paymentMethod: TransactionType.cash, // Will be overridden by actual payment method if available
          isPaid: true,
          discountPercentage: widget.order.discountPercentage,
        ));
      }
    });

    // Create ticket for unpaid items
    final unpaidItems = grouped[null] ?? [];
    if (unpaidItems.isNotEmpty) {
      tickets.add(TicketData(
        items: unpaidItems,
        discountPercentage: widget.order.discountPercentage,
      ));
    }

    // Ensure at least one ticket exists
    if (tickets.isEmpty) {
      tickets.add(TicketData(
        items: [],
        discountPercentage: widget.order.discountPercentage,
      ));
    }

    ref.read(ticketsProvider.notifier).state = tickets;
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.98,
          maxHeight: MediaQuery.of(context).size.height * 0.98,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                children: [
                  // Tickets area - 60% width
                  Expanded(
                    flex: 6,
                    child: _buildTicketsArea(tickets),
                  ),

                  // Divider
                  Container(
                    width: 1,
                    color: theme.dividerColor,
                  ),

                  // Payment calculator - 40% width
                  Expanded(
                    flex: 4,
                    child: _buildPaymentPanel(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.payments_rounded,
            size: 28,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('split_payment'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  'Order: ${widget.order.orderCode}',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close_rounded,
              size: 26,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            tooltip: l10n.translate('close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsArea(List<TicketData> tickets) {
    final hasUnpaidTicketsWithItems = tickets.any((t) => !t.isPaid && t.items.isNotEmpty);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        // Tickets header with buttons
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                '${l10n.translate('tickets')} (${tickets.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Pay All button - always visible
              ElevatedButton.icon(
                onPressed: hasUnpaidTicketsWithItems ? _payAllTickets : null,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(l10n.translate('pay_all'), style: const TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _addNewTicket,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.translate('new_ticket'), style: const TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
        ),

        // Tickets grid
        Expanded(
          child: tickets.isEmpty
              ? Center(child: Text(l10n.translate('no_tickets')))
              : GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 450,
              childAspectRatio: 0.75,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: tickets.length,
            itemBuilder: (context, index) => _buildTicketCard(index, tickets[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildTicketCard(int index, TicketData ticket) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedIndex = ref.watch(selectedTicketProvider);
    final isSelected = selectedIndex == index;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final tickets = ref.watch(ticketsProvider);
    final l10n = AppLocalizations.of(context)!;

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) => !ticket.isPaid,
      onAcceptWithDetails: (details) {
        if (!ticket.isPaid) {
          _moveItemToTicket(details.data, index);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isDraggingOver = candidateData.isNotEmpty && !ticket.isPaid;

        return GestureDetector(
          onTap: () => _selectTicket(index),
          child: Container(
            decoration: BoxDecoration(
              color: ticket.isPaid
                  ? (isDark ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.green.shade50)
                  : (isDraggingOver
                      ? theme.colorScheme.primary.withValues(alpha: 0.1)
                      : (isSelected ? theme.colorScheme.primaryContainer : theme.cardColor)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDraggingOver
                    ? theme.colorScheme.primary
                    : (isSelected
                        ? theme.colorScheme.primary
                        : (ticket.isPaid ? Colors.green : theme.dividerColor)),
                width: isDraggingOver ? 3 : (isSelected ? 2 : 1),
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ticket header
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ticket.isPaid
                        ? (isDark ? Colors.green.shade800 : Colors.green.shade100)
                        : (isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.1)
                            : theme.colorScheme.surfaceContainerHighest),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            ticket.isPaid ? Icons.check_circle_rounded : Icons.receipt_rounded,
                            size: 20,
                            color: ticket.isPaid ? Colors.green.shade700 : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ticket.ticketNum != null
                                      ? '${l10n.translate('ticket')} #${ticket.ticketNum}'
                                      : '${l10n.translate('ticket')} ${index + 1}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: ticket.isPaid ? Colors.green.shade700 : null,
                                  ),
                                ),
                                Text(
                                  '${ticket.items.length} ${l10n.translate('items')}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!ticket.isPaid && tickets.length > 1)
                            IconButton(
                              onPressed: () => _removeTicket(index),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: l10n.translate('remove_ticket'),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                        ],
                      ),
                      // Pay button for unpaid tickets
                      if (!ticket.isPaid && ticket.items.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _payTicket(index, ticket),
                            icon: const Icon(Icons.payment_rounded, size: 18),
                            label: Text('${l10n.translate('pay')} ${currencyFormatter.format(ticket.total)}', style: const TextStyle(fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Ticket items
                Expanded(
                  child: ticket.items.isEmpty
                      ? Center(
                          child: Text(
                            l10n.translate('drag_items_here'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(6),
                          itemCount: ticket.items.length,
                          itemBuilder: (context, i) => _buildDraggableTicketItem(index, i, ticket.items[i], ticket.isPaid),
                        ),
                ),

                // Ticket footer with total and payment method
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                    border: Border(
                      top: BorderSide(color: theme.dividerColor, width: 1),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Payment method
                      if (!ticket.isPaid)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _buildPaymentMethodSelector(index, ticket),
                        ),

                      // Total
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TOTAL',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: ticket.isPaid ? Colors.green.shade700 : theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            currencyFormatter.format(ticket.total),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: ticket.isPaid ? Colors.green.shade700 : theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDraggableTicketItem(int ticketIndex, int itemIndex, OrderItem item, bool isPaid) {
    if (isPaid) {
      return _buildTicketItem(item);
    }

    return Draggable<Map<String, dynamic>>(
      data: {
        'ticketIndex': ticketIndex,
        'itemIndex': itemIndex,
        'item': item,
      },
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
          ),
          child: _buildTicketItemContent(item),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildTicketItem(item),
      ),
      child: _buildTicketItem(item),
    );
  }

  Widget _buildTicketItemContent(OrderItem item) {
    final theme = Theme.of(context);
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Row(
      children: [
        InkWell(
          onTap: item.quantity > 1 ? () => _showDivideQuantityDialog(item) : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
              border: item.quantity > 1
                  ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 1.5)
                  : null,
            ),
            child: Text(
              '${item.quantity}x',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.components.isNotEmpty)
                Text(
                  item.components.map((c) => c.name).join(', '),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          currencyFormatter.format(item.totalPrice * item.quantity),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTicketItem(OrderItem item) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor),
      ),
      child: _buildTicketItemContent(item),
    );
  }

  Widget _buildPaymentMethodSelector(int index, TicketData ticket) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonFormField<TransactionType>(
        initialValue: ticket.paymentMethod,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          border: InputBorder.none,
        ),
        items: TransactionType.values.map((method) {
          return DropdownMenuItem(
            value: method,
            child: Row(
              children: [
                Icon(_getPaymentIcon(method), size: 20),
                const SizedBox(width: 8),
                Text(method.value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            _updatePaymentMethod(index, value);
          }
        },
      ),
    );
  }

  IconData _getPaymentIcon(TransactionType type) {
    switch (type) {
      case TransactionType.cash:
        return Icons.money_rounded;
      case TransactionType.card:
        return Icons.credit_card_rounded;
      case TransactionType.mobile:
        return Icons.phone_android_rounded;
      case TransactionType.other:
        return Icons.more_horiz_rounded;
    }
  }

  Widget _buildPaymentPanel() {
    final selectedIndex = ref.watch(selectedTicketProvider);
    final tickets = ref.watch(ticketsProvider);
    final theme = Theme.of(context);

    if (selectedIndex == null || selectedIndex >= tickets.length) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: 80,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 24),
            Text(
              'Select a ticket\nto process payment',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    final ticket = tickets[selectedIndex];

    if (ticket.isPaid) {
      return _buildPaidTicketPanel(ticket);
    }

    return _buildActivePaymentPanel(selectedIndex, ticket);
  }

  Widget _buildPaidTicketPanel(TicketData ticket) {
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 100,
            color: Colors.green.shade600,
          ),
          const SizedBox(height: 24),
          Text(
            'Ticket Paid',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Ticket #${ticket.ticketNum}',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            currencyFormatter.format(ticket.total),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _printTicket(ticket),
              icon: const Icon(Icons.print_rounded, size: 28),
              label: Text(AppLocalizations.of(context)!.translate('print_receipt'), style: const TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePaymentPanel(int ticketIndex, TicketData ticket) {
    final calcState = ref.watch(calculatorProvider);
    final theme = Theme.of(context);
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        // Ticket summary - Compact
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${l10n.translate('ticket')} ${ticketIndex + 1}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                currencyFormatter.format(ticket.total),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
              ),
            ],
          ),
        ),

        // Calculator mode toggle - Compact
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<CalculatorMode>(
            segments: [
              ButtonSegment(
                value: CalculatorMode.amount,
                label: Text(l10n.translate('amount'), style: const TextStyle(fontSize: 14)),
                icon: const Icon(Icons.dialpad_rounded, size: 20),
              ),
              ButtonSegment(
                value: CalculatorMode.quick,
                label: Text(l10n.translate('quick'), style: const TextStyle(fontSize: 14)),
                icon: const Icon(Icons.flash_on_rounded, size: 20),
              ),
            ],
            selected: {calcState.mode},
            onSelectionChanged: (Set<CalculatorMode> modes) {
              _switchCalculatorMode(modes.first);
            },
          ),
        ),

        // Calculator display - Compact
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(
                currencyFormatter.format(calcState.enteredAmount),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: calcState.enteredAmount >= ticket.total ? Colors.green.shade700 : theme.colorScheme.primary,
                ),
              ),
              if (calcState.enteredAmount >= ticket.total) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${l10n.translate('change')}: ',
                      style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                    Text(
                      currencyFormatter.format(calcState.enteredAmount - ticket.total),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Calculator or quick buttons - Use Expanded to fill space
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: calcState.mode == CalculatorMode.amount
                ? _buildCalculatorPad()
                : _buildQuickPayButtons(ticket.total),
          ),
        ),

        // Payment action buttons - Always visible at bottom
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: calcState.enteredAmount >= ticket.total
                      ? () => _processPayment(ticketIndex, ticket)
                      : null,
                  icon: const Icon(Icons.check_circle_rounded, size: 24),
                  label: Text(l10n.translate('complete_payment'), style: const TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _clearCalculator,
                  icon: const Icon(Icons.clear_rounded, size: 20),
                  label: Text(l10n.translate('clear'), style: const TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCalculatorPad() {
    final theme = Theme.of(context);

    final buttons = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['0', '.', '⌫'],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: buttons.map((row) {
            return Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: row.map((button) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: ElevatedButton(
                        onPressed: () => _onCalculatorButton(button),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: button == '⌫'
                              ? theme.colorScheme.errorContainer
                              : theme.colorScheme.secondaryContainer,
                          foregroundColor: button == '⌫'
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onSecondaryContainer,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.zero,
                          elevation: 2,
                        ),
                        child: Text(
                          button,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          }).toList(),
        );
      }
    );
  }

  Widget _buildQuickPayButtons(double ticketTotal) {
    final amounts = [
      ticketTotal.ceil().toDouble(), // Exact amount
      20.0,
      50.0,
      100.0,
      200.0,
      500.0,
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: amounts.length,
      itemBuilder: (context, index) {
        final amount = amounts[index];
        final currencyFormatter = ref.watch(currencyFormatterProvider);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: 60,
            child: ElevatedButton(
              onPressed: () => _setQuickAmount(amount),
              style: ElevatedButton.styleFrom(
                backgroundColor: index == 0
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.secondaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    index == 0 ? 'Exact Amount' : currencyFormatter.format(amount),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (amount >= ticketTotal)
                    Text(
                      'Change: ${currencyFormatter.format(amount - ticketTotal)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Event handlers
  void _selectTicket(int index) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectedTicketProvider.notifier).state = index;
    });
  }

  void _addNewTicket() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tickets = ref.read(ticketsProvider);
      ref.read(ticketsProvider.notifier).state = [
        ...tickets,
        TicketData(
          items: [],
          discountPercentage: widget.order.discountPercentage,
        ),
      ];
    });
  }

  void _removeTicket(int index) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tickets = ref.read(ticketsProvider);
      final l10n = AppLocalizations.of(context)!;

      if (tickets.length <= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('cannot_remove_last_ticket'))),
        );
        return;
      }

      if (tickets[index].isPaid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('cannot_remove_paid_ticket'))),
        );
        return;
      }

      // Move items to first ticket
      final removedItems = tickets[index].items;
      final updatedTickets = List<TicketData>.from(tickets);
      updatedTickets.removeAt(index);

      if (removedItems.isNotEmpty) {
        updatedTickets[0] = updatedTickets[0].copyWith(
          items: [...updatedTickets[0].items, ...removedItems],
        );
      }

      ref.read(ticketsProvider.notifier).state = updatedTickets;
    });
  }

  void _updatePaymentMethod(int index, TransactionType method) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tickets = ref.read(ticketsProvider);
      final updatedTickets = List<TicketData>.from(tickets);
      updatedTickets[index] = tickets[index].copyWith(paymentMethod: method);
      ref.read(ticketsProvider.notifier).state = updatedTickets;
    });
  }

  void _moveItemToTicket(Map<String, dynamic> data, int targetTicketIndex) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

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
    });
  }

  void _switchCalculatorMode(CalculatorMode mode) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final calcState = ref.read(calculatorProvider);
      ref.read(calculatorProvider.notifier).state = calcState.copyWith(mode: mode);
    });
  }

  void _onCalculatorButton(String button) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final calcState = ref.read(calculatorProvider);
      String newDisplay = calcState.display;

      if (button == '⌫') {
        if (newDisplay.length > 1) {
          newDisplay = newDisplay.substring(0, newDisplay.length - 1);
        } else {
          newDisplay = '0';
        }
      } else if (button == '.') {
        if (!newDisplay.contains('.')) {
          newDisplay += '.';
        }
      } else {
        if (newDisplay == '0') {
          newDisplay = button;
        } else {
          newDisplay += button;
        }
      }

      final amount = double.tryParse(newDisplay) ?? 0.0;
      ref.read(calculatorProvider.notifier).state = CalculatorState(
        display: newDisplay,
        enteredAmount: amount,
        mode: calcState.mode,
      );
    });
  }

  void _setQuickAmount(double amount) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final calcState = ref.read(calculatorProvider);
      ref.read(calculatorProvider.notifier).state = CalculatorState(
        display: amount.toString(),
        enteredAmount: amount,
        mode: calcState.mode,
      );
    });
  }

  void _clearCalculator() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      ref.read(calculatorProvider.notifier).state = CalculatorState();
    });
  }

  Future<void> _processPayment(int ticketIndex, TicketData ticket) async {
    final database = ref.read(databaseProvider);
    final session = ref.read(currentSessionProvider);
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);

    try {
      // Get next ticket number
      final orderId = widget.order.orderId;
      final existingTickets = orderId != null
          ? await (database.select(database.tickets)..where((t) => t.orderId.equals(orderId))).get()
          : <Ticket>[];

      final maxTicketNum = existingTickets.isEmpty
          ? 0
          : existingTickets.map((t) => int.tryParse(t.num) ?? 0).reduce((a, b) => a > b ? a : b);

      final newTicketNum = maxTicketNum + 1;
      final ticketNumStr = newTicketNum.toString().padLeft(4, '0');

      // Insert ticket
      final ticketId = await database.into(database.tickets).insert(
        TicketsCompanion.insert(
          num: ticketNumStr,
          orderId: widget.order.orderId ?? 0,
          paymentMethod: ticket.paymentMethod.value,
          amount: ticket.total,
          sessionId: Value(session?.id),
          isPaid: const Value(true),
          printCount: const Value(0),
        ),
      );

      // Update order items
      for (final item in ticket.items) {
        if (item.id != null) {
          await (database.update(database.orderProducts)..where((tbl) => tbl.id.equals(item.id!))).write(
            OrderProductsCompanion(
              ticketId: Value(ticketId),
              state: const Value('PAID'),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }

      // Update UI
      final updatedItems = ticket.items.map((item) => item.copyWith(ticketId: ticketId, state: 'PAID')).toList();

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final tickets = ref.read(ticketsProvider);
        final updatedTickets = List<TicketData>.from(tickets);
        updatedTickets[ticketIndex] = ticket.copyWith(
          isPaid: true,
          ticketId: ticketId,
          ticketNum: ticketNumStr,
          items: updatedItems,
        );

        ref.read(ticketsProvider.notifier).state = updatedTickets;
        ref.read(calculatorProvider.notifier).state = CalculatorState();

        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('ticket_paid_successfully').replaceAll('{0}', ticketNumStr)),
            backgroundColor: Colors.green.shade700,
          ),
        );
      });

      // Print ticket
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        final businessName = prefs.getString('business_name') ?? 'THANK YOU FOR YOUR PURCHASE';

        final itemsForPrint = ticket.items.map((item) {
          return {
            'name': item.productName,
            'quantity': item.quantity,
            'price': item.totalPrice,
            'components': item.components.map((c) => {'name': c.name, 'quantity': c.quantity}).toList(),
          };
        }).toList();

        await printingService.printTicketReceipt(
          ticketId: ticketId,
          ticketNumber: ticketNumStr,
          amount: ticket.total,
          paymentMethod: ticket.paymentMethod.value,
          createdAt: DateTime.now(),
          items: itemsForPrint,
          orderCode: widget.order.orderCode,
          cashierName: currentUser?.firstName,
          storeName: businessName,
        );

        await database.customStatement(
          'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
          [ticketId],
        );
      } catch (e) {
        _logger.error('Print failed: $e');
      }
    } catch (e) {
      _logger.error('Payment failed: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('payment_failed').replaceAll('{0}', e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Pay a single ticket directly
  Future<void> _payTicket(int ticketIndex, TicketData ticket) async {
    await _processPayment(ticketIndex, ticket);
  }

  /// Pay all unpaid tickets
  Future<void> _payAllTickets() async {
    final tickets = ref.read(ticketsProvider);

    for (int i = 0; i < tickets.length; i++) {
      if (!tickets[i].isPaid && tickets[i].items.isNotEmpty) {
        // Re-read tickets state as it might have changed
        final currentTickets = ref.read(ticketsProvider);
        if (i < currentTickets.length && !currentTickets[i].isPaid) {
          await _processPayment(i, currentTickets[i]);
        }
      }
    }

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('all_tickets_paid_successfully')),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showDivideQuantityDialog(OrderItem item) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('divide_quantity')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.productName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '${l10n.translate('current_quantity')}: ${item.quantity}',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.translate('split_into_quantities'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(item.quantity - 1, (index) {
                final split1 = index + 1;
                final split2 = item.quantity - split1;
                return ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _divideItemQuantity(item, split1, split2);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: Text('$split1 + $split2', style: const TextStyle(fontSize: 16)),
                );
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel')),
          ),
        ],
      ),
    );
  }

  void _divideItemQuantity(OrderItem item, int quantity1, int quantity2) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tickets = ref.read(ticketsProvider);

      // Find which ticket contains this item
      int ticketIndex = -1;
      int itemIndex = -1;

      for (int i = 0; i < tickets.length; i++) {
        final index = tickets[i].items.indexWhere((it) => it.id == item.id);
        if (index != -1) {
          ticketIndex = i;
          itemIndex = index;
          break;
        }
      }

      if (ticketIndex == -1) return;

      final updatedTickets = List<TicketData>.from(
        tickets.map((ticket) => ticket.copyWith(items: List<OrderItem>.from(ticket.items))),
      );

      // Update existing item with first quantity
      updatedTickets[ticketIndex].items[itemIndex] = item.copyWith(quantity: quantity1);

      // Add new item with second quantity
      final newItem = item.copyWith(quantity: quantity2);
      updatedTickets[ticketIndex].items.insert(itemIndex + 1, newItem);

      ref.read(ticketsProvider.notifier).state = updatedTickets;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.productName} ${AppLocalizations.of(context)!.translate('divided_into')} $quantity1 + $quantity2'),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  void _printTicket(TicketData ticket) async {
    // Similar to _processPayment print logic
    _logger.info('Reprinting ticket #${ticket.ticketNum}');
  }

  List<TicketData> get tickets => ref.read(ticketsProvider);
}




