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
import '../../providers/order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_manager_provider.dart';
import '../../providers/network_provider.dart';

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

// Providers — autoDispose so state resets when dialog closes
final ticketsProvider = StateProvider.autoDispose<List<TicketData>>((ref) => []);
final calculatorProvider = StateProvider.autoDispose<CalculatorState>((ref) => CalculatorState());
final selectedTicketProvider = StateProvider.autoDispose<int?>((ref) => null);

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
      final defaultMethod = TransactionType.fromString(
        ref.read(settingsProvider).defaultPaymentMethod,
      );
      tickets.add(TicketData(
        items: unpaidItems,
        paymentMethod: defaultMethod,
        discountPercentage: widget.order.discountPercentage,
      ));
    }

    // Ensure at least one ticket exists
    if (tickets.isEmpty) {
      final defaultMethod = TransactionType.fromString(
        ref.read(settingsProvider).defaultPaymentMethod,
      );
      tickets.add(TicketData(
        items: [],
        paymentMethod: defaultMethod,
        discountPercentage: widget.order.discountPercentage,
      ));
    }

    ref.read(ticketsProvider.notifier).state = tickets;
    ref.read(calculatorProvider.notifier).state = CalculatorState();

    // Auto-select the single unpaid ticket if there is exactly one
    final unpaidIndices = [
      for (int i = 0; i < tickets.length; i++)
        if (!tickets[i].isPaid) i,
    ];
    ref.read(selectedTicketProvider.notifier).state =
        unpaidIndices.length == 1 ? unpaidIndices.first : null;
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
        child: Stack(
          children: [
            Column(
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
            // Printing status overlay
            StreamBuilder<String?>(
              stream: ref.read(printingServiceProvider).printingStatusStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data == null) {
                  return const SizedBox.shrink();
                }
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(strokeWidth: 4),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              snapshot.data!,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
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
    final hasEmptyUnpaidTicket = tickets.any((t) => !t.isPaid && t.items.isEmpty);
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
              Tooltip(
                message: hasEmptyUnpaidTicket ? l10n.translate('fill_empty_ticket_first') : '',
                child: ElevatedButton.icon(
                  onPressed: hasEmptyUnpaidTicket ? null : _addNewTicket,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.translate('new_ticket'), style: const TextStyle(fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // UX hint bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              Icon(Icons.touch_app_rounded, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('Tap qty>1 to split · Long-press for custom split · Drag to merge / move',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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

    final theme = Theme.of(context);

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) {
        final draggedItem = details.data['item'] as OrderItem;
        // Accept if same product (for merging) - even from same ticket
        return draggedItem.productId == item.productId &&
            draggedItem.variantId == item.variantId &&
            !(details.data['ticketIndex'] == ticketIndex && details.data['itemIndex'] == itemIndex);
      },
      onAcceptWithDetails: (details) {
        _mergeItems(details.data, ticketIndex, itemIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isMergeTarget = candidateData.isNotEmpty;

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
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
              child: _buildTicketItemContent(item),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildTicketItem(item),
          ),
          child: GestureDetector(
            onTap: item.quantity > 1 ? () => _quickSplitOne(ticketIndex, itemIndex, item) : null,
            onLongPress: item.quantity > 1 ? () => _showCustomDivideDialog(item, ticketIndex, itemIndex) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMergeTarget
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isMergeTarget
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: isMergeTarget ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Merge indicator overlay when dragging over
                  if (isMergeTarget) ...[
                    Icon(Icons.merge_rounded, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                  ],
                  Expanded(child: _buildTicketItemContent(item)),
                  // Split hint for items with qty > 1
                  if (item.quantity > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.call_split_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
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

  Widget _buildTicketItemContent(OrderItem item) {
    final theme = Theme.of(context);
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Row(
      children: [
        Container(
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
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.displayName,
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
              if (item.note != null && item.note!.isNotEmpty)
                Text(
                  '📝 ${item.note}',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.amber.shade800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          currencyFormatter.format(item.totalPrice),
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

    if (ticket.items.isEmpty) {
      return _buildEmptyTicketPanel();
    }

    return _buildActivePaymentPanel(selectedIndex, ticket);
  }

  Widget _buildEmptyTicketPanel() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded, size: 80, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text(
            l10n.translate('ticket_has_no_items'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
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
                  onPressed: ticket.items.isNotEmpty && calcState.enteredAmount >= ticket.total
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
      final l10n = AppLocalizations.of(context)!;

      // Block if any unpaid ticket is already empty
      if (tickets.any((t) => !t.isPaid && t.items.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('fill_empty_ticket_first')),
            backgroundColor: Colors.orange.shade700,
          ),
        );
        return;
      }

      final defaultMethod = TransactionType.fromString(
        ref.read(settingsProvider).defaultPaymentMethod,
      );
      final newTickets = [
        ...tickets,
        TicketData(
          items: [],
          paymentMethod: defaultMethod,
          discountPercentage: widget.order.discountPercentage,
        ),
      ];
      ref.read(ticketsProvider.notifier).state = newTickets;
      // Auto-select the new empty ticket so user knows to drag items into it
      ref.read(selectedTicketProvider.notifier).state = newTickets.length - 1;
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

      final removedItems = tickets[index].items;
      final updatedTickets = List<TicketData>.from(tickets);
      updatedTickets.removeAt(index);

      // Move orphaned items to the first unpaid ticket (never a paid ticket)
      if (removedItems.isNotEmpty) {
        final destIdx = updatedTickets.indexWhere((t) => !t.isPaid);
        if (destIdx != -1) {
          updatedTickets[destIdx] = updatedTickets[destIdx].copyWith(
            items: [...updatedTickets[destIdx].items, ...removedItems],
          );
        }
      }

      // Reset selected index if it pointed at removed or out-of-bounds ticket
      final selected = ref.read(selectedTicketProvider);
      if (selected != null && selected >= updatedTickets.length) {
        ref.read(selectedTicketProvider.notifier).state = null;
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

  Future<void> _moveItemToTicket(Map<String, dynamic> data, int targetTicketIndex) async {
    final sourceTicketIndex = data['ticketIndex'] as int;
    final itemIndex = data['itemIndex'] as int;

    if (sourceTicketIndex == targetTicketIndex) return;

    final tickets = ref.read(ticketsProvider);
    final item = tickets[sourceTicketIndex].items[itemIndex];

    // Check if same product+variant already exists in target ticket → merge in DB
    final existingIndex = tickets[targetTicketIndex].items.indexWhere(
      (existing) => existing.productId == item.productId &&
          existing.variantId == item.variantId &&
          existing.id != null &&
          existing.id != item.id,
    );

    if (existingIndex != -1) {
      final existing = tickets[targetTicketIndex].items[existingIndex];
      final merged = await _mergeInDatabase(existing, item);
      if (!merged) return;
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tickets = ref.read(ticketsProvider);
      final updatedTickets = List<TicketData>.from(
        tickets.map((ticket) => ticket.copyWith(items: List<OrderItem>.from(ticket.items))),
      );

      final movedItem = updatedTickets[sourceTicketIndex].items[itemIndex];
      updatedTickets[sourceTicketIndex].items.removeAt(itemIndex);

      // Check if same product+variant exists in target ticket → merge UI
      final mergeIndex = updatedTickets[targetTicketIndex].items.indexWhere(
        (existing) => existing.productId == movedItem.productId &&
            existing.variantId == movedItem.variantId &&
            existing.id != null &&
            existing.id != movedItem.id,
      );

      if (mergeIndex != -1) {
        final existing = updatedTickets[targetTicketIndex].items[mergeIndex];
        updatedTickets[targetTicketIndex].items[mergeIndex] = existing.copyWith(
          quantity: existing.quantity + movedItem.quantity,
        );
      } else {
        updatedTickets[targetTicketIndex].items.add(movedItem);
      }

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
      // Get next ticket number — query fresh from DB to avoid collisions in batch pay
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

      // Update order items in DB
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

      // Update UI state immediately (synchronous, no frame callback)
      // This is critical for _payAllTickets to see the correct state on next iteration.
      if (mounted) {
        final updatedItems = ticket.items.map((item) => item.copyWith(ticketId: ticketId, state: 'PAID')).toList();
        final currentTickets = ref.read(ticketsProvider);
        final updatedTickets = List<TicketData>.from(currentTickets);
        if (ticketIndex < updatedTickets.length) {
          updatedTickets[ticketIndex] = ticket.copyWith(
            isPaid: true,
            ticketId: ticketId,
            ticketNum: ticketNumStr,
            items: updatedItems,
          );
        }
        ref.read(ticketsProvider.notifier).state = updatedTickets;
        ref.read(calculatorProvider.notifier).state = CalculatorState();

        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.translate('ticket_paid_successfully').replaceAll('{0}', ticketNumStr)),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      }

      // Print ticket
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        final businessName = prefs.getString('business_name') ?? 'THANK YOU FOR YOUR PURCHASE';

        final itemsForPrint = ticket.items.map((item) {
          return {
            'name': item.displayName,
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

      // Check if all order products are now paid -> mark order as COMPLETED and sync
      if (orderId != null) {
        await _checkAndCompleteOrder(orderId);
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

  /// Pay all unpaid tickets — reads fresh state before each payment to avoid stale-state bugs
  Future<void> _payAllTickets() async {
    // Snapshot the count once; iterate by re-reading state each time so we always
    // operate on the up-to-date ticket list (state is now updated synchronously in _processPayment).
    final initialCount = ref.read(ticketsProvider).length;

    for (int i = 0; i < initialCount; i++) {
      final currentTickets = ref.read(ticketsProvider);
      if (i >= currentTickets.length) break;
      final ticket = currentTickets[i];
      if (!ticket.isPaid && ticket.items.isNotEmpty) {
        await _processPayment(i, ticket);
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

  /// Check if all order products are paid, mark order as paid default status and sync
  Future<void> _checkAndCompleteOrder(int orderId) async {
    try {
      final database = ref.read(databaseProvider);

      // Check if all products in the order are paid
      final allProducts = await (database.select(database.orderProducts)
        ..where((p) => p.orderId.equals(orderId)))
        .get();

      final allPaid = allProducts.isNotEmpty &&
          allProducts.every((p) => p.state == 'PAID');

      if (allPaid) {
        // Update order status to paid default status (skip internal sync, we handle it below)
        final orderRepo = ref.read(orderRepositoryProvider);
        final settings = ref.read(settingsProvider);
        final paidStatus = settings.paidOrderDefaultStatus;
        await orderRepo.updateOrderStatus(orderId, paidStatus, queueSyncOperation: false);
        _logger.info('Order #$orderId marked as $paidStatus (all products paid)');

        // Auto-sync if online
        final isOnline = ref.read(lastKnownOnlineStatusProvider);
        if (isOnline) {
          try {
            final syncManager = ref.read(syncManagerProvider.notifier);
            await syncManager.autoSyncOrder(orderId);
            _logger.info('Auto-synced $paidStatus order #$orderId');
          } catch (e) {
            _logger.error('Auto-sync failed for order #$orderId: $e');
          }
        }

        // Close payment dialog with success
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      _logger.error('Error checking/completing order #$orderId: $e');
    }
  }

  /// Tap: Quick split – peel off 1 unit from the item into a NEW ticket
  Future<void> _quickSplitOne(int ticketIndex, int itemIndex, OrderItem item) async {
    if (item.quantity <= 1) return;

    final newId = await _splitInDatabase(item, item.quantity - 1, 1);
    if (newId == null) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tickets = ref.read(ticketsProvider);
      final updatedTickets = List<TicketData>.from(
        tickets.map((ticket) => ticket.copyWith(items: List<OrderItem>.from(ticket.items))),
      );

      // Reduce original by 1 in same ticket
      updatedTickets[ticketIndex].items[itemIndex] = item.copyWith(quantity: item.quantity - 1);

      // The split-off qty-1 goes into a brand-new ticket
      final newItem = item.copyWith(id: newId, quantity: 1);
      final defaultMethod = TransactionType.fromString(
        ref.read(settingsProvider).defaultPaymentMethod,
      );
      updatedTickets.add(TicketData(
        items: [newItem],
        paymentMethod: defaultMethod,
        discountPercentage: widget.order.discountPercentage,
      ));

      ref.read(ticketsProvider.notifier).state = updatedTickets;
    });
  }

  /// Merge two same-product items when one is dropped onto another
  Future<void> _mergeItems(Map<String, dynamic> data, int targetTicketIndex, int targetItemIndex) async {
    final sourceTicketIndex = data['ticketIndex'] as int;
    final sourceItemIndex = data['itemIndex'] as int;
    final draggedItem = data['item'] as OrderItem;

    final tickets = ref.read(ticketsProvider);
    final targetItem = tickets[targetTicketIndex].items[targetItemIndex];

    // Persist merge in database
    final merged = await _mergeInDatabase(targetItem, draggedItem);
    if (!merged) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tickets = ref.read(ticketsProvider);
      final updatedTickets = List<TicketData>.from(
        tickets.map((ticket) => ticket.copyWith(items: List<OrderItem>.from(ticket.items))),
      );

      final currentTarget = updatedTickets[targetTicketIndex].items[targetItemIndex];

      // Merge: add dragged quantity into target
      updatedTickets[targetTicketIndex].items[targetItemIndex] = currentTarget.copyWith(
        quantity: currentTarget.quantity + draggedItem.quantity,
      );

      // Remove the source item
      if (sourceTicketIndex == targetTicketIndex) {
        // Same ticket – adjust index for removal
        final removeIdx = sourceItemIndex > targetItemIndex ? sourceItemIndex : sourceItemIndex;
        updatedTickets[sourceTicketIndex].items.removeAt(removeIdx);
      } else {
        updatedTickets[sourceTicketIndex].items.removeAt(sourceItemIndex);
      }

      ref.read(ticketsProvider.notifier).state = updatedTickets;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.merge_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('${draggedItem.displayName} → ${currentTarget.quantity + draggedItem.quantity}x'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    });
  }

  /// Persist a split in the database:
  /// - Updates the original order_product row to [keepQty]
  /// - Inserts a new order_product row with [splitQty] (including duplicating components)
  /// Returns the new row's id, or null on failure.
  Future<int?> _splitInDatabase(OrderItem item, int keepQty, int splitQty) async {
    if (item.id == null) return null;
    final database = ref.read(databaseProvider);

    try {
      // 1. Update original row quantity
      await (database.update(database.orderProducts)
        ..where((tbl) => tbl.id.equals(item.id!)))
        .write(OrderProductsCompanion(
          quantity: Value(keepQty),
          updatedAt: Value(DateTime.now()),
        ));

      // 2. Insert new row for the split portion
      final newId = await database.into(database.orderProducts).insert(
        OrderProductsCompanion.insert(
          orderId: widget.order.orderId ?? 0,
          productId: item.productId,
          variantId: Value(item.variantId),
          quantity: Value(splitQty),
          unitaryPrice: item.finalPrice,
          unitaryDiscount: Value(item.discount),
          unitaryTva: Value(item.tva),
          manualDiscount: Value(item.manualDiscount),
          note: Value(item.note),
          state: Value(item.state),
        ),
      );

      // 3. Duplicate components for the new row
      final existingComponents = await (database.select(database.orderProductComponents)
        ..where((c) => c.orderProductId.equals(item.id!)))
        .get();

      for (final comp in existingComponents) {
        await database.into(database.orderProductComponents).insert(
          OrderProductComponentsCompanion.insert(
            componentId: comp.componentId,
            orderProductId: newId,
            quantity: Value(comp.quantity),
            price: Value(comp.price),
            isSpecial: Value(comp.isSpecial),
          ),
        );
      }

      _logger.info('Split order_product #${item.id}: $keepQty + $splitQty → new id #$newId');
      return newId;
    } catch (e) {
      _logger.error('Failed to split in database: $e');
      return null;
    }
  }

  /// Persist a merge in the database:
  /// - Adds [source] quantity into [target] row
  /// - Deletes the [source] row (and its components)
  Future<bool> _mergeInDatabase(OrderItem target, OrderItem source) async {
    if (target.id == null || source.id == null) return false;
    // Don't merge a row with itself
    if (target.id == source.id) return false;
    final database = ref.read(databaseProvider);

    try {
      final newQty = target.quantity + source.quantity;

      // 1. Update target row quantity
      await (database.update(database.orderProducts)
        ..where((tbl) => tbl.id.equals(target.id!)))
        .write(OrderProductsCompanion(
          quantity: Value(newQty),
          updatedAt: Value(DateTime.now()),
        ));

      // 2. Delete source row's components first
      await (database.delete(database.orderProductComponents)
        ..where((c) => c.orderProductId.equals(source.id!)))
        .go();

      // 3. Delete source row
      await (database.delete(database.orderProducts)
        ..where((tbl) => tbl.id.equals(source.id!)))
        .go();

      _logger.info('Merged order_product #${source.id} into #${target.id} → $newQty');
      return true;
    } catch (e) {
      _logger.error('Failed to merge in database: $e');
      return false;
    }
  }

  /// Long press: Custom divide dialog with slider and constraints
  void _showCustomDivideDialog(OrderItem item, int ticketIndex, int itemIndex) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final currencyFormatter = ref.read(currencyFormatterProvider);
    int splitQty = 1;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final qty1 = splitQty;
            final qty2 = item.quantity - splitQty;
            final price1 = item.totalPrice / item.quantity * qty1;
            final price2 = item.totalPrice / item.quantity * qty2;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.call_split_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.translate('divide_quantity'),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Product name
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.quantity}x',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                          ),
                          Text(
                            currencyFormatter.format(item.totalPrice),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Slider
                    Row(
                      children: [
                        _buildSplitPreview(theme, currencyFormatter, qty1, price1, theme.colorScheme.primary),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: theme.colorScheme.primary,
                              inactiveTrackColor: theme.colorScheme.secondary.withValues(alpha: 0.3),
                              thumbColor: theme.colorScheme.primary,
                              overlayColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                              trackHeight: 6,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                            ),
                            child: Slider(
                              value: splitQty.toDouble(),
                              min: 1,
                              max: (item.quantity - 1).toDouble(),
                              divisions: item.quantity - 2 > 0 ? item.quantity - 2 : 1,
                              onChanged: (val) {
                                setDialogState(() => splitQty = val.round());
                              },
                            ),
                          ),
                        ),
                        _buildSplitPreview(theme, currencyFormatter, qty2, price2, theme.colorScheme.secondary),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Quick presets for common splits
                    if (item.quantity > 2)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: _buildQuickSplitChips(item, setDialogState, (val) => splitQty = val, splitQty),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(l10n.translate('cancel')),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _divideItemQuantity(item, qty1, qty2, ticketIndex, itemIndex);
                  },
                  icon: const Icon(Icons.call_split_rounded, size: 18),
                  label: Text('${l10n.translate('split_into_quantities')}: $qty1 + $qty2'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSplitPreview(ThemeData theme, CurrencyFormatter formatter, int qty, double price, Color color) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            '${qty}x',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            formatter.format(price),
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildQuickSplitChips(OrderItem item, StateSetter setDialogState, Function(int) onSplitChanged, int currentSplit) {
    final chips = <Widget>[];
    final qty = item.quantity;

    // Half split
    if (qty % 2 == 0) {
      final half = qty ~/ 2;
      chips.add(_buildSplitChip('½ + ½', half, currentSplit, setDialogState, onSplitChanged));
    }

    // Thirds
    if (qty % 3 == 0) {
      final third = qty ~/ 3;
      chips.add(_buildSplitChip('⅓ + ⅔', third, currentSplit, setDialogState, onSplitChanged));
    }

    // 1 + rest
    if (qty > 2) {
      chips.add(_buildSplitChip('1 + ${qty - 1}', 1, currentSplit, setDialogState, onSplitChanged));
    }

    // rest + 1
    if (qty > 3) {
      chips.add(_buildSplitChip('${qty - 1} + 1', qty - 1, currentSplit, setDialogState, onSplitChanged));
    }

    return chips;
  }

  Widget _buildSplitChip(String label, int splitVal, int currentSplit, StateSetter setDialogState, Function(int) onSplitChanged) {
    final theme = Theme.of(context);
    final isSelected = currentSplit == splitVal;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setDialogState(() => onSplitChanged(splitVal));
      },
      selectedColor: theme.colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? theme.colorScheme.onPrimaryContainer : null,
      ),
    );
  }

  Future<void> _divideItemQuantity(OrderItem item, int quantity1, int quantity2, int ticketIndex, int itemIndex) async {
    final newId = await _splitInDatabase(item, quantity1, quantity2);
    if (newId == null) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final tickets = ref.read(ticketsProvider);
      final updatedTickets = List<TicketData>.from(
        tickets.map((ticket) => ticket.copyWith(items: List<OrderItem>.from(ticket.items))),
      );

      // Keep first portion in the same ticket
      updatedTickets[ticketIndex].items[itemIndex] = item.copyWith(quantity: quantity1);

      // Second portion goes into a brand-new ticket
      final newItem = item.copyWith(id: newId, quantity: quantity2);
      final defaultMethodDiv = TransactionType.fromString(
        ref.read(settingsProvider).defaultPaymentMethod,
      );
      updatedTickets.add(TicketData(
        items: [newItem],
        paymentMethod: defaultMethodDiv,
        discountPercentage: widget.order.discountPercentage,
      ));

      ref.read(ticketsProvider.notifier).state = updatedTickets;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.call_split_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('${item.displayName}: $quantity1 + $quantity2 → 2 tickets'),
            ],
          ),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
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




