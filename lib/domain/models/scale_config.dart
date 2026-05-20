/// Barcode type emitted by scale labels.
/// [weightEmbedded] — the numeric value in the barcode represents weight (kg).
/// [priceEmbedded]  — the numeric value in the barcode represents the line total (currency).
enum ScaleBarcodeType { weightEmbedded, priceEmbedded }

/// Immutable configuration that describes how a scale-issued barcode is structured.
/// Default values match the most common Moroccan/EU supermarket scale format.
class ScaleConfig {
  final String prefix;
  final int pluLength;
  final int weightLength;
  final bool hasCheckDigit;
  final int weightDecimalPlaces;
  final ScaleBarcodeType barcodeType;

  const ScaleConfig({
    this.prefix = '21',
    this.pluLength = 4,
    this.weightLength = 5,
    this.hasCheckDigit = true,
    this.weightDecimalPlaces = 3,
    this.barcodeType = ScaleBarcodeType.weightEmbedded,
  });

  /// Total number of characters expected in a scale barcode.
  int get expectedTotalLength =>
      prefix.length + pluLength + weightLength + (hasCheckDigit ? 1 : 0);

  ScaleConfig copyWith({
    String? prefix,
    int? pluLength,
    int? weightLength,
    bool? hasCheckDigit,
    int? weightDecimalPlaces,
    ScaleBarcodeType? barcodeType,
  }) {
    return ScaleConfig(
      prefix: prefix ?? this.prefix,
      pluLength: pluLength ?? this.pluLength,
      weightLength: weightLength ?? this.weightLength,
      hasCheckDigit: hasCheckDigit ?? this.hasCheckDigit,
      weightDecimalPlaces: weightDecimalPlaces ?? this.weightDecimalPlaces,
      barcodeType: barcodeType ?? this.barcodeType,
    );
  }

  Map<String, dynamic> toJson() => {
        'prefix': prefix,
        'pluLength': pluLength,
        'weightLength': weightLength,
        'hasCheckDigit': hasCheckDigit,
        'weightDecimalPlaces': weightDecimalPlaces,
        'barcodeType': barcodeType.name,
      };

  factory ScaleConfig.fromJson(Map<String, dynamic> json) => ScaleConfig(
        prefix: json['prefix'] as String? ?? '21',
        pluLength: json['pluLength'] as int? ?? 4,
        weightLength: json['weightLength'] as int? ?? 5,
        hasCheckDigit: json['hasCheckDigit'] as bool? ?? true,
        weightDecimalPlaces: json['weightDecimalPlaces'] as int? ?? 3,
        barcodeType: ScaleBarcodeType.values.firstWhere(
          (e) => e.name == json['barcodeType'],
          orElse: () => ScaleBarcodeType.weightEmbedded,
        ),
      );
}

