import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

/// Currency formatter utility
class CurrencyFormatter {
  final String symbol;

  CurrencyFormatter(this.symbol);

  /// Format amount with currency symbol
  String format(double amount) {
    return '${amount.toStringAsFixed(2)} $symbol';
  }

  /// Format amount with currency symbol (static helper)
  static String formatWithCurrency(double amount, String currency) {
    return '${amount.toStringAsFixed(2)} $currency';
  }

  /// Format amount with currency symbol (no decimals)
  String formatWhole(double amount) {
    return '$symbol${amount.toStringAsFixed(0)}';
  }
}

/// Provider for currency formatter
final currencyFormatterProvider = Provider<CurrencyFormatter>((ref) {
  final currency = ref.watch(settingsProvider).currency;
  return CurrencyFormatter(currency);
});

/// Provider for currency symbol only
final currencySymbolProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).currency;
});

