import '../../data/database/app_database.dart' show OrderProduct;

/// What an order contains, condensed for a pick-list row.
class OrderContentSummary {
  /// Total units, so "3 articles" means three things to hand over.
  final double units;

  /// Distinct lines, which is what the preview is truncated against.
  final int lineCount;

  /// Up to N "2x Tajine" strings.
  final List<String> preview;

  /// How many lines the preview left out. Reported as a number rather than
  /// left to an ellipsis: "+4" tells the waiter how much they cannot see.
  final int hiddenLines;

  const OrderContentSummary({
    this.units = 0,
    this.lineCount = 0,
    this.preview = const [],
    this.hiddenLines = 0,
  });

  bool get isEmpty => lineCount == 0;

  /// Whole counts read "3", weighed ones keep their decimals.
  String get unitsLabel => units == units.roundToDouble()
      ? units.toStringAsFixed(0)
      : units.toStringAsFixed(3);

  String get previewLabel {
    if (preview.isEmpty) return '';
    final joined = preview.join(' · ');
    return hiddenLines > 0 ? '$joined  +$hiddenLines' : joined;
  }
}

/// A saved line of an order, with its product's name.
class SavedOrderLine {
  final OrderProduct row;
  final String name;
  const SavedOrderLine(this.row, this.name);
}
