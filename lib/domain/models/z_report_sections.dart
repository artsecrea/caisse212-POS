/// The numbered bands of the X / Z ticket an admin can switch off.
///
/// Stored as the HIDDEN set rather than the shown one, so a band added in a
/// later release prints by default instead of silently never appearing on a
/// till that saved its choice before the band existed.
enum ZReportSection {
  general('general_summary'),
  salesByType('sales_by_type'),
  payments('payments'),
  cashMovements('cash_movements'),
  indicators('restaurant_indicators'),
  families('summary_by_family'),
  topArticles('top_articles'),
  byTag('summary_by_tag', optIn: true),
  liveStatuses('live_statuses'),
  cancellations('cancellations'),
  outstanding('outstanding_on_floor');

  /// The heading the band prints under — reused as its settings label so the
  /// admin ticks the same words they read on the paper.
  final String l10nKey;

  /// Off until an admin ticks it. The stored list is a HIDDEN set, so an
  /// opt-in band is recorded the other way round: [optInShownToken] in the
  /// list means it prints.
  final bool optIn;

  const ZReportSection(this.l10nKey, {this.optIn = false});

  String get optInShownToken => '+$name';
}

/// Whether [band] prints, given a stored hidden list.
bool zBandShown(ZReportSection band, Iterable<String> stored) => band.optIn
    ? stored.contains(band.optInShownToken)
    : !stored.contains(band.name);

/// [stored] with [band] switched to [shown].
List<String> withZBandShown(
    Iterable<String> stored, ZReportSection band, bool shown) {
  final out = {...stored}
    ..remove(band.name)
    ..remove(band.optInShownToken);
  if (band.optIn && shown) out.add(band.optInShownToken);
  if (!band.optIn && !shown) out.add(band.name);
  return out.toList();
}

/// SharedPreferences key holding [ZReportSection.name]s that are switched off.
const String kZReportHiddenSectionsKey = 'z_report_hidden_sections';

/// The X's own hidden set. Absent until the admin first edits the X column,
/// and until then the X follows the Z's choice — what every till printed
/// before the two were split.
const String kXReportHiddenSectionsKey = 'x_report_hidden_sections';

/// Leave off every line whose figure is zero. Totals always print.
const String kXReportSkipZeroKey = 'x_report_skip_zero';
const String kZReportSkipZeroKey = 'z_report_skip_zero';

/// The bands a brief X keeps: what was taken, how, and what the drawer
/// should hold.
const Set<ZReportSection> kBriefXSections = {
  ZReportSection.general,
  ZReportSection.payments,
  ZReportSection.cashMovements,
};

/// Bands never printed on an X whatever the setting (see the printer).
const Set<ZReportSection> kZOnlySections = {ZReportSection.cancellations};
