import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/responsive_utils.dart';

/// Model for Web Order Response (from API)
class WebOrderResponse {
  final int id;
  final String code;
  final String state;
  final String type;
  final int businessId;
  final int? tableId;
  final String? tableName;
  final int? customerId;
  final String? customerName;
  final int? commercialId;
  final String? commercialName;
  final int? createdBy;
  final String? createdByName;
  final int? servedBy;
  final String? servedByName;
  final String dateTime;
  final List<WebOrderProductResponse> products;
  final double totalAmount;
  final String? createdAt;
  final String? updatedAt;

  WebOrderResponse({
    required this.id,
    required this.code,
    required this.state,
    required this.type,
    required this.businessId,
    this.tableId,
    this.tableName,
    this.customerId,
    this.customerName,
    this.commercialId,
    this.commercialName,
    this.createdBy,
    this.createdByName,
    this.servedBy,
    this.servedByName,
    required this.dateTime,
    required this.products,
    required this.totalAmount,
    this.createdAt,
    this.updatedAt,
  });

  factory WebOrderResponse.fromJson(Map<String, dynamic> json) {
    return WebOrderResponse(
      id: json['id'] as int,
      code: json['code'] as String,
      state: json['state'] as String,
      type: json['type'] as String,
      businessId: json['businessId'] as int,
      tableId: json['tableId'] as int?,
      tableName: json['tableName'] as String?,
      customerId: json['customerId'] as int?,
      customerName: json['customerName'] as String?,
      commercialId: json['commercialId'] as int?,
      commercialName: json['commercialName'] as String?,
      createdBy: json['createdBy'] as int?,
      createdByName: json['createdByName'] as String?,
      servedBy: json['servedBy'] as int?,
      servedByName: json['servedByName'] as String?,
      dateTime: json['dateTime'] as String,
      products: (json['products'] as List<dynamic>)
          .map((e) => WebOrderProductResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalAmount: (json['totalAmount'] as num).toDouble(),
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }
}

class WebOrderProductResponse {
  final int id;
  final int productId;
  final String? productName;
  final String? stationName;
  final int? stationId;
  final double quantity;
  final double? price;
  final double? discountAmount;
  final double? manualDiscountAmount;
  final double? totalTva;
  final String? note;
  final List<WebOrderProductOptionResponse> options;

  WebOrderProductResponse({
    required this.id,
    required this.productId,
    this.productName,
    this.stationName,
    this.stationId,
    required this.quantity,
    this.price,
    this.discountAmount,
    this.manualDiscountAmount,
    this.totalTva,
    this.note,
    required this.options,
  });

  factory WebOrderProductResponse.fromJson(Map<String, dynamic> json) {
    return WebOrderProductResponse(
      id: json['id'] as int,
      productId: json['productId'] as int,
      productName: json['productName'] as String?,
      stationName: json['stationName'] as String?,
      stationId: json['stationId'] as int?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      discountAmount: json['discountAmount'] != null ? (json['discountAmount'] as num).toDouble() : null,
      manualDiscountAmount: json['manualDiscountAmount'] != null ? (json['manualDiscountAmount'] as num).toDouble() : null,
      totalTva: json['totalTva'] != null ? (json['totalTva'] as num).toDouble() : null,
      note: json['note'] as String?,
      options: (json['options'] as List<dynamic>?)
              ?.map((e) => WebOrderProductOptionResponse.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class WebOrderProductOptionResponse {
  final int id;
  final int componentId;
  final String? componentName;
  final int quantity;
  final bool isSpecial;
  final double? price;

  WebOrderProductOptionResponse({
    required this.id,
    required this.componentId,
    this.componentName,
    required this.quantity,
    required this.isSpecial,
    this.price,
  });

  factory WebOrderProductOptionResponse.fromJson(Map<String, dynamic> json) {
    return WebOrderProductOptionResponse(
      id: json['id'] as int,
      componentId: json['componentId'] as int,
      componentName: json['componentName'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      isSpecial: json['isSpecial'] as bool? ?? false,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
    );
  }
}

/// Dialog to display order details
class OrderDetailsDialog extends ConsumerWidget {
  final WebOrderResponse order;

  const OrderDetailsDialog({
    Key? key,
    required this.order,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(settingsProvider).currency;
    final currencyFormatter = NumberFormat.currency(symbol: currency);
    final dateFormatter = DateFormat('yyyy-MM-dd HH:mm');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth(context, 800),
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order ${order.code}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getStatusText(order.state),
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  _buildStatusBadge(context, order.state),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order Information
                    _buildInfoSection(
                      context,
                      'Order Information',
                      [
                        _InfoRow('Type', _getTypeText(order.type)),
                        if (order.tableName != null) _InfoRow('Table', order.tableName!),
                        if (order.customerName != null) _InfoRow('Customer', order.customerName!),
                        if (order.commercialName != null) _InfoRow('Commercial', order.commercialName!),
                        if (order.createdByName != null) _InfoRow('Created By', order.createdByName!),
                        if (order.servedByName != null) _InfoRow('Served By', order.servedByName!),
                        _InfoRow('Date & Time', dateFormatter.format(DateTime.parse(order.dateTime))),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Products
                    _buildSectionHeader(context, 'Products (${order.products.length})'),
                    const SizedBox(height: 12),
                    ...order.products.map((product) => _buildProductCard(context, product, currencyFormatter)),

                    const SizedBox(height: 24),

                    // Total
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Amount',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            currencyFormatter.format(order.totalAmount),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, String title, List<_InfoRow> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, title),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: rows
                .map((row) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              row.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              row.value,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, WebOrderProductResponse product, NumberFormat currencyFormatter) {
    final productTotal = (product.price ?? 0) * product.quantity;
    final optionsTotal = product.options.fold<double>(
      0,
      (sum, opt) => sum + ((opt.price ?? 0) * opt.quantity),
    );
    final itemTotal = productTotal + optionsTotal - (product.discountAmount ?? 0) - (product.manualDiscountAmount ?? 0) + (product.totalTva ?? 0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'x${formatQty(product.quantity)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName ?? 'Unknown Product',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (product.stationName != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.restaurant, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              product.stationName!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  currencyFormatter.format(itemTotal),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),

            // Note
            if (product.note != null && product.note!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sticky_note_2, size: 16, color: Colors.amber[800]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        product.note!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.amber[900],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Options
            if (product.options.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...product.options.map((option) => Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_outline, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${option.componentName ?? 'Unknown'} x${option.quantity}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (option.price != null)
                          Text(
                            currencyFormatter.format(option.price! * option.quantity),
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  )),
            ],

            // Discounts
            if ((product.discountAmount ?? 0) > 0 || (product.manualDiscountAmount ?? 0) > 0) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              if ((product.discountAmount ?? 0) > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Discount',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[700],
                      ),
                    ),
                    Text(
                      '-${currencyFormatter.format(product.discountAmount)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              if ((product.manualDiscountAmount ?? 0) > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Manual Discount',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[700],
                      ),
                    ),
                    Text(
                      '-${currencyFormatter.format(product.manualDiscountAmount)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, String state) {
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (state.toUpperCase()) {
      case 'PENDING':
        backgroundColor = Colors.orange[50]!;
        textColor = Colors.orange[800]!;
        icon = Icons.pending;
        break;
      case 'COMPLETED':
        backgroundColor = Colors.green[50]!;
        textColor = Colors.green[800]!;
        icon = Icons.check_circle;
        break;
      case 'CANCELLED':
        backgroundColor = Colors.red[50]!;
        textColor = Colors.red[800]!;
        icon = Icons.cancel;
        break;
      case 'ONHOLD':
        backgroundColor = Colors.blue[50]!;
        textColor = Colors.blue[800]!;
        icon = Icons.pause_circle;
        break;
      default:
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
        icon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            _getStatusText(state),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String state) {
    switch (state.toUpperCase()) {
      case 'PENDING':
        return 'Pending';
      case 'COMPLETED':
        return 'Completed';
      case 'CANCELLED':
        return 'Cancelled';
      case 'ONHOLD':
        return 'On Hold';
      default:
        return state;
    }
  }

  String _getTypeText(String type) {
    switch (type.toUpperCase()) {
      case 'DINE_IN':
        return 'Dine In';
      case 'TAKE_AWAY':
        return 'Take Away';
      case 'DELIVERY':
        return 'Delivery';
      default:
        return type;
    }
  }
}

class _InfoRow {
  final String label;
  final String value;

  _InfoRow(this.label, this.value);
}
