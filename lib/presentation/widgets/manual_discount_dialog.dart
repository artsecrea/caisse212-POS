import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import './adaptive_text_field.dart';

/// Which way round the cashier is thinking about the reduction.
enum DiscountEntryMode { percentage, amount }

/// The percentage that takes [amount] off [base].
///
/// The order stores a PERCENTAGE — `discountAmount` is derived as
/// `totalBeforeDiscount * (pct / 100)` — so an amount typed by the cashier has
/// to be converted before it can be saved. Kept as a free function so the
/// conversion is testable without building the dialog.
///
/// Clamped to 100: "take 600 off a 500 order" is a typo or a refund, and
/// letting it through would write a negative total. A zero or negative base
/// has no percentage that means anything, so it yields 0.
double percentageForAmount(double amount, double base) {
  if (base <= 0 || amount <= 0) return 0.0;
  final pct = amount / base * 100;
  return pct > 100 ? 100.0 : pct;
}

/// The money [percentage] takes off [base] — the inverse of
/// [percentageForAmount], for showing the cashier what they just asked for.
double amountForPercentage(double percentage, double base) {
  if (base <= 0 || percentage <= 0) return 0.0;
  return base * (percentage / 100);
}

class ManualDiscountDialog extends StatefulWidget {
  final double currentPercentage;
  final String? currentNote;

  /// The order total the reduction comes off, BEFORE any reduction — the same
  /// figure `CurrentOrder.discountAmount` multiplies. Needed to convert
  /// between the two ways of entering one, and to show the cashier the money.
  /// Zero (an empty cart) hides the amount mode rather than dividing by it.
  final double orderTotal;

  /// Currency symbol for the figures this dialog shows back. Passed in — the
  /// dialog is a plain StatefulWidget and the symbol lives in a provider.
  final String currencySymbol;

  const ManualDiscountDialog({
    Key? key,
    this.currentPercentage = 0.0,
    this.currentNote,
    this.orderTotal = 0.0,
    this.currencySymbol = '',
  }) : super(key: key);

  @override
  State<ManualDiscountDialog> createState() => _ManualDiscountDialogState();
}

class _ManualDiscountDialogState extends State<ManualDiscountDialog> {
  late TextEditingController _percentageController;
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  final _percentageFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _noteFocus = FocusNode();
  // Manual validation error (the onscreen-keyboard field is a TextField, not a
  // FormField, so we surface errors via the decoration's errorText instead).
  String? _percentageError;

  DiscountEntryMode _mode = DiscountEntryMode.percentage;

  bool get _canEnterAmount => widget.orderTotal > 0;

  @override
  void initState() {
    super.initState();
    _percentageController = TextEditingController(
      text: widget.currentPercentage > 0
          ? widget.currentPercentage.toStringAsFixed(1)
          : '',
    );
    _amountController = TextEditingController(
      text: widget.currentPercentage > 0 && _canEnterAmount
          ? amountForPercentage(widget.currentPercentage, widget.orderTotal)
              .toStringAsFixed(2)
          : '',
    );
    _noteController = TextEditingController(text: widget.currentNote ?? '');
  }

  @override
  void dispose() {
    _percentageController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _percentageFocus.dispose();
    _amountFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// The percentage the dialog would save right now, whichever box was used.
  double? _resolvedPercentage() {
    if (_mode == DiscountEntryMode.amount) {
      final raw = _amountController.text.trim();
      if (raw.isEmpty) return 0.0;
      final amount = double.tryParse(raw);
      if (amount == null) return null;
      return percentageForAmount(amount, widget.orderTotal);
    }
    final raw = _percentageController.text.trim();
    if (raw.isEmpty) return 0.0;
    return double.tryParse(raw);
  }

  void _applyDiscount() {
    final percentage = _resolvedPercentage();
    if (percentage == null) {
      setState(() => _percentageError = 'Please enter a valid number');
      return;
    }
    if (percentage < 0 || percentage > 100) {
      setState(() => _percentageError = 'Percentage must be between 0 and 100');
      return;
    }
    // Amount mode: refuse more than the order is worth rather than quietly
    // capping it at 100% — the cashier typed a number and should be told it
    // does not fit, not handed a different one.
    if (_mode == DiscountEntryMode.amount) {
      final typed = double.tryParse(_amountController.text.trim()) ?? 0.0;
      if (typed > widget.orderTotal + 0.005) {
        setState(() => _percentageError =
            'More than the order total (${widget.orderTotal.toStringAsFixed(2)})');
        return;
      }
    }
    final note =
        _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    Navigator.of(context).pop({'percentage': percentage, 'note': note});
  }

  /// Keep the other box honest as the cashier types.
  void _syncFromPercentage() {
    if (!_canEnterAmount) return;
    final pct = double.tryParse(_percentageController.text.trim()) ?? 0.0;
    _amountController.text =
        pct <= 0 ? '' : amountForPercentage(pct, widget.orderTotal).toStringAsFixed(2);
  }

  void _syncFromAmount() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    _percentageController.text = amount <= 0
        ? ''
        : percentageForAmount(amount, widget.orderTotal).toStringAsFixed(1);
  }

  String _money(double v) => widget.currencySymbol.isEmpty
      ? v.toStringAsFixed(2)
      : '${v.toStringAsFixed(2)} ${widget.currencySymbol}';

  @override
  Widget build(BuildContext context) {
    final isAmount = _mode == DiscountEntryMode.amount;
    final resolved = _resolvedPercentage() ?? 0.0;
    final resolvedAmount = amountForPercentage(resolved, widget.orderTotal);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action buttons.
              //
              // A Wrap, not a Row: with a discount already set there are three
              // buttons, and at 400px — or in a language where "Remove" is two
              // words — a Row overflows rather than reflowing. `Remove` rather
              // than `Remove Discount` for the same reason; it sits next to
              // Apply in a discount dialog and cannot mean anything else.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.currentPercentage > 0)
                    TextButton(
                      onPressed: () => Navigator.of(context)
                          .pop({'percentage': 0.0, 'note': null}),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Remove'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: _applyDiscount,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Pick the way round the cashier is thinking. Hidden entirely
              // when there is no total to convert against — an amount off an
              // empty cart is not a question with an answer.
              if (_canEnterAmount) ...[
                SegmentedButton<DiscountEntryMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: DiscountEntryMode.percentage,
                      label: Text('Percentage'),
                    ),
                    ButtonSegment(
                      value: DiscountEntryMode.amount,
                      label: Text('Amount'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (sel) {
                    setState(() {
                      _mode = sel.first;
                      _percentageError = null;
                      // Carry the figure across so switching mode never
                      // silently discards what was already typed.
                      if (_mode == DiscountEntryMode.amount) {
                        _syncFromPercentage();
                      } else {
                        _syncFromAmount();
                      }
                    });
                  },
                ),
                const SizedBox(height: 14),
              ],

              if (isAmount)
                AdaptiveKeyboardTextField(
                  key: const ValueKey('discount-amount'),
                  controller: _amountController,
                  focusNode: _amountFocus,
                  decoration: InputDecoration(
                    labelText: 'Discount Amount',
                    hintText: '0.00',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.payments_outlined),
                    errorText: _percentageError,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  autofocus: true,
                  onChanged: (_) => setState(() {
                    _percentageError = null;
                    _syncFromAmount();
                  }),
                  onSubmitted: (_) => _applyDiscount(),
                )
              else
                AdaptiveKeyboardTextField(
                  key: const ValueKey('discount-percentage'),
                  controller: _percentageController,
                  focusNode: _percentageFocus,
                  decoration: InputDecoration(
                    labelText: 'Discount Percentage',
                    hintText: '0.0',
                    suffixText: '%',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.percent),
                    errorText: _percentageError,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  autofocus: true,
                  onChanged: (_) => setState(() {
                    _percentageError = null;
                    _syncFromPercentage();
                  }),
                  onSubmitted: (_) => _applyDiscount(),
                ),

              // The conversion, shown both ways round. Whichever box the
              // cashier is in, the other number is the one they have to defend
              // to a customer or an auditor.
              if (_canEnterAmount && resolved > 0) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.tintFill(context, Colors.blue),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppTheme.tintBorder(context, Colors.blue)),
                  ),
                  child: Text(
                    '${resolved.toStringAsFixed(1)}%  ·  '
                    '-${_money(resolvedAmount)}   '
                    '(${_money(widget.orderTotal)} → '
                    '${_money(widget.orderTotal - resolvedAmount)})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.tintOn(context, Colors.blue),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Quick select. In amount mode these still name percentages —
              // round money is shop-specific, round percentages are not. No
              // heading: a row of "10%" chips does not need to be announced.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [5.0, 10.0, 15.0, 20.0, 25.0, 50.0].map((percentage) {
                  final isSelected =
                      double.tryParse(_percentageController.text) == percentage;
                  return ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _percentageError = null;
                        _percentageController.text =
                            percentage.toStringAsFixed(1);
                        _syncFromPercentage();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      foregroundColor: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                      elevation: isSelected ? 2 : 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('${percentage.toInt()}%'),
                  );
                }).toList(),
              ),

              const SizedBox(height: 14),

              // Note / reason field
              AdaptiveKeyboardTextField(
                controller: _noteController,
                focusNode: _noteFocus,
                decoration: InputDecoration(
                  labelText: 'Note (reason for discount)',
                  hintText: 'e.g. Loyalty customer, manager approval…',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.note_alt_outlined),
                ),
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _applyDiscount(),
              ),

              const SizedBox(height: 16),

            ],
          ),
        ),
      ),
    );
  }
}
