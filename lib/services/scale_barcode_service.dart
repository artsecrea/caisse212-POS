import '../domain/models/scale_config.dart';

// ---------------------------------------------------------------------------
// Result hierarchy — sealed so switch expressions are exhaustive.
// ---------------------------------------------------------------------------

sealed class BarcodeResult {}

/// Barcode does not start with the configured prefix → treat as a regular
/// static product barcode; route to the existing findByBarcode() flow.
class StaticItem extends BarcodeResult {
  final String raw;
  StaticItem(this.raw);
}

/// Barcode parsed successfully as a scale label.
class WeightedItem extends BarcodeResult {
  /// PLU / MBW code extracted from the barcode (string, never cast to int).
  final String plu;

  /// Numeric value embedded in the barcode.
  /// For [ScaleBarcodeType.weightEmbedded]: weight in kg (e.g. 1.250).
  /// For [ScaleBarcodeType.priceEmbedded]  : line total in currency units (e.g. 12.50).
  final double extractedValue;

  WeightedItem({required this.plu, required this.extractedValue});
}

/// Barcode starts with the prefix but its length does not match the config.
class ConfigMismatch extends BarcodeResult {
  final int expected;
  final int actual;
  ConfigMismatch({required this.expected, required this.actual});
}

/// Length matches but the extracted PLU or weight segment contains non-digits.
class MalformedWeightBarcode extends BarcodeResult {
  final String reason;
  MalformedWeightBarcode(this.reason);
}

// ---------------------------------------------------------------------------
// Pure classifier function — no state, no side effects.
// ---------------------------------------------------------------------------

BarcodeResult classifyBarcode(String raw, ScaleConfig config) {
  // 1. Prefix check — not a scale label at all.
  if (!raw.startsWith(config.prefix)) return StaticItem(raw);

  // 2. Length check.
  final expected = config.expectedTotalLength;
  if (raw.length != expected) {
    return ConfigMismatch(expected: expected, actual: raw.length);
  }

  // 3. Slice out PLU and value segments.
  final offset = config.prefix.length;
  final plu = raw.substring(offset, offset + config.pluLength);
  final valueStr = raw.substring(
      offset + config.pluLength, offset + config.pluLength + config.weightLength);

  // 4. Digit-only validation — never attempt integer parsing before validation.
  final _digits = RegExp(r'^\d+$');
  if (!_digits.hasMatch(plu)) {
    return MalformedWeightBarcode('PLU segment contains non-digits: "$plu"');
  }
  if (!_digits.hasMatch(valueStr)) {
    return MalformedWeightBarcode('Value segment contains non-digits: "$valueStr"');
  }

  // 5. Parse numeric value with correct decimal placement.
  final rawInt = int.parse(valueStr);
  final divisor = _pow10(config.weightDecimalPlaces);
  final extractedValue = rawInt / divisor;

  return WeightedItem(plu: plu, extractedValue: extractedValue);
}

double _pow10(int n) {
  double result = 1.0;
  for (int i = 0; i < n; i++) {
    result *= 10.0;
  }
  return result;
}

