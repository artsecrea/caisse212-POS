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
    final shortcuts = _shortcuts(ref);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 420;

        // Wide enough: the shortcuts become a column beside the keypad, sharing
        // its height like a till's tender keys. Stacked above it they were a
        // ragged wrap that left a blank band on the right and pushed the keypad
        // down for nothing.
        if (constraints.maxWidth >= 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAmountCard(
                theme,
                l10n,
                formatter,
                dense: dense,
                sideBySide: true,
              ),
              SizedBox(height: dense ? 4 : 6),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: (constraints.maxWidth * 0.3).clamp(110.0, 190.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < shortcuts.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: _shortcutChip(
                                  theme,
                                  l10n,
                                  formatter,
                                  shortcuts,
                                  i,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: _buildKeypad(theme)),
                  ],
                ),
              ),
            ],
          );
        }

        // Narrow: the chips share one row in equal widths, keypad below.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Short: received and change on one line to leave the keys room.
            _buildAmountCard(
              theme,
              l10n,
              formatter,
              dense: dense,
              sideBySide: dense,
            ),
            SizedBox(height: dense ? 4 : 6),
            SizedBox(
              height: dense ? 44 : 52,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < shortcuts.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _shortcutChip(
                          theme,
                          l10n,
                          formatter,
                          shortcuts,
                          i,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: dense ? 2 : 4),
            Expanded(child: _buildKeypad(theme)),
          ],
        );
      },
    );
  }

  Widget _buildAmountCard(
    ThemeData theme,
    AppLocalizations l10n,
    CurrencyFormatter formatter, {
    bool dense = false,
    bool sideBySide = false,
  }) {
    final short = amountDue - entered;
    final faint = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final received = Text(
      formatter.format(entered),
      style: TextStyle(
        fontSize: dense ? 26 : 34,
        fontWeight: FontWeight.bold,
        color: _isEnough ? Colors.green.shade700 : theme.colorScheme.primary,
      ),
    );
    final balanceLabel = Text(
      _isEnough
          ? l10n.translate('change_due')
          : l10n.translate('still_missing'),
      style: TextStyle(fontSize: 12, color: faint),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final balance = Text(
      formatter.format(_isEnough ? _change : short),
      style: TextStyle(
        fontSize: sideBySide ? (dense ? 22 : 28) : (dense ? 18 : 21),
        fontWeight: FontWeight.bold,
        color: _isEnough ? Colors.green.shade700 : theme.colorScheme.error,
      ),
    );

    final decoration = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: _isEnough
            ? Colors.green.shade600
            : theme.colorScheme.outlineVariant,
        width: _isEnough ? 2 : 1,
      ),
    );

    // Received and change side by side: one band of card instead of three
    // stacked lines.
    if (sideBySide) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 4 : 8),
        decoration: decoration,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.translate('amount_received'),
                      style: TextStyle(fontSize: 12, color: faint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    FittedBox(fit: BoxFit.scaleDown, child: received),
                  ],
                ),
              ),
              VerticalDivider(
                width: 20,
                color: theme.colorScheme.outlineVariant,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    balanceLabel,
                    FittedBox(fit: BoxFit.scaleDown, child: balance),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 4 : 8),
      decoration: decoration,
      child: Column(
        children: [
          Text(
            l10n.translate('amount_received'),
            style: TextStyle(fontSize: 12, color: faint),
          ),
          FittedBox(fit: BoxFit.scaleDown, child: received),
          Divider(height: dense ? 8 : 12),
          Row(
            children: [
              Expanded(child: balanceLabel),
              FittedBox(fit: BoxFit.scaleDown, child: balance),
            ],
          ),
        ],
      ),
    );
  }

  /// Whole notes lose the ".00" — a row of "200 DH / 300 DH" chips scans far
  /// faster than "200.00 DH / 300.00 DH" on a crowded touch screen.
  String _shortLabel(double amount, CurrencyFormatter formatter) =>
      amount == amount.roundToDouble()
      ? '${amount.toStringAsFixed(0)} ${formatter.symbol}'
      : formatter.format(amount);

  /// Shortcut [i]: the first is the exact amount, the rest are notes.
  Widget _shortcutChip(
    ThemeData theme,
    AppLocalizations l10n,
    CurrencyFormatter formatter,
    List<double> shortcuts,
    int i,
  ) {
    final amount = shortcuts[i];
    final exact = i == 0;
    final selected = (entered - amount).abs() < 0.005;
    return ElevatedButton(
      onPressed: () => onAmount(amount),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected
            ? theme.colorScheme.primary
            : (exact
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.secondaryContainer),
        foregroundColor: selected
            ? theme.colorScheme.onPrimary
            : (exact
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSecondaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        elevation: exact ? 2 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              exact ? l10n.translate('exact') : _shortLabel(amount, formatter),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (exact)
              Text(
                formatter.format(amount),
                style: const TextStyle(fontSize: 11),
              ),
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
                          minimumSize: Size.zero,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            key,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
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
