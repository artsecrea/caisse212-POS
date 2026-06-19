import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart'
    show OnscreenKeyboardTextField;

import '../../providers/settings_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';

enum _TipMode { amount, percentage }

/// Touch-friendly dialog for entering an order tip.
///
/// Two input modes:
///   - **Amount** — the cashier types (or quick-picks) a literal currency
///     value. Quick chips add to the current input (`+5`, `+10`, `+20`,
///     `+50`).
///   - **Percentage** — the cashier picks `5% / 10% / 15% / 20%` (or types
///     a custom percent). The dialog shows the resulting currency amount
///     live, computed against [orderTotal].
///
/// Returns `double?` via Navigator.pop:
///   - the computed tip amount in currency on Confirm,
///   - `0.0` on "No tip" / Skip,
///   - `null` on dismiss (treated as no change by callers).
///
/// The dialog itself does NO API calls — the caller orchestrates the
/// `PATCH /orders/{id}/tip` after pop. Keeps this widget pure-UI.
class TipDialog extends ConsumerStatefulWidget {
  final double orderTotal;
  final double initialTip;

  const TipDialog({
    super.key,
    required this.orderTotal,
    this.initialTip = 0.0,
  });

  @override
  ConsumerState<TipDialog> createState() => _TipDialogState();
}

class _TipDialogState extends ConsumerState<TipDialog> {
  _TipMode _mode = _TipMode.amount;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  static const _amountChips = [5.0, 10.0, 20.0, 50.0];
  static const _percentChips = [5.0, 10.0, 15.0, 20.0];

  @override
  void initState() {
    super.initState();
    if (widget.initialTip > 0) {
      _controller.text = widget.initialTip.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double _parsedInput() {
    final raw = _controller.text.replaceAll(',', '.').trim();
    if (raw.isEmpty) return 0.0;
    return double.tryParse(raw) ?? 0.0;
  }

  /// Currency amount that will actually be sent to the server. In amount
  /// mode this is the raw input; in percentage mode it's percent × total.
  double _computedAmount() {
    final v = _parsedInput();
    if (_mode == _TipMode.amount) return v;
    return widget.orderTotal * v / 100.0;
  }

  void _setInput(double v) {
    setState(() {
      // Two decimals for currency mode, no decimals for percent (it's
      // almost always whole numbers and trailing .00 looks weird).
      _controller.text = _mode == _TipMode.amount
          ? v.toStringAsFixed(2)
          : v.toStringAsFixed(0);
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  /// Quick "+N" chip in amount mode: bump the current input by [delta].
  /// In percentage mode the chip overrides the value (since adding
  /// percentages doesn't intuitively match "5%, 10%, 15%, 20%").
  void _onChipTap(double delta) {
    if (_mode == _TipMode.amount) {
      _setInput(_parsedInput() + delta);
    } else {
      _setInput(delta);
    }
  }

  void _onModeChanged(_TipMode newMode) {
    if (newMode == _mode) return;
    setState(() {
      _mode = newMode;
      // Clear when switching — "10" means very different things between
      // 10 currency units and 10%, and inferring intent is asking for
      // trouble.
      _controller.text = '';
    });
  }

  void _onConfirm() {
    final amount = _computedAmount();
    if (amount < 0) return;
    Navigator.of(context).pop(amount);
  }

  void _onSkip() => Navigator.of(context).pop(0.0);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencySymbolProvider);
    final colors = Theme.of(context).colorScheme;
    final showKeyboard = ref.watch(settingsProvider).showOnscreenKeyboard;

    final computed = _computedAmount();
    final totalDue = widget.orderTotal + computed;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.attach_money, color: colors.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.translate('add_tip'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Order subtotal — context for the percentage option
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    '${l10n.translate('order_total')}:',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Spacer(),
                  Text(
                    CurrencyFormatter.formatWithCurrency(
                        widget.orderTotal, currency),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Mode toggle
            SegmentedButton<_TipMode>(
              style: SegmentedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
              segments: [
                ButtonSegment(
                  value: _TipMode.amount,
                  label: Text(l10n.translate('amount')),
                  icon: const Icon(Icons.payments_outlined),
                ),
                ButtonSegment(
                  value: _TipMode.percentage,
                  label: Text(l10n.translate('percentage')),
                  icon: const Icon(Icons.percent),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _onModeChanged(s.first),
            ),
            const SizedBox(height: 20),

            // Quick chips row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in (_mode == _TipMode.amount
                    ? _amountChips
                    : _percentChips))
                  _quickChip(v, currency, colors),
              ],
            ),
            const SizedBox(height: 16),

            // Input field
            (showKeyboard
                ? OnscreenKeyboardTextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9\.,]')),
                    ],
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: _inputDecoration(l10n, currency, colors),
                    onChanged: (_) => setState(() {}),
                  )
                : TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9\.,]')),
                    ],
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: _inputDecoration(l10n, currency, colors),
                    onChanged: (_) => setState(() {}),
                  )),
            const SizedBox(height: 20),

            // Live total breakdown
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  if (_mode == _TipMode.percentage) ...[
                    _summaryLine(
                      '${l10n.translate('tip')} (${_parsedInput().toStringAsFixed(0)}%)',
                      CurrencyFormatter.formatWithCurrency(computed, currency),
                    ),
                  ] else ...[
                    _summaryLine(
                      l10n.translate('tip'),
                      CurrencyFormatter.formatWithCurrency(computed, currency),
                    ),
                  ],
                  const SizedBox(height: 4),
                  const Divider(height: 12),
                  _summaryLine(
                    l10n.translate('total_due'),
                    CurrencyFormatter.formatWithCurrency(totalDue, currency),
                    bold: true,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onSkip,
                    icon: const Icon(Icons.close),
                    label: Text(l10n.translate('no_tip')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: computed > 0 ? _onConfirm : null,
                    icon: const Icon(Icons.check),
                    label: Text(l10n.translate('confirm_tip')),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
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

  Widget _quickChip(double v, String currency, ColorScheme colors) {
    final label = _mode == _TipMode.amount
        ? '+ ${v.toStringAsFixed(0)} $currency'
        : '${v.toStringAsFixed(0)}%';
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: () => _onChipTap(v),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          side: BorderSide(color: colors.primary, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
      AppLocalizations l10n, String currency, ColorScheme colors) {
    return InputDecoration(
      hintText: _mode == _TipMode.amount
          ? l10n.translate('enter_amount')
          : l10n.translate('enter_percentage'),
      prefixText: _mode == _TipMode.amount ? '$currency  ' : '',
      suffixText: _mode == _TipMode.percentage ? '  %' : '',
      prefixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      suffixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
    );
  }

  Widget _summaryLine(String label, String value,
      {bool bold = false, double size = 16}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: size,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: size,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
