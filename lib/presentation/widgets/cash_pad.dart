import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';

/// The cash entry pad: what came in, what goes back, note shortcuts, keypad.
///
/// Controlled — the tendered amount lives with the caller, so the pad sits
/// directly inside the payment panel and speaks about the *selected ticket*
/// rather than the whole order. That is the point of it: on a divided order
/// only the ticket in hand has a meaningful "change due", and the cashier is
/// asked for cash in exactly one place instead of once before the payment
/// screen and again on it.
class CashPad extends ConsumerWidget {
  /// What this ticket owes, fee included. Drives the exact-amount shortcut,
  /// the change readout and the shortfall warning.
  final double amountDue;

  /// Cash keyed in so far.
  final double entered;

  /// A keypad press: `0`-`9`, `.` or `⌫`.
  final ValueChanged<String> onKey;

  /// A shortcut chip: the tender to jump straight to.
  final ValueChanged<double> onAmount;

  const CashPad({
    super.key,
    required this.amountDue,
    required this.entered,
    required this.onKey,
    required this.onAmount,
  });

  double get _change => entered - amountDue;
  bool get _isEnough => entered >= amountDue && entered > 0;

  /// Exact amount plus the note denominations that actually help: a 20 button
  /// is noise on a 340 DH bill, so only values above the total are offered,
  /// smallest first — the eye lands on the realistic tender.
  List<double> _shortcuts(WidgetRef ref) {
    final exact = (amountDue * 100).ceil() / 100;
    final notes = <double>{};

    for (final note in ref.watch(settingsProvider).quickCashAmounts) {
      final value = note.toDouble();
      if (value > exact) notes.add(value);
      // Also offer the next multiple of the note — two 100s for a 150 bill.
      final rounded = (amountDue / value).ceil() * value;
      if (rounded > exact) notes.add(rounded);
    }

    final sorted = notes.toList()..sort();
    return [exact, ...sorted.take(4)];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final formatter = ref.watch(currencyFormatterProvider);

    return LayoutBuilder(builder: (context, constraints) {
      // Stacked, the amount card and the note chips take ~200px off the top;
      // on a short screen that left the keypad keys as thin strips. Short and
      // wide: keypad beside the readout. Short and narrow: tighten everything
      // and give the chips one scrolling row.
      if (constraints.maxHeight >= 420) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAmountCard(theme, l10n, formatter),
            const SizedBox(height: 10),
            _buildShortcuts(theme, l10n, formatter, ref),
            const SizedBox(height: 10),
            Expanded(child: _buildKeypad(theme)),
          ],
        );
      }

      if (constraints.maxWidth >= 440) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAmountCard(theme, l10n, formatter, dense: true),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildShortcuts(theme, l10n, formatter, ref,
                          chipHeight: 42),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _buildKeypad(theme)),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAmountCard(theme, l10n, formatter, dense: true),
          const SizedBox(height: 6),
          _buildShortcuts(theme, l10n, formatter, ref,
              chipHeight: 40, singleRow: true),
          const SizedBox(height: 6),
          Expanded(child: _buildKeypad(theme)),
        ],
      );
    });
  }

  Widget _buildAmountCard(
      ThemeData theme, AppLocalizations l10n, CurrencyFormatter formatter,
      {bool dense = false}) {
    final short = amountDue - entered;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 6 : 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isEnough
              ? Colors.green.shade600
              : theme.colorScheme.outlineVariant,
          width: _isEnough ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            l10n.translate('amount_received'),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (!dense) const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatter.format(entered),
              style: TextStyle(
                fontSize: dense ? 28 : 38,
                fontWeight: FontWeight.bold,
                color:
                    _isEnough ? Colors.green.shade700 : theme.colorScheme.primary,
              ),
            ),
          ),
          Divider(height: dense ? 10 : 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isEnough
                    ? l10n.translate('change_due')
                    : l10n.translate('still_missing'),
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                formatter.format(_isEnough ? _change : short),
                style: TextStyle(
                  fontSize: dense ? 18 : 21,
                  fontWeight: FontWeight.bold,
                  color: _isEnough
                      ? Colors.green.shade700
                      : theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShortcuts(ThemeData theme, AppLocalizations l10n,
      CurrencyFormatter formatter, WidgetRef ref,
      {double chipHeight = 48, bool singleRow = false}) {
    final shortcuts = _shortcuts(ref);
    final chips = [
      for (var i = 0; i < shortcuts.length; i++)
        _shortcutChip(
          theme: theme,
          label: i == 0
              ? l10n.translate('exact')
              : _shortLabel(shortcuts[i], formatter),
          sublabel: i == 0 ? formatter.format(shortcuts[i]) : null,
          amount: shortcuts[i],
          highlighted: i == 0,
          height: chipHeight,
        ),
    ];

    if (singleRow) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  /// Whole notes lose the ".00" — a row of "200 DH / 300 DH" chips scans far
  /// faster than "200.00 DH / 300.00 DH" on a crowded touch screen.
  String _shortLabel(double amount, CurrencyFormatter formatter) =>
      amount == amount.roundToDouble()
          ? '${amount.toStringAsFixed(0)} ${formatter.symbol}'
          : formatter.format(amount);

  Widget _shortcutChip({
    required ThemeData theme,
    required String label,
    String? sublabel,
    required double amount,
    required bool highlighted,
    double height = 48,
  }) {
    final selected = (entered - amount).abs() < 0.005;
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: () => onAmount(amount),
        style: ElevatedButton.styleFrom(
          backgroundColor: selected
              ? theme.colorScheme.primary
              : (highlighted
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.secondaryContainer),
          foregroundColor: selected
              ? theme.colorScheme.onPrimary
              : (highlighted
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSecondaryContainer),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: highlighted ? 2 : 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (sublabel != null)
              Text(sublabel, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(ThemeData theme) {
    const rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['0', '.', '⌫'],
    ];

    return Column(
      children: [
        for (final row in rows)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: ElevatedButton(
                        onPressed: () => onKey(key),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: key == '⌫'
                              ? theme.colorScheme.errorContainer
                              : theme.colorScheme.secondaryContainer,
                          foregroundColor: key == '⌫'
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onSecondaryContainer,
                          padding: EdgeInsets.zero,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(key,
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
