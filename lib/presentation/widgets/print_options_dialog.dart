// filepath: /home/artecrea/StudioProjects/posecrea/lib/presentation/widgets/print_options_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/order_models.dart';
import '../../providers/database_providers.dart';
import '../../services/printing_service.dart';

/// Dialog to select what to print for an order
class PrintOptionsDialog extends ConsumerStatefulWidget {
  final CurrentOrder order;
  final String? cashierName;
  final String? storeName;
  final String? storeAddress;
  final String? storePhone;
  final VoidCallback? onPrintComplete;

  const PrintOptionsDialog({
    Key? key,
    required this.order,
    this.cashierName,
    this.storeName,
    this.storeAddress,
    this.storePhone,
    this.onPrintComplete,
  }) : super(key: key);

  @override
  ConsumerState<PrintOptionsDialog> createState() => _PrintOptionsDialogState();
}

class _PrintOptionsDialogState extends ConsumerState<PrintOptionsDialog> {
  bool _printReceipt = true;
  bool _printKds = false; // KDS should only print on direct payment by default
  bool _isPrinting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // KDS should be off by default - it's meant for direct payment
    // User can still manually enable it if needed
  }

  Future<void> _handlePrint() async {
    if (!_printReceipt && !_printKds) {
      setState(() {
        _error = 'Please select at least one option to print';
      });
      return;
    }

    setState(() {
      _isPrinting = true;
      _error = null;
    });

    final printingService = ref.read(printingServiceProvider);
    bool receiptSuccess = true;
    bool kdsSuccess = true;

    try {
      // Print receipt if selected
      if (_printReceipt) {
        receiptSuccess = await printingService.printOrderReceipt(
          order: widget.order,
          cashierName: widget.cashierName,
          storeName: widget.storeName,
          storeAddress: widget.storeAddress,
          storePhone: widget.storePhone,
        );
      }

      // Print KDS if selected and enabled
      if (_printKds && printingService.config.kdsEnabled) {
        kdsSuccess = await printingService.printKdsTicket(
          order: widget.order,
          cashierName: widget.cashierName,
        );
      }

      if (mounted) {
        if (receiptSuccess && kdsSuccess) {
          // Update print count in database
          await _incrementPrintCount();

          widget.onPrintComplete?.call();
          Navigator.of(context).pop(true);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Print successful!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          setState(() {
            _isPrinting = false;
            if (!receiptSuccess && !kdsSuccess) {
              _error = 'Failed to print receipt and KDS ticket. Check printer connections.';
            } else if (!receiptSuccess) {
              _error = 'Failed to print receipt. Check receipt printer connection.';
            } else {
              _error = 'Failed to print KDS ticket. Check KDS printer connection.';
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPrinting = false;
          _error = 'Print error: $e';
        });
      }
    }
  }

  Future<void> _incrementPrintCount() async {
    final orderId = widget.order.orderId;
    if (orderId == null) return;

    try {
      final database = ref.read(databaseProvider);
      // Increment print count in orders table
      await database.customStatement(
        'UPDATE orders SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
        [orderId],
      );
    } catch (e) {
      debugPrint('Error incrementing print count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final printingService = ref.watch(printingServiceProvider);
    final config = printingService.config;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.print, size: 28),
          const SizedBox(width: 12),
          Text('Print Order #${widget.order.orderId ?? "New"}'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order Summary',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('Items', '${widget.order.items.length}'),
                  _buildInfoRow('Type', widget.order.type == 'DINE_IN' ? 'Dine In' : 'Take Away'),
                  if (widget.order.tableName != null)
                    _buildInfoRow('Table', widget.order.tableName!),
                  if (widget.order.customerName != null)
                    _buildInfoRow('Customer', widget.order.customerName!),
                  _buildInfoRow('Total', '\$${widget.order.total.toStringAsFixed(2)}'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Select what to print:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Print options
            CheckboxListTile(
              value: _printReceipt,
              onChanged: _isPrinting ? null : (value) {
                setState(() {
                  _printReceipt = value ?? false;
                });
              },
              title: const Text('Customer Receipt'),
              subtitle: Text(
                config.receiptPrinterName ?? 'No printer configured',
                style: TextStyle(
                  color: config.receiptPrinterName != null ? Colors.green : Colors.red,
                  fontSize: 12,
                ),
              ),
              secondary: Icon(
                Icons.receipt_long,
                color: config.receiptPrinterName != null ? Colors.green : Colors.grey,
              ),
              enabled: config.receiptPrinterName != null,
            ),

            CheckboxListTile(
              value: _printKds && config.kdsEnabled,
              onChanged: (!_isPrinting && config.kdsEnabled) ? (value) {
                setState(() {
                  _printKds = value ?? false;
                });
              } : null,
              title: const Text('Kitchen Ticket (KDS)'),
              subtitle: Text(
                !config.kdsEnabled
                    ? 'KDS printing disabled'
                    : config.kdsPrinterName ?? 'No printer configured',
                style: TextStyle(
                  color: config.kdsEnabled && config.kdsPrinterName != null
                      ? Colors.green
                      : Colors.red,
                  fontSize: 12,
                ),
              ),
              secondary: Icon(
                Icons.restaurant,
                color: config.kdsEnabled && config.kdsPrinterName != null
                    ? Colors.green
                    : Colors.grey,
              ),
              enabled: config.kdsEnabled && config.kdsPrinterName != null,
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Printer settings link
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pushNamed('/printers');
                },
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Configure Printers'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isPrinting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isPrinting ? null : _handlePrint,

          icon: _isPrinting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.print),
          label: Text(_isPrinting ? 'Printing...' : 'Print'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Show print options dialog
Future<bool?> showPrintOptionsDialog(
  BuildContext context, {
  required CurrentOrder order,
  String? cashierName,
  String? storeName,
  String? storeAddress,
  String? storePhone,
  VoidCallback? onPrintComplete,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => PrintOptionsDialog(
      order: order,
      cashierName: cashierName,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      onPrintComplete: onPrintComplete,
    ),
  );
}
