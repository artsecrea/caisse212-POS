import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/order_models.dart';
import '../../providers/database_providers.dart';
import '../../providers/device_providers.dart';
import '../../services/printing_service.dart';

class PrintOptionsDialog extends ConsumerStatefulWidget {
  final CurrentOrder order;
  final String? cashierName;
  final String? storeName;
  final String? storeAddress;
  final String? storePhone;
  final VoidCallback? onPrintComplete;

  const PrintOptionsDialog({
    super.key,
    required this.order,
    this.cashierName,
    this.storeName,
    this.storeAddress,
    this.storePhone,
    this.onPrintComplete,
  });

  @override
  ConsumerState<PrintOptionsDialog> createState() => _PrintOptionsDialogState();
}

class _PrintOptionsDialogState extends ConsumerState<PrintOptionsDialog> {
  bool _printReceipt = true;
  bool _printKds = false;
  KdsPrintMode _kdsPrintMode = KdsPrintMode.modificationsOnly;
  // Empty = all stations; non-empty = only selected station IDs
  final Set<int> _selectedStationIds = {};
  bool _isPrinting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkUnprintedItems();
  }

  // "New" means an unpaid line the kitchen hasn't seen yet. A paid line
  // with kdsPrintedAt == null is NOT new — it just lost its KDS stamp
  // (failed first print, KDS was disabled, came from the server, etc.) and
  // surprising the cashier with a "(2)" badge on an order they didn't touch
  // is what the customer complaint was about. Reprinting those paid lines
  // is still possible via `KdsPrintMode.full`.
  // A line is a pending modification when it's unpaid AND its current quantity
  // exceeds what has already been sent to the kitchen (0 for never-printed
  // lines, so those still count in full). Matches the delta logic in
  // PrintingService._filterItemsByMode.
  bool _isUnprinted(item) =>
      item.ticketId == null && item.quantity > item.kdsPrintedQuantity;

  void _checkUnprintedItems() {
    final hasUnprinted = widget.order.items.any(_isUnprinted);
    if (!hasUnprinted) _kdsPrintMode = KdsPrintMode.full;
  }

  int get _unprintedCount => widget.order.items.where(_isUnprinted).length;

  Future<void> _handlePrint() async {
    if (!_printReceipt && !_printKds) {
      setState(() => _error = 'Select at least one print option.');
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
      if (_printReceipt) {
        // Store identity, the courier block and the separate courier slip are
        // all the service's job now — passing them from here is what let this
        // dialog's ticket drift from the automatic one. Anything this dialog
        // does NOT pass is resolved from settings and the order row, so both
        // paths produce the same paper.
        receiptSuccess = await printingService.printOrderReceipt(
          order: widget.order,
          cashierName: widget.cashierName,
          storeName: widget.storeName,
          storeAddress: widget.storeAddress,
          storePhone: widget.storePhone,
        );
      }

      if (_printKds && printingService.config.kdsEnabled) {
        kdsSuccess = await printingService.printKdsTicket(
          order: widget.order,
          cashierName: widget.cashierName,
          mode: _kdsPrintMode,
          stationIds: _selectedStationIds.toList(),
        );
      }

      if (mounted) {
        if (receiptSuccess && kdsSuccess) {
          await _incrementPrintCount();
          widget.onPrintComplete?.call();
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Printed successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          setState(() {
            _isPrinting = false;
            _error = !receiptSuccess && !kdsSuccess
                ? 'Both receipt and KDS failed. Check connections.'
                : !receiptSuccess
                    ? 'Receipt failed. Check receipt printer.'
                    : 'KDS failed. Check KDS printer.';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _isPrinting = false; _error = 'Error: $e'; });
    }
  }

  Future<void> _incrementPrintCount() async {
    final orderId = widget.order.orderId;
    if (orderId == null) return;
    try {
      final db = ref.read(databaseProvider);
      await db.customStatement(
        'UPDATE orders SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
        [orderId],
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final printingService = ref.watch(printingServiceProvider);
    final config = printingService.config;
    final stationsAsync = ref.watch(stationListProvider);

    final receiptReady = config.receiptPrinterName != null;
    final kdsReady = config.kdsEnabled && config.kdsPrinterName != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              // White content on top: needs a dark background in both themes,
              // which `primaryColor` is not. See [AppTheme.bar].
              color: AppTheme.bar(theme.colorScheme),
              child: Row(
                children: [
                  const Icon(Icons.print, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Order #${widget.order.orderId ?? "New"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined,
                        color: Colors.white70, size: 20),
                    tooltip: 'Configure Printers',
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed('/printers');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed:
                        _isPrinting ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),

            // ── Scrollable Body ──────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order summary card
                    _OrderSummaryCard(order: widget.order),
                    const SizedBox(height: 16),

                    Text(
                      'Print options',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Receipt card
                    _PrintTypeCard(
                      icon: Icons.receipt_long,
                      title: 'Customer Receipt',
                      subtitle: receiptReady
                          ? config.receiptPrinterName!
                          : 'No printer configured',
                      ready: receiptReady,
                      selected: _printReceipt,
                      disabled: _isPrinting || !receiptReady,
                      onTap: receiptReady && !_isPrinting
                          ? () => setState(() => _printReceipt = !_printReceipt)
                          : null,
                    ),
                    const SizedBox(height: 8),

                    // KDS card
                    _PrintTypeCard(
                      icon: Icons.restaurant,
                      title: 'Kitchen Ticket (KDS)',
                      subtitle: !config.kdsEnabled
                          ? 'KDS disabled in settings'
                          : kdsReady
                              ? config.kdsPrinterName!
                              : 'No printer configured',
                      ready: kdsReady,
                      selected: _printKds,
                      disabled: _isPrinting || !kdsReady,
                      onTap: kdsReady && !_isPrinting
                          ? () => setState(() => _printKds = !_printKds)
                          : null,
                    ),

                    // KDS sub-options
                    if (_printKds && kdsReady) ...[
                      const SizedBox(height: 12),
                      _KdsOptions(
                        mode: _kdsPrintMode,
                        unprintedCount: _unprintedCount,
                        totalCount: widget.order.items.length,
                        disabled: _isPrinting,
                        onModeChanged: (m) => setState(() => _kdsPrintMode = m),
                      ),
                      const SizedBox(height: 12),

                      // Station selector
                      stationsAsync.when(
                        data: (stations) {
                          if (stations.isEmpty) return const SizedBox.shrink();
                          return _StationSelector(
                            stations: stations,
                            selectedIds: _selectedStationIds,
                            disabled: _isPrinting,
                            onToggle: (id) => setState(() {
                              if (_selectedStationIds.contains(id)) {
                                _selectedStationIds.remove(id);
                              } else {
                                _selectedStationIds.add(id);
                              }
                            }),
                            onClear: () =>
                                setState(() => _selectedStationIds.clear()),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],

                    // Error
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: _error!),
                    ],
                  ],
                ),
              ),
            ),

            // ── Footer ──────────────────────────────────────────────────
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _isPrinting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isPrinting ? null : _handlePrint,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.print, size: 18),
                    label: Text(_isPrinting ? 'Printing…' : 'Print'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _OrderSummaryCard extends StatelessWidget {
  final CurrentOrder order;
  const _OrderSummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Order Summary',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _SummaryChip(
                  icon: Icons.shopping_bag_outlined,
                  label: '${order.items.length} items'),
              _SummaryChip(
                  icon: order.type == 'DINE_IN'
                      ? Icons.restaurant
                      : Icons.takeout_dining,
                  label: order.type == 'DINE_IN' ? 'Dine In' : 'Take Away'),
              if (order.tableName != null)
                _SummaryChip(
                    icon: Icons.table_bar, label: order.tableName!),
              if (order.customerName != null)
                _SummaryChip(
                    icon: Icons.person_outline, label: order.customerName!),
              _SummaryChip(
                  icon: Icons.attach_money,
                  label: order.total.toStringAsFixed(2),
                  highlight: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;
  const _SummaryChip(
      {required this.icon, required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? theme.primaryColor.withValues(alpha: 0.1)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: highlight
                ? theme.primaryColor.withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: highlight ? theme.primaryColor : Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  highlight ? FontWeight.w600 : FontWeight.normal,
              color: highlight ? theme.primaryColor : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrintTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool ready;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _PrintTypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ready,
    required this.selected,
    required this.disabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.primaryColor;
    final borderColor = selected && ready
        ? activeColor
        : ready
            ? Colors.grey.withValues(alpha: 0.3)
            : Colors.grey.withValues(alpha: 0.15);
    final bgColor = selected && ready
        ? activeColor.withValues(alpha: 0.05)
        : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: selected && ready ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ready
                      ? (selected
                          ? activeColor.withValues(alpha: 0.12)
                          : Colors.grey.withValues(alpha: 0.08))
                      : Colors.grey.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: ready
                      ? (selected ? activeColor : Theme.of(context).colorScheme.onSurfaceVariant)
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: ready ? null : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: ready ? Colors.green[700] : Colors.red[400],
                      ),
                    ),
                  ],
                ),
              ),
              if (ready)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: selected
                      ? Icon(Icons.check_circle,
                          key: const ValueKey('checked'),
                          color: activeColor,
                          size: 22)
                      : Icon(Icons.circle_outlined,
                          key: const ValueKey('unchecked'),
                          color: Theme.of(context).colorScheme.outline,
                          size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KdsOptions extends StatelessWidget {
  final KdsPrintMode mode;
  final int unprintedCount;
  final int totalCount;
  final bool disabled;
  final ValueChanged<KdsPrintMode> onModeChanged;

  const _KdsOptions({
    required this.mode,
    required this.unprintedCount,
    required this.totalCount,
    required this.disabled,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Print mode',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ModeButton(
                label: 'New items only',
                count: unprintedCount,
                selected: mode == KdsPrintMode.modificationsOnly,
                color: theme.primaryColor,
                onTap: disabled
                    ? null
                    : () => onModeChanged(KdsPrintMode.modificationsOnly),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeButton(
                label: 'Full order',
                count: totalCount,
                selected: mode == KdsPrintMode.full,
                color: theme.primaryColor,
                onTap: disabled
                    ? null
                    : () => onModeChanged(KdsPrintMode.full),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  const _ModeButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : Colors.grey.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? color : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count item${count != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: selected ? color.withValues(alpha: 0.8) : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationSelector extends StatelessWidget {
  final List<dynamic> stations;
  final Set<int> selectedIds;
  final bool disabled;
  final ValueChanged<int> onToggle;
  final VoidCallback onClear;

  const _StationSelector({
    required this.stations,
    required this.selectedIds,
    required this.disabled,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = selectedIds.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Station',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // "All" chip
            _StationChip(
              label: 'All stations',
              selected: allSelected,
              color: theme.primaryColor,
              onTap: disabled ? null : onClear,
            ),
            // Per-station chips
            ...stations.map((s) {
              final isSelected = selectedIds.contains(s.id);
              return _StationChip(
                label: s.name as String,
                selected: isSelected && !allSelected,
                color: theme.primaryColor,
                onTap: disabled ? null : () => onToggle(s.id as int),
              );
            }),
          ],
        ),
        if (!allSelected)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${selectedIds.length} station${selectedIds.length != 1 ? 's' : ''} selected',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _StationChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  const _StationChip({
    required this.label,
    required this.selected,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            // `color` is caller-supplied, so pick the readable foreground for
            // it rather than assuming it is dark enough for white.
            color: selected
                ? (ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black)
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
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
