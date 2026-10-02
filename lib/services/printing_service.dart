// filepath: /home/artecrea/StudioProjects/posecrea/lib/services/printing_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Socket, SocketOption;
import 'dart:typed_data';
import 'dart:ui';

import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/enums.dart';
import 'serial_job_queue.dart';
import '../data/database/app_database.dart';
import '../domain/models/component_rules.dart';
import '../domain/models/order_course.dart';
import '../domain/models/order_models.dart';
import '../utils/app_localizations.dart';
import '../utils/currency_formatter.dart';
import 'daily_summary_service.dart';
import 'refund_service.dart';
import 'unpaid_orders_service.dart';

/// Enum for printer purpose
enum PrinterPurpose {
  receipt, // For customer receipts
  kds, // For kitchen display/tickets
}

/// What a kitchen ticket is FOR.
///
/// [send] is food to make. [cancel] is food to stop making — an item pulled
/// off a saved order, or the whole order voided. The kitchen has already been
/// told to cook it, so somebody has to be told not to; that is the entire
/// reason this exists, and why a cancellation ticket is never subject to the
/// delta filter (the caller has already worked out exactly what was pulled)
/// and never marks anything as sent.
enum KdsPrintPurpose { send, cancel }

/// Enum for KDS print mode
enum KdsPrintMode {
  full, // Print all items in the order
  modificationsOnly, // Print only new/unprinted items
}

/// How much of the order goes on a CUSTOMER order ticket.
///
/// The kitchen has had this choice since [KdsPrintMode] existed; the order
/// ticket never did, so every Continue on an open table reprinted the whole
/// bill from the top. A table on its third round got three full bills instead
/// of a slip for each round.
enum OrderTicketPrintMode {
  /// Every line, whatever has been printed before. What a bill presented to
  /// the customer wants, and what every caller did implicitly until now.
  full,

  /// Only the units not yet put on a slip — `quantity -
  /// orderTicketPrintedQuantity` per line. What a running table wants on each
  /// Continue.
  additionsOnly,
}

/// Where the business logo sits across the paper.
enum LogoAlign { left, center, right }

/// Distinct print outputs whose auto-printing can be configured independently.
enum PrintOutput { orderTicket, customerReceipt, storeCopy, kds }

/// Where the courier's platform code goes on paper.
///
/// Applies to GLOVO and KOOUL only. DealUp and Web orders have no courier and
/// no platform code, so the block is never emitted for them.
enum CourierCodeMode {
  /// Block at the TOP of the normal ticket, before the items — the default,
  /// because it needs no second roll and the courier reads the same paper the
  /// kitchen produced.
  sameTicket,

  /// A dedicated small ticket printed straight after the main one, to go on the
  /// bag. Costs an extra cut but survives the main ticket being kept back.
  separateTicket,

  off,
}

/// How the code is rendered for scanning.
enum CourierCodeSymbology {
  /// Default: dense, forgiving of a crumpled bag, and every courier app reads
  /// it from a phone camera.
  qr,

  /// For fleets using laser scanners, which read 1-D far better than QR.
  code128,

  /// No symbol at all — the code is typed in by hand.
  text,
}

/// Which name a product-linked option prints under.
///
/// The two can differ a lot: the menu calls it "Included drink", the shelf
/// calls it "Coca 33cl". Which one the kitchen wants depends on whether the
/// ticket is read by someone assembling the order or someone pouring it.
enum LinkedComponentLabel {
  /// What the customer chose, as the menu names it. The default, because it
  /// is what the parent ticket already says.
  component,

  /// What the linked product is called in the catalogue — the variant's name
  /// when the link points at one, otherwise the product's.
  product,
}

/// All known order types — used as the default set in a [PrintRule].
const Set<String> kAllOrderTypes = {'DINE_IN', 'TAKE_AWAY', 'DELIVERY'};

/// Canonical set of order *origins* the print rule can filter on.
///
/// Stored as the [Orders.source] column on the order row. New origins added
/// later (e.g. a self-service tablet) should land here so existing rules
/// continue to apply to them by default — the alternative (defaulting
/// unknown sources to "blocked") would silently break printing the moment
/// a new origin shows up.
///
/// - `POS`      — order created from the cashier POS UI (this app).
/// - `WAITER`   — order created via the waiter app over `/waiters/orders`.
/// - `KIOSK`    — order placed by an in-store kiosk (future).
/// - `EXTERNAL` — DealUp / WhatsApp queue confirmations.
const Set<String> kAllOrderSources = {'POS', 'WAITER', 'KIOSK', 'EXTERNAL'};

/// Per-output conditional print rule: whether the output prints at all, for
/// which order types, for which sources, and whether a table must be
/// selected.
class PrintRule {
  final bool enabled;
  final Set<String> orderTypes;
  final Set<String> sources;
  final bool requireTable;

  const PrintRule({
    this.enabled = true,
    this.orderTypes = kAllOrderTypes,
    this.sources = kAllOrderSources,
    this.requireTable = false,
  });

  PrintRule copyWith({
    bool? enabled,
    Set<String>? orderTypes,
    Set<String>? sources,
    bool? requireTable,
  }) {
    return PrintRule(
      enabled: enabled ?? this.enabled,
      orderTypes: orderTypes ?? this.orderTypes,
      sources: sources ?? this.sources,
      requireTable: requireTable ?? this.requireTable,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'orderTypes': orderTypes.toList(),
    'sources': sources.toList(),
    'requireTable': requireTable,
  };

  factory PrintRule.fromJson(Map<String, dynamic> json) {
    return PrintRule(
      enabled: json['enabled'] ?? true,
      orderTypes: (json['orderTypes'] as List?)?.map((e) => e.toString()).toSet() ??
          kAllOrderTypes,
      // Backward compat: rules persisted before this field existed default
      // to ALL sources so behavior matches what they had — they were always
      // applied to every order regardless of origin.
      sources: (json['sources'] as List?)?.map((e) => e.toString()).toSet() ??
          kAllOrderSources,
      requireTable: json['requireTable'] ?? false,
    );
  }
}

/// Model for saved printer configuration
class PrinterConfig {
  final String? receiptPrinterAddress;
  final String? receiptPrinterName;
  final ConnectionType? receiptConnectionType;
  final String? kdsPrinterAddress;
  final String? kdsPrinterName;
  final ConnectionType? kdsConnectionType;
  final bool kdsEnabled;
  final bool printingEnabled; // Master switch to enable/disable all printing
  final PaperSize paperSize;
  final int textSize; // 1=Normal, 2=Medium, 3=Large
  final String printingLanguage; // 'en' or 'fr'

  // Per-output conditional rules
  final PrintRule orderTicketRule;
  final PrintRule customerReceiptRule;
  final PrintRule storeCopyRule;
  final PrintRule kdsRule;

  // Pro configuration
  final bool autoPrintOnPayment; // Master auto-print switch on payment
  final int customerCopies; // Number of customer receipt copies
  final bool reprintWatermark; // Stamp DUPLICATA on reprints
  /// Courier-code printing, GLOVO/KOOUL only. See [CourierCodeMode].
  final CourierCodeMode courierCodeMode;
  final CourierCodeSymbology courierCodeSymbology;

  final bool cashDrawerKick; // Open cash drawer
  final bool cashDrawerCashOnly; // Only kick drawer for cash payments
  final bool splitKdsByStation; // Split kitchen tickets per station
  // Whether items whose product has NO station (no primary stationId and no
  // product_stations rows) print on the KDS at all. Default true = they print
  // in the "General" bucket / on the consolidated ticket (legacy behavior).
  // Turn OFF to suppress stationless items from every kitchen ticket.
  final bool printKdsUnassigned;
  final KdsPrintMode defaultKdsMode; // Default kitchen print mode
  // When `splitKdsByStation` is on AND there's more than one station to
  // print, send all station tickets to the printer in a SINGLE driver job
  // (one `_dispatchBytes` call) — with paper cuts between sections — instead
  // of one job per station. This avoids the "third sequential print fails"
  // class of bug on Windows USB drivers, where rapid back-to-back jobs
  // overwhelm the spooler / driver. Default is true; turn it off if you
  // prefer the legacy per-job behavior.
  final bool consolidateKdsJob;

  /// Ignore stations altogether: one ticket carrying the whole order, printed
  /// [kdsCopies] times on the single KDS printer.
  ///
  /// For a kitchen that has no stations to speak of and just wants two or
  /// three identical tickets — one for the pass, one for the line, one for the
  /// bag. Stronger than turning [splitKdsByStation] off, which still drops
  /// stationless items when [printKdsUnassigned] is off and still honours a
  /// station marked "no printer". In this mode neither applies: every item on
  /// the order is on every copy, which is the whole point of it.
  final bool kdsFullOrderMode;

  /// How many identical copies [kdsFullOrderMode] prints. Clamped 1..9.
  final int kdsCopies;

  /// Whether an option that stands for a product of its own also prints on
  /// that product's station — the drink inside a menu reaching the bar.
  ///
  /// Only ever does anything for components the backend has linked to a
  /// product, and only on stations the parent line is not already going to.
  final bool printLinkedComponents;

  /// Which name those lines carry. See [LinkedComponentLabel].
  final LinkedComponentLabel linkedComponentLabel;

  /// Per-ticket-type field visibility. Outer key = ticket type
  /// ('customer' | 'store' | 'kds'), inner key = field id, value = print it?.
  /// A missing entry means "visible" (default), so an empty map keeps the
  /// legacy behavior of printing every field.
  final Map<String, Map<String, bool>> ticketFields;

  /// Crop applied to the picked logo before it is printed, as fractions of
  /// the source image: left/top edge and right/bottom edge, 0..1.
  ///
  /// Held as fractions, and applied at print time rather than baked into
  /// the stored bytes, so the crop stays adjustable: reopening the editor
  /// shows the whole picked image again with the current box on it.
  final double logoCropLeft;
  final double logoCropTop;
  final double logoCropRight;
  final double logoCropBottom;

  /// Printed width as a percentage of the paper's printable width, 10..100.
  final int logoWidthPercent;

  /// Where the logo sits across the paper.
  final LogoAlign logoAlign;

  /// Whether the crop box is anything other than the whole image.
  bool get hasLogoCrop =>
      logoCropLeft > 0 ||
      logoCropTop > 0 ||
      logoCropRight < 1 ||
      logoCropBottom < 1;

  /// Per-ticket-type row order. Outer key = ticket type, value = field ids
  /// in the order the operator wants them printed. A missing entry means
  /// the catalogue order, which is what every ticket printed before this
  /// existed. See [orderedFields] for how a band is resolved.
  final Map<String, List<String>> ticketFieldOrder;

  /// Per-ticket-type text scale. Outer key = ticket type, inner key = field id,
  /// value = a tier from [textTiers]. 0 (or a missing entry) means "follow the
  /// global text size", which is what every ticket did before this existed.
  final Map<String, Map<String, int>> ticketFieldSizes;

  /// Catalog of toggleable content fields per ticket type — drives both the
  /// print gating and the settings UI. List order is the display order.
  static const Map<String, List<String>> fieldCatalog = {
    'order': [
      'storeAddress', 'storePhone', 'storeIce', 'orderCode', 'orderNumber',
      'date',
      'cashier', 'waiter',
      'orderType', 'table', 'persons', 'customerName', 'customerPhone',
      'deliveryAddress', 'subtotal', 'discount', 'tva', 'barcode',
    ],
    'customer': [
      'storeAddress', 'storePhone', 'storeIce', 'orderCode', 'orderNumber',
      'date',
      'cashier', 'waiter',
      'orderType', 'table', 'persons', 'customerName', 'customerPhone',
      'deliveryAddress', 'paymentMethod', 'discount', 'tva', 'amountGiven',
      'change', 'barcode',
    ],
    'store': [
      'storeAddress', 'storePhone', 'storeIce', 'orderCode', 'orderNumber',
      'date',
      'cashier', 'waiter',
      'orderType', 'table', 'persons', 'customerName', 'customerPhone',
      'deliveryAddress', 'paymentMethod', 'discount', 'tva', 'amountGiven',
      'change', 'barcode',
    ],
    'kds': [
      'orderCode', 'orderNumber', 'time', 'waiter', 'orderType', 'table',
      'persons',
      'customerName', 'customerPhone', 'orderNote', 'barcode',
    ],
  };

  /// Parts of a ticket that are always printed but whose size is still worth
  /// controlling — the store name, the product lines, the total. They carry
  /// the document, so a switch would only ever produce a broken receipt; a
  /// size input is the one knob that makes sense for them.
  static const Map<String, List<String>> sizeOnlyCatalog = {
    'order': ['storeName', 'items', 'total'],
    'customer': ['storeName', 'items', 'total'],
    'store': ['storeName', 'items', 'total'],
    'kds': ['stationName', 'items'],
  };

  /// Every field with a size input, in display order: the toggleable ones
  /// first, then the structural ones.
  static List<String> sizableFields(String ticket) =>
      [...?fieldCatalog[ticket], ...?sizeOnlyCatalog[ticket]];

  /// Which band of the ticket a field is printed in.
  ///
  /// Rows reorder freely inside a band. They do not move between bands:
  /// the bands are separated by rules and by the item list, so dragging a
  /// total into the header or the barcode above the items would not produce
  /// a differently-ordered ticket, it would produce a broken one.
  static const Map<String, String> fieldZone = {
    'storeAddress': 'header',
    'storePhone': 'header',
    'storeIce': 'header',
    'orderCode': 'info',
    'orderNumber': 'info',
    'date': 'info',
    'time': 'info',
    'cashier': 'info',
    'waiter': 'info',
    'orderType': 'info',
    'table': 'info',
    'persons': 'info',
    'customerName': 'info',
    'customerPhone': 'info',
    'deliveryAddress': 'info',
    'paymentMethod': 'info',
    'orderNote': 'note',
    'subtotal': 'totals',
    'discount': 'totals',
    'tva': 'totals',
    'amountGiven': 'totals',
    'change': 'totals',
    'barcode': 'trailer',
  };

  /// The bands in the order they are printed. Drives the settings UI.
  static const List<String> fieldZones = [
    'header',
    'info',
    'note',
    'totals',
    'trailer',
  ];

  static String zoneOf(String field) => fieldZone[field] ?? 'info';

  /// The fields of one band of one ticket, in the operator's order.
  ///
  /// Anything the saved order does not mention keeps its catalogue position
  /// at the end of its band, so a field added by a later build appears
  /// without the operator having to re-save an order they already set.
  List<String> orderedFields(String ticket, String zone) {
    final inZone = [
      for (final f in fieldCatalog[ticket] ?? const <String>[])
        if (zoneOf(f) == zone) f,
    ];
    final saved = ticketFieldOrder[ticket];
    if (saved == null || saved.isEmpty) return inZone;
    final seen = <String>{};
    final out = [
      for (final f in saved)
        if (inZone.contains(f) && seen.add(f)) f,
    ];
    for (final f in inZone) {
      if (!seen.contains(f)) out.add(f);
    }
    return out;
  }

  /// One ticket's fields as the settings UI stores them: every band, in
  /// print order, flattened into a single list.
  List<String> orderedFieldsFlat(String ticket) => [
        for (final zone in fieldZones) ...orderedFields(ticket, zone),
      ];

  /// Fields whose *absence* from [ticketFields] means "don't print", per
  /// ticket type.
  ///
  /// Every other field defaults to visible, which is what keeps a config saved
  /// before a field existed behaving exactly as it did. VAT, cash given and
  /// change arrived after the fact on the paid receipts, so flipping them on
  /// by default would silently add lines to every receipt in the field on the
  /// next update. The order ticket is the mirror image: it has always printed
  /// all of this unconditionally, so every one of its new switches starts ON
  /// and an updated till prints exactly what it printed yesterday until
  /// somebody changes something.
  ///
  /// `tva` was here too, and shops expected the tax line on a receipt they
  /// hand over — it read as broken rather than as opt-in. Cash given and
  /// change stay opt-in: those are a counter-shop habit, not a legal line.
  ///
  /// `orderNumber` (the per-session #1, #2…) is opt-in on every ticket: a new
  /// line nobody asked for until they switch it on.
  static const Map<String, Set<String>> defaultOffByTicket = {
    'order': {'orderNumber'},
    'customer': {'amountGiven', 'change', 'orderNumber'},
    'store': {'amountGiven', 'change', 'orderNumber'},
    'kds': {'orderNumber'},
  };

  /// Legacy alias, kept for callers that ask without naming a ticket type.
  static const Set<String> defaultOffFields = {
    'tva', 'amountGiven', 'change', 'orderNumber',
  };

  /// Visibility a field falls back to when the operator has never touched it.
  static bool fieldDefaultOn(String field, [String? ticket]) => ticket == null
      ? !defaultOffFields.contains(field)
      : !(defaultOffByTicket[ticket] ?? const <String>{}).contains(field);

  /// The text scales a field can be pinned to. 0 is not listed because it is
  /// the absence of a choice: follow whatever the global text size is set to.
  ///
  /// The widths stop at 2x on purpose. Column layout on a receipt is measured
  /// in characters, so a 3x-wide total would wrap into the price beside it —
  /// height is the axis that buys legibility without costing columns.
  static const Map<int, String> textTiers = {
    1: 'Normal',
    2: 'Tall',
    3: 'Large',
    4: 'Huge',
  };

  /// The scale pinned to one field, or 0 when it follows the global size.
  int fieldSize(String ticket, String field) =>
      ticketFieldSizes[ticket]?[field] ?? 0;

  /// The width+height a pinned tier maps to.
  ///
  /// Width tops out at 2x deliberately: `generator.row` divides the paper into
  /// character columns, so a wider face eats into the column beside it. Height
  /// is free — the print head just makes a second pass.
  static ({PosTextSize width, PosTextSize height}) tierSize(int tier) {
    switch (tier) {
      case 2:
        return (width: PosTextSize.size1, height: PosTextSize.size2);
      case 3:
        return (width: PosTextSize.size2, height: PosTextSize.size2);
      case 4:
        return (width: PosTextSize.size2, height: PosTextSize.size3);
      case 1:
      default:
        return (width: PosTextSize.size1, height: PosTextSize.size1);
    }
  }

  const PrinterConfig({
    this.receiptPrinterAddress,
    this.receiptPrinterName,
    this.receiptConnectionType,
    this.kdsPrinterAddress,
    this.kdsPrinterName,
    this.kdsConnectionType,
    this.kdsEnabled = true,
    this.printingEnabled = true,
    this.paperSize = PaperSize.mm80,
    this.textSize = 1,
    this.printingLanguage = 'en',
    this.orderTicketRule = const PrintRule(enabled: false),
    this.customerReceiptRule = const PrintRule(),
    this.storeCopyRule = const PrintRule(enabled: false),
    this.kdsRule = const PrintRule(),
    this.autoPrintOnPayment = true,
    this.customerCopies = 1,
    this.reprintWatermark = true,
    this.courierCodeMode = CourierCodeMode.sameTicket,
    this.courierCodeSymbology = CourierCodeSymbology.qr,
    this.cashDrawerKick = false,
    this.cashDrawerCashOnly = true,
    this.splitKdsByStation = true,
    this.printKdsUnassigned = true,
    this.defaultKdsMode = KdsPrintMode.modificationsOnly,
    this.consolidateKdsJob = true,
    this.kdsFullOrderMode = false,
    this.kdsCopies = 1,
    this.printLinkedComponents = true,
    this.linkedComponentLabel = LinkedComponentLabel.component,
    this.ticketFields = const {},
    this.ticketFieldSizes = const {},
    this.ticketFieldOrder = const {},
    this.logoCropLeft = 0.0,
    this.logoCropTop = 0.0,
    this.logoCropRight = 1.0,
    this.logoCropBottom = 1.0,
    this.logoWidthPercent = 100,
    this.logoAlign = LogoAlign.center,
  });

  PrinterConfig copyWith({
    String? receiptPrinterAddress,
    String? receiptPrinterName,
    ConnectionType? receiptConnectionType,
    String? kdsPrinterAddress,
    String? kdsPrinterName,
    ConnectionType? kdsConnectionType,
    bool? kdsEnabled,
    bool? printingEnabled,
    PaperSize? paperSize,
    int? textSize,
    String? printingLanguage,
    PrintRule? orderTicketRule,
    PrintRule? customerReceiptRule,
    PrintRule? storeCopyRule,
    PrintRule? kdsRule,
    bool? autoPrintOnPayment,
    int? customerCopies,
    bool? reprintWatermark,
    CourierCodeMode? courierCodeMode,
    CourierCodeSymbology? courierCodeSymbology,
    bool? cashDrawerKick,
    bool? cashDrawerCashOnly,
    bool? splitKdsByStation,
    bool? printKdsUnassigned,
    KdsPrintMode? defaultKdsMode,
    bool? consolidateKdsJob,
    bool? kdsFullOrderMode,
    int? kdsCopies,
    bool? printLinkedComponents,
    LinkedComponentLabel? linkedComponentLabel,
    Map<String, Map<String, bool>>? ticketFields,
    Map<String, Map<String, int>>? ticketFieldSizes,
    Map<String, List<String>>? ticketFieldOrder,
    double? logoCropLeft,
    double? logoCropTop,
    double? logoCropRight,
    double? logoCropBottom,
    int? logoWidthPercent,
    LogoAlign? logoAlign,
  }) {
    return PrinterConfig(
      receiptPrinterAddress:
          receiptPrinterAddress ?? this.receiptPrinterAddress,
      receiptPrinterName: receiptPrinterName ?? this.receiptPrinterName,
      receiptConnectionType:
          receiptConnectionType ?? this.receiptConnectionType,
      kdsPrinterAddress: kdsPrinterAddress ?? this.kdsPrinterAddress,
      kdsPrinterName: kdsPrinterName ?? this.kdsPrinterName,
      kdsConnectionType: kdsConnectionType ?? this.kdsConnectionType,
      kdsEnabled: kdsEnabled ?? this.kdsEnabled,
      printingEnabled: printingEnabled ?? this.printingEnabled,
      paperSize: paperSize ?? this.paperSize,
      textSize: textSize ?? this.textSize,
      printingLanguage: printingLanguage ?? this.printingLanguage,
      orderTicketRule: orderTicketRule ?? this.orderTicketRule,
      customerReceiptRule: customerReceiptRule ?? this.customerReceiptRule,
      storeCopyRule: storeCopyRule ?? this.storeCopyRule,
      kdsRule: kdsRule ?? this.kdsRule,
      autoPrintOnPayment: autoPrintOnPayment ?? this.autoPrintOnPayment,
      customerCopies: customerCopies ?? this.customerCopies,
      reprintWatermark: reprintWatermark ?? this.reprintWatermark,
      courierCodeMode: courierCodeMode ?? this.courierCodeMode,
      courierCodeSymbology: courierCodeSymbology ?? this.courierCodeSymbology,
      cashDrawerKick: cashDrawerKick ?? this.cashDrawerKick,
      cashDrawerCashOnly: cashDrawerCashOnly ?? this.cashDrawerCashOnly,
      splitKdsByStation: splitKdsByStation ?? this.splitKdsByStation,
      printKdsUnassigned: printKdsUnassigned ?? this.printKdsUnassigned,
      defaultKdsMode: defaultKdsMode ?? this.defaultKdsMode,
      consolidateKdsJob: consolidateKdsJob ?? this.consolidateKdsJob,
      kdsFullOrderMode: kdsFullOrderMode ?? this.kdsFullOrderMode,
      kdsCopies: kdsCopies ?? this.kdsCopies,
      printLinkedComponents:
          printLinkedComponents ?? this.printLinkedComponents,
      linkedComponentLabel:
          linkedComponentLabel ?? this.linkedComponentLabel,
      ticketFields: ticketFields ?? this.ticketFields,
      ticketFieldSizes: ticketFieldSizes ?? this.ticketFieldSizes,
      ticketFieldOrder: ticketFieldOrder ?? this.ticketFieldOrder,
      logoCropLeft: logoCropLeft ?? this.logoCropLeft,
      logoCropTop: logoCropTop ?? this.logoCropTop,
      logoCropRight: logoCropRight ?? this.logoCropRight,
      logoCropBottom: logoCropBottom ?? this.logoCropBottom,
      logoWidthPercent: logoWidthPercent ?? this.logoWidthPercent,
      logoAlign: logoAlign ?? this.logoAlign,
    );
  }

  Map<String, dynamic> toJson() => {
    'receiptPrinterAddress': receiptPrinterAddress,
    'receiptPrinterName': receiptPrinterName,
    'receiptConnectionType': receiptConnectionType?.index,
    'kdsPrinterAddress': kdsPrinterAddress,
    'kdsPrinterName': kdsPrinterName,
    'kdsConnectionType': kdsConnectionType?.index,
    'kdsEnabled': kdsEnabled,
    'printingEnabled': printingEnabled,
    // Human width (58/80) — `fromJson` reads it back by comparing to 58.
    // Storing `paperSize.value` (internal 1/2/3) broke the round-trip.
    'paperSize': paperSize == PaperSize.mm58 ? 58 : 80,
    'textSize': textSize,
    'printingLanguage': printingLanguage,
    'orderTicketRule': orderTicketRule.toJson(),
    'customerReceiptRule': customerReceiptRule.toJson(),
    'storeCopyRule': storeCopyRule.toJson(),
    'kdsRule': kdsRule.toJson(),
    'autoPrintOnPayment': autoPrintOnPayment,
    'customerCopies': customerCopies,
    'reprintWatermark': reprintWatermark,
    'courierCodeMode': courierCodeMode.index,
    'courierCodeSymbology': courierCodeSymbology.index,
    'cashDrawerKick': cashDrawerKick,
    'cashDrawerCashOnly': cashDrawerCashOnly,
    'splitKdsByStation': splitKdsByStation,
    'printKdsUnassigned': printKdsUnassigned,
    'defaultKdsMode': defaultKdsMode.index,
    'consolidateKdsJob': consolidateKdsJob,
    'kdsFullOrderMode': kdsFullOrderMode,
    'kdsCopies': kdsCopies,
    'printLinkedComponents': printLinkedComponents,
    'linkedComponentLabel': linkedComponentLabel.index,
    'ticketFields': ticketFields,
    'ticketFieldSizes': ticketFieldSizes,
    'ticketFieldOrder': ticketFieldOrder,
    'logoCropLeft': logoCropLeft,
    'logoCropTop': logoCropTop,
    'logoCropRight': logoCropRight,
    'logoCropBottom': logoCropBottom,
    'logoWidthPercent': logoWidthPercent,
    'logoAlign': logoAlign.index,
  };

  factory PrinterConfig.fromJson(Map<String, dynamic> json) {
    return PrinterConfig(
      receiptPrinterAddress: json['receiptPrinterAddress'],
      receiptPrinterName: json['receiptPrinterName'],
      receiptConnectionType: json['receiptConnectionType'] != null
          ? ConnectionType.values[json['receiptConnectionType']]
          : null,
      kdsPrinterAddress: json['kdsPrinterAddress'],
      kdsPrinterName: json['kdsPrinterName'],
      kdsConnectionType: json['kdsConnectionType'] != null
          ? ConnectionType.values[json['kdsConnectionType']]
          : null,
      kdsEnabled: json['kdsEnabled'] ?? true,
      printingEnabled: json['printingEnabled'] ?? true,
      paperSize: (json['paperSize'] == 58 || json['paperSize'] == 1)
          ? PaperSize.mm58
          : PaperSize.mm80,
      textSize: json['textSize'] ?? 1,
      printingLanguage: json['printingLanguage'] ?? 'en',
      orderTicketRule: json['orderTicketRule'] != null
          ? PrintRule.fromJson(Map<String, dynamic>.from(json['orderTicketRule']))
          : const PrintRule(enabled: false),
      customerReceiptRule: json['customerReceiptRule'] != null
          ? PrintRule.fromJson(
              Map<String, dynamic>.from(json['customerReceiptRule']))
          : const PrintRule(),
      storeCopyRule: json['storeCopyRule'] != null
          ? PrintRule.fromJson(Map<String, dynamic>.from(json['storeCopyRule']))
          : const PrintRule(enabled: false),
      kdsRule: json['kdsRule'] != null
          ? PrintRule.fromJson(Map<String, dynamic>.from(json['kdsRule']))
          : const PrintRule(),
      autoPrintOnPayment: json['autoPrintOnPayment'] ?? true,
      customerCopies: json['customerCopies'] ?? 1,
      reprintWatermark: json['reprintWatermark'] ?? true,
      // Index-based like defaultKdsMode, clamped so a config written by a
      // newer build cannot crash an older one on a bad index.
      courierCodeMode: CourierCodeMode.values[
          ((json['courierCodeMode'] as int?) ?? CourierCodeMode.sameTicket.index)
              .clamp(0, CourierCodeMode.values.length - 1)],
      courierCodeSymbology: CourierCodeSymbology.values[
          ((json['courierCodeSymbology'] as int?) ?? CourierCodeSymbology.qr.index)
              .clamp(0, CourierCodeSymbology.values.length - 1)],
      cashDrawerKick: json['cashDrawerKick'] ?? false,
      cashDrawerCashOnly: json['cashDrawerCashOnly'] ?? true,
      splitKdsByStation: json['splitKdsByStation'] ?? true,
      printKdsUnassigned: json['printKdsUnassigned'] ?? true,
      defaultKdsMode: json['defaultKdsMode'] != null
          ? KdsPrintMode.values[json['defaultKdsMode']]
          : KdsPrintMode.modificationsOnly,
      consolidateKdsJob: json['consolidateKdsJob'] ?? true,
      kdsFullOrderMode: json['kdsFullOrderMode'] ?? false,
      kdsCopies: ((json['kdsCopies'] as num?)?.toInt() ?? 1).clamp(1, 9),
      printLinkedComponents: json['printLinkedComponents'] ?? true,
      // Clamped like the other index-persisted enums, so a config written by
      // a newer build cannot crash an older one on an unknown value.
      linkedComponentLabel: LinkedComponentLabel.values[
          ((json['linkedComponentLabel'] as int?) ??
                  LinkedComponentLabel.component.index)
              .clamp(0, LinkedComponentLabel.values.length - 1)],
      ticketFields: parseTicketFields(json['ticketFields']),
      ticketFieldSizes: parseTicketFieldSizes(json['ticketFieldSizes']),
      ticketFieldOrder: parseTicketFieldOrder(json['ticketFieldOrder']),
      logoCropLeft: _fraction(json['logoCropLeft'], 0.0),
      logoCropTop: _fraction(json['logoCropTop'], 0.0),
      logoCropRight: _fraction(json['logoCropRight'], 1.0),
      logoCropBottom: _fraction(json['logoCropBottom'], 1.0),
      logoWidthPercent:
          ((json['logoWidthPercent'] as num?)?.toInt() ?? 100).clamp(10, 100),
      logoAlign: LogoAlign.values[
          ((json['logoAlign'] as num?)?.toInt() ?? LogoAlign.center.index)
              .clamp(0, LogoAlign.values.length - 1)],
    );
  }

  /// Decodes the nested `{ticketType: {field: bool}}` map from JSON (or a
  /// JSON string), tolerating nulls/partial data. Missing → empty map.
  static Map<String, Map<String, bool>> parseTicketFields(dynamic raw) {
    if (raw == null) return const {};
    final dynamic decoded;
    try {
      decoded = raw is String ? jsonDecode(raw) : raw;
    } catch (_) {
      // Truncated or hand-edited prefs. Losing the customisation is bad;
      // losing the whole printer config to an exception is worse.
      return const {};
    }
    if (decoded is! Map) return const {};
    final out = <String, Map<String, bool>>{};
    decoded.forEach((k, v) {
      if (v is Map) {
        out[k as String] = {
          for (final e in v.entries)
            if (e.value is bool) e.key as String: e.value as bool,
        };
      }
    });
    return out;
  }

  /// Decodes the nested `{ticketType: {field: tier}}` map. Tiers outside the
  /// known range are dropped rather than clamped: an unknown number means the
  /// config was written by a build that knows more sizes than this one, and
  /// falling back to the global size is the honest reading of that.
  static Map<String, Map<String, int>> parseTicketFieldSizes(dynamic raw) {
    if (raw == null) return const {};
    final dynamic decoded;
    try {
      decoded = raw is String ? jsonDecode(raw) : raw;
    } catch (_) {
      // Truncated or hand-edited prefs. Losing the customisation is bad;
      // losing the whole printer config to an exception is worse.
      return const {};
    }
    if (decoded is! Map) return const {};
    final out = <String, Map<String, int>>{};
    decoded.forEach((k, v) {
      if (v is Map) {
        out[k as String] = {
          for (final e in v.entries)
            if (e.value is int && textTiers.containsKey(e.value))
              e.key as String: e.value as int,
        };
      }
    });
    return out;
  }

  /// Decodes the `{ticketType: [fieldId, ...]}` row order. Unknown ids are
  /// kept rather than dropped: [orderedFields] filters against the
  /// catalogue anyway, and keeping them means an order saved by a newer
  /// build survives a round trip through an older one.
  /// A 0..1 crop edge from JSON. Anything outside the range, or not a
  /// number at all, falls back to [fallback] rather than clamping: a bad
  /// value means the config did not come from this editor, and guessing at
  /// a crop would silently cut a corner off every receipt.
  static double _fraction(dynamic raw, double fallback) {
    final v = (raw as num?)?.toDouble();
    if (v == null || v.isNaN || v < 0 || v > 1) return fallback;
    return v;
  }

  static Map<String, List<String>> parseTicketFieldOrder(dynamic raw) {
    if (raw == null) return const {};
    final dynamic decoded;
    try {
      decoded = raw is String ? jsonDecode(raw) : raw;
    } catch (_) {
      return const {};
    }
    if (decoded is! Map) return const {};
    final out = <String, List<String>>{};
    decoded.forEach((k, v) {
      if (v is List) {
        out[k as String] = [
          for (final e in v)
            if (e is String) e,
        ];
      }
    });
    return out;
  }
}

/// A named entry in the per-station printer pool. Lives in SharedPrefs as
/// part of a JSON-encoded list under `station_printer_pool_v1`. Identified
/// by a stable [id] so [stationAssignments] (stationId -> printerIds) keeps
/// resolving even after the pool list is reordered.
class NamedPrinter {
  final String id;
  final String label;
  final String address;
  final String name;
  final ConnectionType connectionType;

  const NamedPrinter({
    required this.id,
    required this.label,
    required this.address,
    required this.name,
    required this.connectionType,
  });

  NamedPrinter copyWith({
    String? label,
    String? address,
    String? name,
    ConnectionType? connectionType,
  }) {
    return NamedPrinter(
      id: id,
      label: label ?? this.label,
      address: address ?? this.address,
      name: name ?? this.name,
      connectionType: connectionType ?? this.connectionType,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'address': address,
    'name': name,
    'connectionType': connectionType.index,
  };

  factory NamedPrinter.fromJson(Map<String, dynamic> json) {
    return NamedPrinter(
      id: json['id'] as String,
      label: (json['label'] ?? '') as String,
      address: (json['address'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      connectionType: ConnectionType.values[(json['connectionType'] ?? 0) as int],
    );
  }
}

/// Sentinel value in the station→printer assignment map meaning "this station
/// must NOT print at all" (KDS-display only). Distinct from an *unassigned*
/// station, which falls back to the global KDS printer.
const kNoPrinterAssignment = '__none__';

/// SharedPrefs key holding the JSON-encoded list of [NamedPrinter] entries.
const _kPrefsPrinterPool = 'station_printer_pool_v1';

/// SharedPrefs key holding the JSON-encoded
/// `Map<String stationId, List<String> printerIds>`. Older installs hold a
/// bare `String printerId` per station; [_loadStationRouting] reads both.
const _kPrefsStationAssignments = 'station_printer_assignments_v1';

/// Per-station ticket rules — see [StationTicketRule]. Absent means every
/// station behaves as it always has.
const _kPrefsStationRules = 'station_ticket_rules_v1';

/// How much of an order a station's ticket shows.
enum StationTicketScope {
  /// Only this station's own items, and only when it has some. What every
  /// station has always done, and still the default.
  ownItems,

  /// Every line on the order, but only when this station owns at least one of
  /// them. The "if there is pizza AND burger, both get the full order" rule:
  /// a station that is cooking for this table sees what the rest of the table
  /// is getting, so it can time its plates against them.
  wholeOrderWhenUsed,

  /// Every line on every order, whether this station is cooking or not. The
  /// pass: one sheet per order, all night, so the expediter can assemble.
  wholeOrderAlways,
}

/// What one station does with a ticket.
///
/// Two switches rather than a station-by-station matrix, because two express
/// the arrangements kitchens actually run: which stations read the whole
/// order, and which station's items are nobody else's business.
///
/// [private] is the bar. Drinks belong on the bar's own ticket and nowhere
/// else — a pass sheet listing four beers among the food is noise, and a
/// pizza station does not need to know. A private station still gets its own
/// items in full; it is only kept OFF other stations' whole-order tickets.
class StationTicketRule {
  final StationTicketScope scope;
  final bool private;

  const StationTicketRule({
    this.scope = StationTicketScope.ownItems,
    this.private = false,
  });

  bool get isDefault =>
      scope == StationTicketScope.ownItems && !private;

  Map<String, dynamic> toJson() => {
        'scope': scope.name,
        'private': private,
      };

  static StationTicketRule fromJson(Map<String, dynamic> json) =>
      StationTicketRule(
        scope: StationTicketScope.values.firstWhere(
          (s) => s.name == json['scope'],
          // An unknown scope from a newer build reads as the safe one: the
          // station keeps printing its own items rather than silently
          // spraying the whole order at a printer nobody meant to configure.
          orElse: () => StationTicketScope.ownItems,
        ),
        private: json['private'] == true,
      );
}

/// Resolved per-call KDS printer target. Passed through the dispatch and
/// "ensure connected" path so station printing can hit a pool printer
/// without mutating `_config`.
class _KdsTarget {
  final String address;
  final String? name;
  final ConnectionType type;
  const _KdsTarget({required this.address, this.name, required this.type});
}

/// Entry representing a single order in a user's daily report
class UserDailyOrderEntry {
  final String orderCode;
  final double amount;
  final bool isPaid;
  final String paymentMethod;
  final DateTime date;

  const UserDailyOrderEntry({
    required this.orderCode,
    required this.amount,
    required this.isPaid,
    required this.paymentMethod,
    required this.date,
  });
}

/// An outstanding print failure, held until the cashier acknowledges it.
///
/// Printing runs detached from the cashier's tap, so this is what stops a dead
/// printer from being silent: the kitchen not getting a ticket has to be
/// visible somewhere, and it is no longer visible as a stalled button.
class PrintAlert {
  const PrintAlert({
    required this.reason,
    required this.at,
    required this.count,
  });

  /// Plain-language cause, e.g. "Kitchen ticket did not print (Cuisine)".
  final String reason;

  /// When the most recent failure happened.
  final DateTime at;

  /// Failed print attempts since the alert was last cleared. Internal retries
  /// count, so treat this as "how bad is it", not an exact ticket count.
  final int count;
}

/// An option line's text on the kitchen ticket and the order receipt. A
/// SINGLE or MULTIPLE pick is always one, so a count there is noise; a
/// QUANTITY stepper shows its count only when there is more than one.
String optionLineLabel(
        String name, int quantity, ComponentSelectionType selectionType) =>
    selectionType == ComponentSelectionType.quantity && quantity > 1
        ? '$name x$quantity'
        : name;

/// Printing service for thermal printers
class PrintingService {
  static final PrintingService _instance = PrintingService._internal();

  factory PrintingService() => _instance;

  PrintingService._internal();

  FlutterThermalPrinter? _thermalPrinterInstance;

  FlutterThermalPrinter get _thermalPrinter {
    _thermalPrinterInstance ??= FlutterThermalPrinter.instance;
    return _thermalPrinterInstance!;
  }

  List<Printer> _availablePrinters = [];
  Printer? _connectedReceiptPrinter;
  Printer? _connectedKdsPrinter;
  PrinterConfig _config = const PrinterConfig();
  bool _isScanning = false;
  Ref? _ref; // Store ref for accessing providers
  // Kept so settings can still be read when [_ref] is missing or stale — see
  // [_customTicketText].
  SharedPreferences? _prefs;

  // Per-station printer routing (SharedPrefs-persisted, survives DB sync).
  List<NamedPrinter> _printerPool = [];
  // stationId -> the NamedPrinter.id(s) this station's ticket goes to. A list
  // rather than a single id so one station can fan the SAME ticket out to
  // several printers. Empty/absent = fall back to the global KDS printer;
  // `[kNoPrinterAssignment]` = print nowhere.
  Map<int, List<String>> _stationAssignments = {};
  // stationId -> what its ticket shows. Absent = the default rule, so a shop
  // that never opens this screen behaves exactly as it always has.
  Map<int, StationTicketRule> _stationRules = {};

  final _poolController = StreamController<List<NamedPrinter>>.broadcast();
  final _assignmentsController =
      StreamController<Map<int, List<String>>>.broadcast();

  // Stream controllers
  final _printersController = StreamController<List<Printer>>.broadcast();
  final _scanningController = StreamController<bool>.broadcast();
  final _configController = StreamController<PrinterConfig>.broadcast();
  final _printingStatusController = StreamController<String?>.broadcast();

  bool _isPrintingInProgress = false;

  // ---------------------------------------------------------------------------
  // Print queue
  // ---------------------------------------------------------------------------
  //
  // Every public print entry point runs through [_enqueue] -> [SerialJobQueue],
  // which chains jobs onto a single slot so only one ticket is ever being built
  // and dispatched at a time. The queue's own re-entrancy and failure-isolation
  // rules are covered by test/serial_job_queue_test.dart.
  //
  // This exists because [PrintingService] is a singleton (`printingServiceProvider`
  // is a plain `Provider`) shared by TWO independent producers: the cashier's UI
  // and the LAN server's waiter-order handler, which fires its prints unawaited
  // (`server_service.dart` `_firePrintsForWaiterOrder`). Before the queue, a
  // waiter POST landing while the cashier tapped Continue put two jobs on one
  // printer at once:
  //
  //   * NETWORK — thermal printers accept ONE connection on :9100, so the
  //     second connect is refused and burns the 3-attempt backoff in
  //     [_sendBytesOverTcp] before giving up.
  //   * USB/BLE — concurrent `printData` on one handle hits the 10s timeout,
  //     which then calls [_invalidateCachedPrinter], so the NEXT print pays the
  //     `startScan()` + 4s rescan in [_ensurePrinterConnected] too.
  //
  // Both look to the cashier like "printing randomly takes forever". Serialising
  // removes the collision that the retries were there to paper over.
  //
  // The slot is held for a WHOLE job, not per byte-dispatch: a multi-station KDS
  // ticket must not interleave its sections with another order's, and a job's
  // `_ensurePrinterConnected` -> build -> `_dispatchBytes` sequence has to see a
  // stable cached printer handle (with a `kdsOverride` in play that handle is
  // swapped per station, so an interleaved job would dispatch to the wrong
  // physical printer).
  final SerialJobQueue _printQueue = SerialJobQueue();

  /// How many prints are waiting for the printer, including the one running.
  /// Surfaced so the UI can show a non-blocking "N prints pending" indicator
  /// instead of a modal overlay.
  Stream<int> get printQueueDepthStream => _printQueue.depthStream;

  int get printQueueDepth => _printQueue.depth;

  /// Run [job] on the print queue, or inline when already on it.
  Future<T> _enqueue<T>(Future<T> Function() job) => _printQueue.add(job);

  // ---------------------------------------------------------------------------
  // Print failure alerts
  // ---------------------------------------------------------------------------
  //
  // Prints are fired detached now, so the blocking overlay that used to double
  // as the error channel is gone. Without somewhere for a failure to land, a
  // dead printer would mean the kitchen silently gets nothing — the one real
  // regression risk in moving printing off the critical path.
  //
  // Reported from the two choke points every print funnels through
  // ([_ensurePrinterConnected] and [_dispatchBytes]) rather than from each of
  // the 18 entry points, so nothing can fail without being counted.
  //
  // Deliberately NOT auto-cleared on a later success: a KDS job can succeed for
  // one station and fail for another, and "the kitchen never got table 6's food"
  // must not be erased by the next ticket that happens to print. The cashier
  // dismisses it.
  PrintAlert? _printAlert;
  final _printAlertController = StreamController<PrintAlert?>.broadcast();

  Stream<PrintAlert?> get printAlertStream => _printAlertController.stream;

  PrintAlert? get printAlert => _printAlert;

  /// Acknowledge the outstanding print failure(s).
  void clearPrintAlert() {
    if (_printAlert == null) return;
    _printAlert = null;
    _printAlertController.add(null);
  }

  void _recordPrintFailure(String reason) {
    _printAlert = PrintAlert(
      reason: reason,
      at: DateTime.now(),
      count: (_printAlert?.count ?? 0) + 1,
    );
    _printAlertController.add(_printAlert);
    debugPrint('Print failure recorded: $reason');
  }

  /// Test seams: when set, tickets go here instead of to a printer, and the
  /// catalogue is read from [databaseForTesting] when there is no ref.
  @visibleForTesting
  void Function(PrinterPurpose purpose, List<int> bytes)? dispatchForTesting;
  @visibleForTesting
  AppDatabase? databaseForTesting;

  AppDatabase? get _catalogueDatabase =>
      _ref?.read(databaseProvider) ?? databaseForTesting;

  /// [_ensurePrinterConnectedRaw] plus failure reporting.
  Future<bool> _ensurePrinterConnected(PrinterPurpose purpose,
      {_KdsTarget? kdsOverride}) async {
    if (dispatchForTesting != null) return true;
    final ok = await _ensurePrinterConnectedRaw(purpose, kdsOverride: kdsOverride);
    if (!ok) {
      final name = kdsOverride?.name ??
          (purpose == PrinterPurpose.receipt
              ? _config.receiptPrinterName
              : _config.kdsPrinterName);
      _recordPrintFailure(
        purpose == PrinterPurpose.receipt
            ? 'Receipt printer unreachable${name == null ? '' : ' ($name)'}'
            : 'Kitchen printer unreachable${name == null ? '' : ' ($name)'}',
      );
    }
    return ok;
  }

  /// [_dispatchBytesRaw] plus failure reporting.
  Future<bool> _dispatchBytes(PrinterPurpose purpose, List<int> bytes,
      {_KdsTarget? kdsOverride}) async {
    if (dispatchForTesting != null) {
      dispatchForTesting!(purpose, bytes);
      return true;
    }
    final ok =
        await _dispatchBytesRaw(purpose, bytes, kdsOverride: kdsOverride);
    // Empty-byte sends are reachability probes (connectPrinter /
    // testNetworkReachable), not tickets. A failed probe is already reported by
    // the connect path above, so counting it here would double-report.
    if (!ok && bytes.isNotEmpty) {
      final name = kdsOverride?.name ??
          (purpose == PrinterPurpose.receipt
              ? _config.receiptPrinterName
              : _config.kdsPrinterName);
      _recordPrintFailure(
        purpose == PrinterPurpose.receipt
            ? 'Receipt did not print${name == null ? '' : ' ($name)'}'
            : 'Kitchen ticket did not print${name == null ? '' : ' ($name)'}',
      );
    }
    return ok;
  }

  // Getters
  List<Printer> get availablePrinters => _availablePrinters;

  Printer? get connectedReceiptPrinter => _connectedReceiptPrinter;

  Printer? get connectedKdsPrinter => _connectedKdsPrinter;

  PrinterConfig get config => _config;

  bool get isScanning => _isScanning;

  bool get isPrintingInProgress => _isPrintingInProgress;

  Stream<List<Printer>> get printersStream => _printersController.stream;

  Stream<bool> get scanningStream => _scanningController.stream;

  Stream<PrinterConfig> get configStream => _configController.stream;

  /// Read-only view of the named-printer pool the cashier has configured.
  List<NamedPrinter> get printerPool => List.unmodifiable(_printerPool);

  /// stationId -> NamedPrinter.ids. Stations missing from this map fall back
  /// to the global KDS printer at print time; more than one id means the same
  /// station ticket is printed on every one of them.
  Map<int, List<String>> get stationAssignments => Map.unmodifiable({
        for (final e in _stationAssignments.entries)
          e.key: List<String>.unmodifiable(e.value),
      });

  /// stationId -> its ticket rule. Stations missing from this map use the
  /// default ([StationTicketScope.ownItems], not private).
  Map<int, StationTicketRule> get stationRules =>
      Map.unmodifiable(_stationRules);

  /// The rule in force for a station, defaults included.
  StationTicketRule ruleForStation(int? stationId) =>
      (stationId == null ? null : _stationRules[stationId]) ??
      const StationTicketRule();

  Stream<List<NamedPrinter>> get printerPoolStream => _poolController.stream;
  Stream<Map<int, List<String>>> get stationAssignmentsStream =>
      _assignmentsController.stream;

  /// Stream of printing status messages (null = idle, non-null = status text shown in overlay)
  Stream<String?> get printingStatusStream => _printingStatusController.stream;

  /// Initialize the printing service
  Future<void> initialize(SharedPreferences prefs, Ref ref) async {
    _ref = ref; // Store the ref
    _prefs = prefs;

    // Load saved configuration
    await _loadConfig(prefs);
    _loadStationRouting(prefs);

    // Listen to printer stream - wrapped in try-catch for platforms
    // where thermal printer may not be fully supported
    try {
      _thermalPrinter.devicesStream.listen(
        (printerList) {
          _availablePrinters = printerList;
          _printersController.add(printerList);
        },
        onError: (e) {
          debugPrint('Printer stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('⚠️ Failed to listen to printer stream: $e');
    }

    // Pre-warm printer connections in the background so the FIRST order prints
    // immediately instead of triggering a scan mid-order. See [_prewarmPrinters].
    // ignore: unawaited_futures
    _prewarmPrinters();
  }

  /// Connect the saved receipt / KDS printers at startup so the first order
  /// doesn't pay for a device scan.
  ///
  /// USB/BLE printers can't be connected from the saved address alone — the
  /// plugin needs a one-time device enumeration to get a connectable handle —
  /// so we run that scan now, at boot (off the print path, no "Scanning..."
  /// overlay), and connect. NETWORK printers skip the scan entirely (they
  /// connect straight from the saved address).
  ///
  /// Fully best-effort: if the printer is off or this fails, the first print
  /// just falls back to the existing scan-then-connect path.
  Future<void> _prewarmPrinters() async {
    try {
      final receiptNeedsScan = _config.receiptPrinterAddress != null &&
          _config.receiptConnectionType != ConnectionType.NETWORK;
      final kdsNeedsScan = _config.kdsEnabled &&
          _config.kdsPrinterAddress != null &&
          _config.kdsConnectionType != ConnectionType.NETWORK;

      // One enumeration fills `_availablePrinters` (via the devices stream).
      // `startScan` only drives the scanning stream — it never touches the
      // print-status overlay — so nothing flashes on screen during boot.
      if (receiptNeedsScan || kdsNeedsScan) {
        await startScan();
      }

      Future<void> connect(
        PrinterPurpose purpose,
        String? address,
        ConnectionType? type,
        String? name,
      ) async {
        if (address == null || type == null) return;
        if (type == ConnectionType.NETWORK) {
          await connectPrinter(
            Printer(
              name: name ?? 'Network printer',
              address: address,
              connectionType: ConnectionType.NETWORK,
              isConnected: false,
            ),
            purpose,
          );
          return;
        }
        final p = _findPrinterByAddress(address);
        if (p != null) await connectPrinter(p, purpose);
      }

      await connect(
        PrinterPurpose.receipt,
        _config.receiptPrinterAddress,
        _config.receiptConnectionType,
        _config.receiptPrinterName,
      );
      if (_config.kdsEnabled) {
        await connect(
          PrinterPurpose.kds,
          _config.kdsPrinterAddress,
          _config.kdsConnectionType,
          _config.kdsPrinterName,
        );
      }
    } catch (e) {
      debugPrint('Printer prewarm failed (non-fatal): $e');
    }
  }

  /// Load configuration from SharedPreferences
  Future<void> _loadConfig(SharedPreferences prefs) async {
    final receiptAddress = prefs.getString('printer_receipt_address');
    final receiptName = prefs.getString('printer_receipt_name');
    final receiptType = prefs.getInt('printer_receipt_type');
    final kdsAddress = prefs.getString('printer_kds_address');
    final kdsName = prefs.getString('printer_kds_name');
    final kdsType = prefs.getInt('printer_kds_type');
    final kdsEnabled = prefs.getBool('printer_kds_enabled') ?? true;
    final printingEnabled = prefs.getBool('printer_printing_enabled') ?? true;
    final paperSizeValue = prefs.getInt('printer_paper_size') ?? 80;
    final textSizeValue = prefs.getInt('printer_text_size') ?? 1;
    final printingLanguage = prefs.getString('printer_language') ?? 'en';

    PrintRule loadRule(String key, {bool defaultEnabled = true}) {
      final raw = prefs.getString(key);
      if (raw == null) return PrintRule(enabled: defaultEnabled);
      try {
        return PrintRule.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {
        return PrintRule(enabled: defaultEnabled);
      }
    }

    final defaultKdsModeIndex = prefs.getInt('printer_default_kds_mode');

    _config = PrinterConfig(
      receiptPrinterAddress: receiptAddress,
      receiptPrinterName: receiptName,
      receiptConnectionType: receiptType != null
          ? ConnectionType.values[receiptType]
          : null,
      kdsPrinterAddress: kdsAddress,
      kdsPrinterName: kdsName,
      kdsConnectionType: kdsType != null
          ? ConnectionType.values[kdsType]
          : null,
      kdsEnabled: kdsEnabled,
      printingEnabled: printingEnabled,
      // Accept the human width (58) and the legacy internal value (mm58.value
      // == 1) that older builds mistakenly persisted, so 58mm installs recover
      // without a manual re-toggle. Everything else => 80mm.
      paperSize: (paperSizeValue == 58 || paperSizeValue == 1)
          ? PaperSize.mm58
          : PaperSize.mm80,
      textSize: textSizeValue,
      printingLanguage: printingLanguage,
      orderTicketRule:
          loadRule('printer_rule_order_ticket', defaultEnabled: false),
      customerReceiptRule: loadRule('printer_rule_customer_receipt'),
      storeCopyRule:
          loadRule('printer_rule_store_copy', defaultEnabled: false),
      kdsRule: loadRule('printer_rule_kds'),
      autoPrintOnPayment:
          prefs.getBool('printer_auto_print_payment') ?? true,
      customerCopies: prefs.getInt('printer_customer_copies') ?? 1,
      reprintWatermark: prefs.getBool('printer_reprint_watermark') ?? true,
      cashDrawerKick: prefs.getBool('printer_cash_drawer_kick') ?? false,
      cashDrawerCashOnly:
          prefs.getBool('printer_cash_drawer_cash_only') ?? true,
      splitKdsByStation:
          prefs.getBool('printer_split_kds_by_station') ?? true,
      printKdsUnassigned:
          prefs.getBool('printer_print_kds_unassigned') ?? true,
      defaultKdsMode: defaultKdsModeIndex != null
          ? KdsPrintMode.values[defaultKdsModeIndex]
          : KdsPrintMode.modificationsOnly,
      consolidateKdsJob:
          prefs.getBool('printer_consolidate_kds_job') ?? true,
      kdsFullOrderMode:
          prefs.getBool('printer_kds_full_order_mode') ?? false,
      kdsCopies: (prefs.getInt('printer_kds_copies') ?? 1).clamp(1, 9),
      printLinkedComponents:
          prefs.getBool('printer_print_linked_components') ?? true,
      linkedComponentLabel: LinkedComponentLabel.values[
          (prefs.getInt('printer_linked_component_label') ??
                  LinkedComponentLabel.component.index)
              .clamp(0, LinkedComponentLabel.values.length - 1)],
      ticketFields:
          PrinterConfig.parseTicketFields(prefs.getString('printer_ticket_fields')),
      ticketFieldSizes: PrinterConfig.parseTicketFieldSizes(
          prefs.getString('printer_ticket_field_sizes')),
      ticketFieldOrder: PrinterConfig.parseTicketFieldOrder(
          prefs.getString('printer_ticket_field_order')),
      logoCropLeft: prefs.getDouble('printer_logo_crop_l') ?? 0.0,
      logoCropTop: prefs.getDouble('printer_logo_crop_t') ?? 0.0,
      logoCropRight: prefs.getDouble('printer_logo_crop_r') ?? 1.0,
      logoCropBottom: prefs.getDouble('printer_logo_crop_b') ?? 1.0,
      logoWidthPercent:
          (prefs.getInt('printer_logo_width_percent') ?? 100).clamp(10, 100),
      logoAlign: LogoAlign.values[
          (prefs.getInt('printer_logo_align') ?? LogoAlign.center.index)
              .clamp(0, LogoAlign.values.length - 1)],
    );
    _configController.add(_config);
  }

  /// Save configuration to SharedPreferences
  Future<void> saveConfig(
    SharedPreferences prefs,
    PrinterConfig newConfig,
  ) async {
    _config = newConfig;
    _prefs = prefs;

    if (newConfig.receiptPrinterAddress != null) {
      await prefs.setString(
        'printer_receipt_address',
        newConfig.receiptPrinterAddress!,
      );
    } else {
      await prefs.remove('printer_receipt_address');
    }

    if (newConfig.receiptPrinterName != null) {
      await prefs.setString(
        'printer_receipt_name',
        newConfig.receiptPrinterName!,
      );
    } else {
      await prefs.remove('printer_receipt_name');
    }

    if (newConfig.receiptConnectionType != null) {
      await prefs.setInt(
        'printer_receipt_type',
        newConfig.receiptConnectionType!.index,
      );
    } else {
      await prefs.remove('printer_receipt_type');
    }

    if (newConfig.kdsPrinterAddress != null) {
      await prefs.setString(
        'printer_kds_address',
        newConfig.kdsPrinterAddress!,
      );
    } else {
      await prefs.remove('printer_kds_address');
    }

    if (newConfig.kdsPrinterName != null) {
      await prefs.setString('printer_kds_name', newConfig.kdsPrinterName!);
    } else {
      await prefs.remove('printer_kds_name');
    }

    if (newConfig.kdsConnectionType != null) {
      await prefs.setInt(
        'printer_kds_type',
        newConfig.kdsConnectionType!.index,
      );
    } else {
      await prefs.remove('printer_kds_type');
    }

    await prefs.setBool('printer_kds_enabled', newConfig.kdsEnabled);
    await prefs.setBool('printer_printing_enabled', newConfig.printingEnabled);
    // Persist the HUMAN width (58 / 80), NOT `PaperSize.value` (which is the
    // package's internal index: mm58=1, mm72=2, mm80=3). `_loadConfig` /
    // `fromJson` read this back by comparing to `58`, so storing `.value`
    // here meant the comparison never matched and the size silently reverted
    // to 80mm on every restart — a 58mm printer then received 80mm-wide
    // (48-col) lines and squeezed them, producing the "compressed" ticket.
    await prefs.setInt('printer_paper_size',
        newConfig.paperSize == PaperSize.mm58 ? 58 : 80);
    await prefs.setInt('printer_text_size', newConfig.textSize);
    await prefs.setString('printer_language', newConfig.printingLanguage);

    // Per-output conditional rules
    await prefs.setString(
        'printer_rule_order_ticket', jsonEncode(newConfig.orderTicketRule.toJson()));
    await prefs.setString('printer_rule_customer_receipt',
        jsonEncode(newConfig.customerReceiptRule.toJson()));
    await prefs.setString(
        'printer_rule_store_copy', jsonEncode(newConfig.storeCopyRule.toJson()));
    await prefs.setString(
        'printer_rule_kds', jsonEncode(newConfig.kdsRule.toJson()));

    // Pro configuration
    await prefs.setBool(
        'printer_auto_print_payment', newConfig.autoPrintOnPayment);
    await prefs.setInt('printer_customer_copies', newConfig.customerCopies);
    await prefs.setBool(
        'printer_reprint_watermark', newConfig.reprintWatermark);
    await prefs.setBool('printer_cash_drawer_kick', newConfig.cashDrawerKick);
    await prefs.setBool(
        'printer_cash_drawer_cash_only', newConfig.cashDrawerCashOnly);
    await prefs.setBool(
        'printer_split_kds_by_station', newConfig.splitKdsByStation);
    await prefs.setBool(
        'printer_print_kds_unassigned', newConfig.printKdsUnassigned);
    await prefs.setInt(
        'printer_default_kds_mode', newConfig.defaultKdsMode.index);
    await prefs.setBool(
        'printer_consolidate_kds_job', newConfig.consolidateKdsJob);
    await prefs.setBool(
        'printer_kds_full_order_mode', newConfig.kdsFullOrderMode);
    await prefs.setInt('printer_kds_copies', newConfig.kdsCopies);
    await prefs.setBool(
        'printer_print_linked_components', newConfig.printLinkedComponents);
    await prefs.setInt('printer_linked_component_label',
        newConfig.linkedComponentLabel.index);
    await prefs.setString(
        'printer_ticket_fields', jsonEncode(newConfig.ticketFields));
    await prefs.setString(
        'printer_ticket_field_sizes', jsonEncode(newConfig.ticketFieldSizes));
    await prefs.setString(
        'printer_ticket_field_order', jsonEncode(newConfig.ticketFieldOrder));
    await prefs.setDouble('printer_logo_crop_l', newConfig.logoCropLeft);
    await prefs.setDouble('printer_logo_crop_t', newConfig.logoCropTop);
    await prefs.setDouble('printer_logo_crop_r', newConfig.logoCropRight);
    await prefs.setDouble('printer_logo_crop_b', newConfig.logoCropBottom);
    await prefs.setInt(
        'printer_logo_width_percent', newConfig.logoWidthPercent);
    await prefs.setInt('printer_logo_align', newConfig.logoAlign.index);

    _configController.add(_config);
  }

  /// Load the printer pool + station→printer assignments from SharedPrefs.
  /// Both are stored as JSON blobs (one key each) — see [_kPrefsPrinterPool]
  /// and [_kPrefsStationAssignments]. Missing/malformed data resets to empty,
  /// so a fresh install or a wiped key behaves exactly like today (the
  /// fallback to the global KDS printer kicks in for every station).
  void _loadStationRouting(SharedPreferences prefs) {
    _printerPool = [];
    _stationAssignments = {};

    final rawPool = prefs.getString(_kPrefsPrinterPool);
    if (rawPool != null && rawPool.isNotEmpty) {
      try {
        final list = jsonDecode(rawPool) as List<dynamic>;
        _printerPool = list
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => NamedPrinter.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      } catch (e) {
        debugPrint('Failed to decode printer pool: $e');
      }
    }

    final rawAssignments = prefs.getString(_kPrefsStationAssignments);
    if (rawAssignments != null && rawAssignments.isNotEmpty) {
      try {
        final map = jsonDecode(rawAssignments) as Map<dynamic, dynamic>;
        // Self-migrating: the pre-fan-out format stored a bare printer id per
        // station. Read either shape, always write the list one back.
        _stationAssignments = {
          for (final e in map.entries)
            int.parse(e.key.toString()): e.value is List
                ? (e.value as List)
                    .map((v) => v.toString())
                    .where((v) => v.isNotEmpty)
                    .toList()
                : <String>[e.value.toString()],
        }..removeWhere((_, ids) => ids.isEmpty);
      } catch (e) {
        debugPrint('Failed to decode station assignments: $e');
      }
    }

    final rawRules = prefs.getString(_kPrefsStationRules);
    if (rawRules != null && rawRules.isNotEmpty) {
      try {
        final map = jsonDecode(rawRules) as Map<dynamic, dynamic>;
        _stationRules = {
          for (final e in map.entries)
            if (e.value is Map)
              int.parse(e.key.toString()):
                  StationTicketRule.fromJson(Map<String, dynamic>.from(
                      e.value as Map<dynamic, dynamic>)),
        };
      } catch (e) {
        // A malformed blob resets to defaults rather than throwing: every
        // station printing its own items is a working kitchen, and refusing
        // to start the printer over a bad pref is not.
        debugPrint('Failed to decode station rules: $e');
        _stationRules = {};
      }
    }

    _poolController.add(printerPool);
    _assignmentsController.add(stationAssignments);
  }

  /// Persist the per-station ticket rules. Default rules are dropped rather
  /// than stored, so the blob stays small and "unconfigured" is a plain
  /// absence.
  Future<void> saveStationRules(
    SharedPreferences prefs,
    Map<int, StationTicketRule> rules,
  ) async {
    _stationRules = {
      for (final e in rules.entries)
        if (!e.value.isDefault) e.key: e.value,
    };
    await prefs.setString(
      _kPrefsStationRules,
      jsonEncode(
        _stationRules.map((k, v) => MapEntry(k.toString(), v.toJson())),
      ),
    );
    _assignmentsController.add(stationAssignments);
  }

  /// Persist the named-printer pool. Also strips any station assignment that
  /// references a removed printer id — keeps the two structures consistent
  /// without forcing the caller to do it.
  Future<void> savePrinterPool(
    SharedPreferences prefs,
    List<NamedPrinter> pool,
  ) async {
    _printerPool = List.of(pool);
    final encoded = jsonEncode(_printerPool.map((p) => p.toJson()).toList());
    await prefs.setString(_kPrefsPrinterPool, encoded);
    _poolController.add(printerPool);

    final validIds = _printerPool.map((p) => p.id).toSet();
    final pruned = <int, List<String>>{};
    var changed = false;
    for (final entry in _stationAssignments.entries) {
      // The "don't print" sentinel is not a pool id — keep it, or saving the
      // pool would silently un-silence every silenced station.
      final kept = entry.value
          .where((id) => id == kNoPrinterAssignment || validIds.contains(id))
          .toList();
      if (kept.length != entry.value.length) changed = true;
      if (kept.isNotEmpty) pruned[entry.key] = kept;
    }
    if (changed) {
      await saveStationAssignments(prefs, pruned);
    }
  }

  /// Persist the station→printer(s) map. Entries with an empty list are
  /// dropped, so "unassigned" is stored as absent rather than as an empty
  /// list — keeps the fallback-to-global-KDS check a plain null test.
  Future<void> saveStationAssignments(
    SharedPreferences prefs,
    Map<int, List<String>> assignments,
  ) async {
    _stationAssignments = {
      for (final e in assignments.entries)
        if (e.value.isNotEmpty) e.key: List<String>.of(e.value),
    };
    final encoded = jsonEncode(
      _stationAssignments.map((k, v) => MapEntry(k.toString(), v)),
    );
    await prefs.setString(_kPrefsStationAssignments, encoded);
    _assignmentsController.add(stationAssignments);
  }

  /// True when the cashier assigned "No printer (KDS only)" to this station —
  /// its items must be skipped by every kitchen-print path.
  bool isStationSilenced(int? stationId) =>
      stationId != null &&
      (_stationAssignments[stationId]?.contains(kNoPrinterAssignment) ?? false);

  /// Resolve which physical printer(s) a given station's items should go to.
  /// An EMPTY list means "use the default global KDS printer" — covers a
  /// null stationId (no station on the product), an unassigned station, and a
  /// station whose every mapping points at a now-deleted pool entry.
  ///
  /// More than one entry means the station's ticket is printed on each of
  /// them. Deduped by address so two pool entries naming the same device
  /// don't produce two identical tickets on it.
  List<_KdsTarget> _resolveTargetsForStation(int? stationId) {
    if (stationId == null) return const [];
    final printerIds = _stationAssignments[stationId];
    if (printerIds == null || printerIds.isEmpty) return const [];

    final byAddress = <String, _KdsTarget>{};
    for (final printerId in printerIds) {
      // Silenced stations are skipped before resolution (see the grouping
      // loop); guard anyway so the sentinel can never reach a pool lookup.
      if (printerId == kNoPrinterAssignment) continue;
      NamedPrinter? match;
      for (final p in _printerPool) {
        if (p.id == printerId) {
          match = p;
          break;
        }
      }
      if (match == null) continue;
      final printer = match;
      byAddress.putIfAbsent(
        printer.address,
        () => _KdsTarget(
          address: printer.address,
          name: printer.name.isNotEmpty ? printer.name : printer.label,
          type: printer.connectionType,
        ),
      );
    }
    return byAddress.values.toList();
  }

  /// Returns only the items whose product is assigned to at least one station
  /// (primary `stationId` or a `product_stations` row). Used to drop stationless
  /// items from the KDS when `printKdsUnassigned` is off.
  Future<List<OrderItem>> _itemsWithStationOnly(
      AppDatabase database, List<OrderItem> items) async {
    final result = <OrderItem>[];
    for (final item in items) {
      final product = await (database.select(database.products)
            ..where((t) => t.id.equals(item.productId)))
          .getSingleOrNull();
      if (product?.stationId != null) {
        result.add(item);
        continue;
      }
      final extra = await (database.select(database.productStations)
            ..where((t) => t.productId.equals(item.productId)))
          .get();
      if (extra.isNotEmpty) result.add(item);
    }
    return result;
  }

  /// Drops items whose EVERY station is assigned "No printer (KDS only)".
  /// An item with no station at all is kept (that case is governed by
  /// `printKdsUnassigned`), and a multi-station item prints as long as at
  /// least one of its stations still has a printer.
  Future<List<OrderItem>> _dropSilencedItems(
      AppDatabase database, List<OrderItem> items) async {
    // Fast path: nothing silenced → nothing to do.
    if (!_stationAssignments.values
        .any((ids) => ids.contains(kNoPrinterAssignment))) {
      return items;
    }
    final result = <OrderItem>[];
    for (final item in items) {
      final product = await (database.select(database.products)
            ..where((t) => t.id.equals(item.productId)))
          .getSingleOrNull();
      final stationIds = <int>{
        if (product?.stationId != null) product!.stationId!,
      };
      final extra = await (database.select(database.productStations)
            ..where((t) => t.productId.equals(item.productId)))
          .get();
      stationIds.addAll(extra.map((e) => e.stationId));

      if (stationIds.isEmpty) {
        result.add(item); // stationless — not this setting's concern
        continue;
      }
      final anyPrints = stationIds.any((id) => !isStationSilenced(id));
      if (anyPrints) result.add(item);
    }
    return result;
  }

  /// Start scanning for printers
  Future<void> startScan() async {
    if (_isScanning) return;

    _isScanning = true;
    _scanningController.add(true);

    try {
      await _thermalPrinter.getPrinters(
        connectionTypes: [ConnectionType.USB, ConnectionType.NETWORK],
      );

      // Wait for results
      await Future.delayed(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Error scanning for printers: $e');
    } finally {
      _isScanning = false;
      _scanningController.add(false);
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    try {
      await _thermalPrinter.stopScan();
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    } finally {
      _isScanning = false;
      _scanningController.add(false);
    }
  }

  /// Connect to a printer for a specific purpose.
  ///
  /// For [ConnectionType.NETWORK] we bypass `flutter_thermal_printer` entirely
  /// (it has no NETWORK implementation in 2.0.0) and do a one-shot reachability
  /// check via [_sendBytesOverTcp]. Subsequent prints open a fresh socket.
  Future<bool> connectPrinter(Printer printer, PrinterPurpose purpose) async {
    try {
      debugPrint(
        'Attempting to connect to ${purpose.name} printer: ${printer.name} (${printer.address})',
      );

      if (printer.connectionType == ConnectionType.NETWORK) {
        final reachable = await _sendBytesOverTcp(
          printer.address ?? '',
          const <int>[],
          timeout: const Duration(seconds: 2),
        );
        if (!reachable) {
          debugPrint('Network printer ${printer.address} not reachable');
          return false;
        }
        if (purpose == PrinterPurpose.receipt) {
          _connectedReceiptPrinter = printer;
        } else {
          _connectedKdsPrinter = printer;
        }
        return true;
      }

      final result = await _thermalPrinter.connect(printer);

      debugPrint('Connection result: $result');

      if (purpose == PrinterPurpose.receipt) {
        _connectedReceiptPrinter = printer;
        debugPrint('Receipt printer connected successfully');
      } else {
        _connectedKdsPrinter = printer;
        debugPrint('KDS printer connected successfully');
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint('Error connecting to ${purpose.name} printer: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Disconnect a printer
  Future<void> disconnectPrinter(PrinterPurpose purpose) async {
    try {
      if (purpose == PrinterPurpose.receipt &&
          _connectedReceiptPrinter != null) {
        if (_connectedReceiptPrinter!.connectionType !=
            ConnectionType.NETWORK) {
          await _thermalPrinter.disconnect(_connectedReceiptPrinter!);
        }
        _connectedReceiptPrinter = null;
      } else if (purpose == PrinterPurpose.kds &&
          _connectedKdsPrinter != null) {
        if (_connectedKdsPrinter!.connectionType != ConnectionType.NETWORK) {
          await _thermalPrinter.disconnect(_connectedKdsPrinter!);
        }
        _connectedKdsPrinter = null;
      }
    } catch (e) {
      debugPrint('Error disconnecting printer: $e');
    }
  }

  /// Open a one-shot TCP connection to `host:port` (port defaults to 9100) and
  /// write [bytes]. Returns `true` on a clean send. Used for any printer slot
  /// whose [ConnectionType] is [ConnectionType.NETWORK].
  Future<bool> _sendBytesOverTcp(
    String address,
    List<int> bytes, {
    Duration timeout = const Duration(seconds: 5),
    int maxAttempts = 3,
  }) async {
    if (address.isEmpty) return false;
    final parts = address.split(':');
    final host = parts[0];
    final port = parts.length > 1
        ? int.tryParse(parts[1]) ?? 9100
        : 9100;

    // CRITICAL: only the CONNECT phase is retried. Printing is NOT idempotent —
    // once we've started writing bytes, the printer may have already received
    // (and printed) the whole job even if flush/close then throws (e.g. the
    // printer resets the connection right after ingesting). Retrying at that
    // point would double-print. So a write/flush/close failure returns false
    // WITHOUT another attempt; only a failure to establish the connection (when
    // nothing has been sent yet) is safe to retry.
    //
    // The retry matters because most network thermal printers accept only ONE
    // connection at a time on :9100: rapid back-to-back tickets (adding items
    // one after another to the KDS) can hit "connection refused / timeout"
    // while the printer is still draining the previous socket. A short, growing
    // backoff lets it free its single slot instead of dropping the ticket —
    // the "after 5-6 items it stops printing" symptom.
    //
    // Empty-byte sends are reachability probes (connectPrinter /
    // testNetworkReachable) — a single connect attempt so a "test connection"
    // on an offline printer fails fast instead of stalling on the backoffs.
    final attempts = bytes.isEmpty ? 1 : maxAttempts;
    Socket? sock;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        sock = await Socket.connect(host, port, timeout: timeout);
        break; // connected — leave the retry loop, do NOT retry past this point
      } catch (e) {
        // Connect failed and nothing was sent → safe to retry.
        debugPrint(
            'TCP connect to $host:$port failed (attempt $attempt/$attempts): $e');
        if (attempt < attempts) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    if (sock == null) return false; // never connected

    // Connected: send once. Any failure here is terminal (no retry) because the
    // job may already be at the printer.
    try {
      // Push the job out immediately instead of letting Nagle coalesce it.
      try {
        sock.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}
      if (bytes.isNotEmpty) {
        sock.add(bytes);
        await sock.flush();
        // Let the printer ingest the buffer before we tear the socket down.
        // Some cheap network printers drop the tail of a job if the connection
        // closes the instant after flush.
        await Future.delayed(const Duration(milliseconds: 150));
      }
      await sock.close();
      return true;
    } catch (e) {
      debugPrint('TCP send to $host:$port failed after connect (no retry): $e');
      try {
        sock.destroy();
      } catch (_) {}
      return false;
    }
  }

  /// Single dispatch point for byte sends — branches on the slot's connection
  /// type so callers don't have to know whether the printer is USB/BLE
  /// (plugin-managed) or NETWORK (TCP socket).
  ///
  /// Returns `true` only when the bytes were actually accepted by the
  /// transport. **All callers must honour this** — in particular, callers
  /// that mark items as printed in the DB (e.g. KDS in
  /// `KdsPrintMode.modificationsOnly`) must skip the mark when this returns
  /// false, otherwise a single transient failure permanently swallows the
  /// kitchen ticket.
  Future<bool> _dispatchBytesRaw(
      PrinterPurpose purpose, List<int> bytes,
      {_KdsTarget? kdsOverride}) async {
    // Per-station override (only meaningful when purpose == kds) wins over
    // the global _config. Used by the per-station routing path so a station
    // can hit its own physical printer without us mutating _config.
    final String? address;
    final ConnectionType? type;
    if (purpose == PrinterPurpose.kds && kdsOverride != null) {
      address = kdsOverride.address;
      type = kdsOverride.type;
    } else if (purpose == PrinterPurpose.receipt) {
      address = _config.receiptPrinterAddress;
      type = _config.receiptConnectionType;
    } else {
      address = _config.kdsPrinterAddress;
      type = _config.kdsConnectionType;
    }
    if (address == null || type == null) {
      debugPrint('Dispatch: no printer configured for ${purpose.name}');
      return false;
    }
    if (type == ConnectionType.NETWORK) {
      return _sendBytesOverTcp(address, bytes);
    }
    final printer = purpose == PrinterPurpose.receipt
        ? _connectedReceiptPrinter
        : _connectedKdsPrinter;
    if (printer == null) {
      debugPrint('Dispatch: ${purpose.name} printer not connected');
      return false;
    }
    // The plugin call is fire-and-forget on success, but it CAN throw — and
    // on some platforms it can hang indefinitely (cover open, paper jam,
    // BLE in a weird state). Bound it with a timeout and treat any failure
    // as a real failure rather than a silent success.
    try {
      await _thermalPrinter
          .printData(printer, bytes, longData: true)
          .timeout(const Duration(seconds: 10));
      return true;
    } on TimeoutException catch (e) {
      debugPrint('Dispatch: printData timed out on ${purpose.name}: $e');
      // CRITICAL: drop the cached handle. The plugin's `printer` reference
      // is almost certainly unusable after a timeout (BLE stuck, USB queue
      // full, paper jam mid-cut). If we leave it in place,
      // `_ensurePrinterConnected` will see a non-null cached printer next
      // time and skip the reconnect — so every subsequent print (the
      // customer receipt after a KDS station times out, the user's manual
      // retry from the dialog, everything) hits the same dead handle and
      // also fails. That's the "I can't even print just the receipt"
      // symptom the cashier sees after a partial KDS failure.
      _invalidateCachedPrinter(purpose);
      return false;
    } catch (e, stackTrace) {
      debugPrint(
          'Dispatch: printData failed on ${purpose.name}: $e\n$stackTrace');
      // Same reasoning: a thrown plugin call usually leaves the underlying
      // transport in an unusable state.
      _invalidateCachedPrinter(purpose);
      return false;
    }
  }

  /// Drop the cached `Printer` handle for [purpose] so the next print call
  /// goes through the reconnect path (rescan for USB/BLE, fresh TCP probe
  /// for NETWORK). Cheap and idempotent.
  void _invalidateCachedPrinter(PrinterPurpose purpose) {
    if (purpose == PrinterPurpose.receipt) {
      _connectedReceiptPrinter = null;
    } else {
      _connectedKdsPrinter = null;
    }
  }

  /// Send arbitrary ESC/POS bytes to the receipt or KDS printer. Used by the
  /// "Send raw ESC/POS" debugging dialog in printers management.
  Future<bool> sendRawBytes(PrinterPurpose purpose, List<int> bytes) => _enqueue(() async {
    if (bytes.isEmpty) return false;
    return _dispatchBytes(purpose, bytes);
  });

  /// Probe whether a network printer at `host:port` accepts TCP connections.
  /// Used by the manual-entry dialog to validate an address before saving.
  Future<bool> testNetworkReachable(String address) =>
      _sendBytesOverTcp(address, const <int>[],
          timeout: const Duration(seconds: 3));

  /// Set printer for a purpose (saves to config)
  Future<void> setPrinter(
    SharedPreferences prefs,
    Printer printer,
    PrinterPurpose purpose,
  ) async {
    PrinterConfig newConfig;

    if (purpose == PrinterPurpose.receipt) {
      newConfig = _config.copyWith(
        receiptPrinterAddress: printer.address,
        receiptPrinterName: printer.name,
        receiptConnectionType: printer.connectionType,
      );
    } else {
      newConfig = _config.copyWith(
        kdsPrinterAddress: printer.address,
        kdsPrinterName: printer.name,
        kdsConnectionType: printer.connectionType,
      );
    }

    await saveConfig(prefs, newConfig);
    await connectPrinter(printer, purpose);
  }

  /// Clear printer for a purpose
  Future<void> clearPrinter(
    SharedPreferences prefs,
    PrinterPurpose purpose,
  ) async {
    await disconnectPrinter(purpose);

    PrinterConfig newConfig;
    if (purpose == PrinterPurpose.receipt) {
      newConfig = PrinterConfig(
        kdsPrinterAddress: _config.kdsPrinterAddress,
        kdsPrinterName: _config.kdsPrinterName,
        kdsConnectionType: _config.kdsConnectionType,
        kdsEnabled: _config.kdsEnabled,
        paperSize: _config.paperSize,
        textSize: _config.textSize,
        printingLanguage: _config.printingLanguage,
      );
    } else {
      newConfig = PrinterConfig(
        receiptPrinterAddress: _config.receiptPrinterAddress,
        receiptPrinterName: _config.receiptPrinterName,
        receiptConnectionType: _config.receiptConnectionType,
        kdsEnabled: _config.kdsEnabled,
        paperSize: _config.paperSize,
        textSize: _config.textSize,
        printingLanguage: _config.printingLanguage,
      );
    }

    await saveConfig(prefs, newConfig);
  }

  /// Toggle KDS printing
  Future<void> toggleKds(SharedPreferences prefs, bool enabled) async {
    final newConfig = _config.copyWith(kdsEnabled: enabled);
    await saveConfig(prefs, newConfig);
  }

  /// Toggle printing entirely (master switch)
  Future<void> togglePrinting(SharedPreferences prefs, bool enabled) async {
    final newConfig = _config.copyWith(printingEnabled: enabled);
    await saveConfig(prefs, newConfig);
  }

  /// Map a [PrintOutput] to its configured [PrintRule].
  PrintRule _ruleFor(PrintOutput output) {
    switch (output) {
      case PrintOutput.orderTicket:
        return _config.orderTicketRule;
      case PrintOutput.customerReceipt:
        return _config.customerReceiptRule;
      case PrintOutput.storeCopy:
        return _config.storeCopyRule;
      case PrintOutput.kds:
        return _config.kdsRule;
    }
  }

  /// Whether a given output should auto-print for the given order context.
  ///
  /// [source] is the [Orders.source] column on the order row — typically one
  /// of [kAllOrderSources] (`POS`, `WAITER`, `KIOSK`, `EXTERNAL`). If a
  /// caller has no source recorded, pass `'POS'` (the legacy default) so
  /// existing rules apply.
  bool shouldPrint(
    PrintOutput output, {
    required String orderType,
    required bool hasTable,
    String source = 'POS',
  }) {
    if (!_config.printingEnabled) return false;
    final rule = _ruleFor(output);
    if (!rule.enabled) return false;
    if (!rule.orderTypes.contains(orderType)) return false;
    if (!rule.sources.contains(source)) return false;
    if (rule.requireTable && !hasTable) return false;
    return true;
  }

  /// Send a cash-drawer open pulse via the receipt printer.
  Future<bool> kickCashDrawer() => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) return false;
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      final bytes = generator.drawer();
      return await _dispatchBytes(PrinterPurpose.receipt, bytes);
    } catch (e) {
      debugPrint('Cash drawer kick failed: $e');
      return false;
    }
  });

  /// The delivery fee to put on the ticket being printed right now, or null.
  ///
  /// The fee rides the FIRST cut of an order: divide a delivered order three
  /// ways and the other two tickets must not each add it again. Three call
  /// paths need this rule and each knows "has anything been collected yet?"
  /// in its own terms — prior tickets, amount already paid — so they answer
  /// that and this decides. Mirrors `deliveryFeeToCollect` on the payment
  /// screen and `_ticketDeliveryFee` on the reprint path, which resolve the
  /// same rule from their own data.
  static double? feeForThisTicket(
    double? orderFee, {
    required bool anythingAlreadyPaid,
  }) {
    if (anythingAlreadyPaid) return null;
    if (orderFee == null || orderFee <= 0) return null;
    return orderFee;
  }

  /// Orchestrates all payment-time printing according to [PrinterConfig]:
  /// customer receipt (x copies), store copy, and the cash drawer kick.
  /// Honors the per-output rules and the [autoPrintOnPayment] master switch.
  Future<void> printPaymentDocuments({
    required int ticketId,
    required String ticketNumber,
    required double amount,
    /// See [printTicketReceipt] — the delivery charge, the VAT included in
    /// [amount], and the cash the customer handed over / got back. TVA, cash
    /// given and change are gated per ticket type by the `tva` / `amountGiven`
    /// / `change` content toggles; the delivery fee always prints when set,
    /// because it changes what the customer owes.
    double? deliveryFee,
    double? tvaAmount,
    /// The reduction taken off [amount], and why. Forwarded to
    /// [printTicketReceipt] — this wrapper is the path the payment dialog
    /// takes, so a discount missing here is a discount missing from every
    /// receipt actually handed to a customer.
    double? discountAmount,
    String? discountReason,
    double? amountGiven,
    double? changeDue,
    required String paymentMethod,
    required DateTime createdAt,
    required List<Map<String, dynamic>> items,
    required String orderType,
    required bool hasTable,
    String source = 'POS',
    String? currency,
    String? orderCode,
    String? cashierName,
    /// Who is serving the table, printed beside the cashier. The receipt
    /// builders have no CurrentOrder to read it from, unlike the order and
    /// KDS tickets, so it travels as its own argument. Null / blank prints
    /// nothing, which is what a counter shop wants.
    String? waiterName,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    String? customerName,
    String? customerPhone,
    String? deliveryAddress,
    String? tableName,
    int? numberOfPersons,
  }) => _enqueue(() async {
    if (!_config.printingEnabled || !_config.autoPrintOnPayment) return;

    Future<void> printOne({required bool storeCopy}) {
      return printTicketReceipt(
        ticketId: ticketId,
        ticketNumber: ticketNumber,
        amount: amount,
        deliveryFee: deliveryFee,
        tvaAmount: tvaAmount,
        discountAmount: discountAmount,
        discountReason: discountReason,
        amountGiven: amountGiven,
        changeDue: changeDue,
        paymentMethod: paymentMethod,
        createdAt: createdAt,
        items: items,
        currency: currency,
        orderCode: orderCode,
        cashierName: cashierName,
        waiterName: waiterName,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        customerName: customerName,
        customerPhone: customerPhone,
        deliveryAddress: orderType == 'DELIVERY' ? deliveryAddress : null,
        tableName: tableName,
        numberOfPersons: numberOfPersons,
        orderType: orderType,
        storeCopy: storeCopy,
      );
    }

    // Customer receipt(s)
    if (shouldPrint(PrintOutput.customerReceipt,
        orderType: orderType, hasTable: hasTable, source: source)) {
      final copies = _config.customerCopies < 1 ? 1 : _config.customerCopies;
      for (var i = 0; i < copies; i++) {
        await printOne(storeCopy: false);
      }
    }

    // Store copy
    if (shouldPrint(PrintOutput.storeCopy,
        orderType: orderType, hasTable: hasTable, source: source)) {
      await printOne(storeCopy: true);
    }

    // Cash drawer
    if (_config.cashDrawerKick) {
      final isCash =
          paymentMethod.toUpperCase() == TransactionType.cash.value.toUpperCase();
      if (!_config.cashDrawerCashOnly || isCash) {
        await kickCashDrawer();
      }
    }
  });

  /// Set paper size
  Future<void> setPaperSize(SharedPreferences prefs, PaperSize size) async {
    final newConfig = _config.copyWith(paperSize: size);
    await saveConfig(prefs, newConfig);
  }

  /// Set text size
  Future<void> setTextSize(SharedPreferences prefs, int size) async {
    final newConfig = _config.copyWith(textSize: size);
    await saveConfig(prefs, newConfig);
  }

  /// Set printing language (independent of app language)
  Future<void> setPrintingLanguage(SharedPreferences prefs, String language) async {
    final newConfig = _config.copyWith(printingLanguage: language);
    await saveConfig(prefs, newConfig);
  }

  // ── Text-size resolvers ────────────────────────────────────────────────
  //
  // ESC/POS only ships two real scales — `size1` (1×) and `size2` (2×) —
  // applied independently to width and height. The previous resolvers
  // returned `size1` for "Normal" (tiny on 80mm wide paper) and `size2`
  // for "Large" (doubled, basically headlines) with nothing in between.
  // That's the "small or huge" you saw.
  //
  // The fix is **asymmetric sizing**: `width: size1, height: size2`
  // gives single-column-wide text at 2× height — taller, more legible
  // body text without doubling line consumption. Real-world POS receipts
  // call this the "compact medium" tier. Now we map:
  //
  //   Settings 1 (Normal) → 1× × 1× — dense, compact, like a real receipt
  //   Settings 2 (Large)  → 1× × 2× — taller body, normal column width
  //   Settings 3 (Extra)  → 2× × 2× — full headline scale
  //
  // Headers shift up one tier so they always stand out from body.

  /// Body text width+height. Returns a `(width, height)` record.
  ({PosTextSize width, PosTextSize height}) _bodySize() {
    switch (_config.textSize) {
      case 1:
        return (width: PosTextSize.size1, height: PosTextSize.size1);
      case 2:
        // Taller-only — the missing middle tier that fixes "too small
        // OR too big". Two-pass print head means cells are taller but
        // line consumption stays compact.
        return (width: PosTextSize.size1, height: PosTextSize.size2);
      case 3:
      default:
        return (width: PosTextSize.size2, height: PosTextSize.size2);
    }
  }

  /// Header (store name, section titles, payment totals) — one tier larger
  /// than body so it always reads as emphasis.
  ({PosTextSize width, PosTextSize height}) _headerSize() {
    switch (_config.textSize) {
      case 1:
        return (width: PosTextSize.size1, height: PosTextSize.size2);
      case 2:
        return (width: PosTextSize.size2, height: PosTextSize.size2);
      case 3:
      default:
        return (width: PosTextSize.size2, height: PosTextSize.size2);
    }
  }

  /// Body text dimension. The legacy call pattern was
  ///   `height: _resolveTextSize(), width: _resolveTextSize()`
  /// which forced symmetric scaling and produced the "tiny OR huge"
  /// jump. We keep the function returning the **width** dimension so
  /// callers passing this into both axes still get COMPACT text — exactly
  /// what real-world POS receipts want. New code that wants the
  /// asymmetric tall-body tier should use [_resolveTextHeight] or
  /// [_bodySize] directly.
  PosTextSize _resolveTextSize({bool isHeader = false}) {
    final s = isHeader ? _headerSize() : _bodySize();
    return s.width;
  }

  /// Body height when paired with [_resolveTextSize] for width. Returns
  /// the **height** dimension — for body at Settings=2 this is `size2`
  /// (2× tall), which combined with `width: size1` gives the asymmetric
  /// "compact medium" tier ESC/POS lacks natively.
  PosTextSize _resolveTextHeight({bool isHeader = false}) {
    final s = isHeader ? _headerSize() : _bodySize();
    return s.height;
  }

  /// Legacy header resolver. Returns the **width** dimension for the
  /// same reason as [_resolveTextSize] — symmetric callers get the
  /// compact rendering. The matching height comes from
  /// [_resolveHeaderHeight].
  PosTextSize _resolveHeaderSize() => _headerSize().width;

  /// Header height counterpart to [_resolveHeaderSize].
  PosTextSize _resolveHeaderHeight() => _headerSize().height;

  // ── Per-field sizing ──────────────────────────────────────────────────
  //
  // The global text size sets the whole document's tone; these let one line
  // out of it be bigger than the rest. A cashier who wants the table number
  // readable across the room, or a kitchen that wants the order code visible
  // from the pass, no longer has to scale up the entire ticket to get it.
  //
  // A field with no pinned tier resolves exactly as it did before — the same
  // `_bodySize()` / `_headerSize()` it always used — so a config that has
  // never been touched prints byte-identical paper.

  ({PosTextSize width, PosTextSize height}) _fieldSizePair(
      String ticket, String field, bool isHeader) {
    final tier = _config.fieldSize(ticket, field);
    if (tier <= 0) return isHeader ? _headerSize() : _bodySize();
    return PrinterConfig.tierSize(tier);
  }

  /// The size one field resolves to under the current config — the whole of
  /// the per-field sizing decision, exposed so it can be checked without a
  /// printer attached.
  @visibleForTesting
  ({PosTextSize width, PosTextSize height}) debugFieldSize(
          String ticket, String field, {bool isHeader = false}) =>
      _fieldSizePair(ticket, field, isHeader);

  /// Width dimension for one ticket field. Falls back to the global body (or
  /// header) size when the operator has not pinned this field to a scale, or
  /// to [fallback] for the few lines that were hard-coded to a fixed size
  /// rather than following the global setting.
  PosTextSize _resolveFieldSize(String ticket, String field,
      {bool isHeader = false, PosTextSize? fallback}) {
    if (fallback != null && _config.fieldSize(ticket, field) <= 0) {
      return fallback;
    }
    return _fieldSizePair(ticket, field, isHeader).width;
  }

  /// Height counterpart to [_resolveFieldSize].
  PosTextSize _resolveFieldHeight(String ticket, String field,
      {bool isHeader = false, PosTextSize? fallback}) {
    if (fallback != null && _config.fieldSize(ticket, field) <= 0) {
      return fallback;
    }
    return _fieldSizePair(ticket, field, isHeader).height;
  }

  // ── Separators ────────────────────────────────────────────────────────
  //
  // The package's bare `generator.hr()` defaults to a thin `-` rule that
  // reads as weak on thermal paper. These helpers swap in styled
  // characters that print darker and read as clear section dividers:
  //
  //   _sepMajor — a heavy `=` rule for top-of-ticket / between-sections.
  //   _sepMinor — a `-` rule with denser packing for inside-section breaks.
  //
  // Both honor the configured paper size (the package's hr() already does
  // that — we just pick the char).
  List<int> _sepMajor(Generator generator) => generator.hr(ch: '=');
  List<int> _sepMinor(Generator generator) => generator.hr(ch: '-');

  /// Get currency symbol from settings provider
  String _getCurrency(String? providedCurrency) {
    if (providedCurrency != null) return providedCurrency;
    if (_ref != null) {
      try {
        return _ref!.read(currencySymbolProvider);
      } catch (e) {
        debugPrint('Error reading currency from provider: $e');
      }
    }
    return 'USD'; // Fallback default
  }

  /// Ensure printer is connected, with automatic rescan and reconnect if needed
  Future<bool> _ensurePrinterConnectedRaw(PrinterPurpose purpose,
      {_KdsTarget? kdsOverride}) async {
    final isReceipt = purpose == PrinterPurpose.receipt;
    final useOverride = !isReceipt && kdsOverride != null;
    final currentPrinter = isReceipt ? _connectedReceiptPrinter : _connectedKdsPrinter;
    final savedAddress = useOverride
        ? kdsOverride.address
        : (isReceipt ? _config.receiptPrinterAddress : _config.kdsPrinterAddress);
    final savedType = useOverride
        ? kdsOverride.type
        : (isReceipt ? _config.receiptConnectionType : _config.kdsConnectionType);
    final savedName = useOverride
        ? kdsOverride.name
        : (isReceipt ? _config.receiptPrinterName : _config.kdsPrinterName);

    // With an override in play, the cached _connectedKdsPrinter may belong to
    // a DIFFERENT physical device (a prior station's printer in the same
    // print run). Only honor the cache when its address matches the address
    // we're about to dispatch to — otherwise invalidate so we reconnect to
    // the right device.
    if (useOverride &&
        currentPrinter != null &&
        currentPrinter.address != kdsOverride.address) {
      _connectedKdsPrinter = null;
    }
    final usableCached = (useOverride
        ? (_connectedKdsPrinter)
        : currentPrinter);

    // If printer already connected, we're good
    if (usableCached != null) {
      debugPrint('${purpose.name} printer already connected');
      return true;
    }

    // Check if we have saved printer config
    if (savedAddress == null) {
      debugPrint('No saved ${purpose.name} printer configuration found');
      return false;
    }

    // NETWORK printers are never in the scan list — reconstruct directly from
    // saved config and probe reachability via [connectPrinter].
    if (savedType == ConnectionType.NETWORK) {
      final manual = Printer(
        name: savedName ?? 'Network printer',
        address: savedAddress,
        connectionType: ConnectionType.NETWORK,
        isConnected: false,
      );
      return await connectPrinter(manual, purpose);
    }

    // Emit "connecting" status so the UI can show a loading overlay
    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('connecting_printer', fallback: 'Connecting to printer...'));

    debugPrint('${purpose.name} printer not connected, attempting to reconnect: $savedAddress');

    // Step 1: Try to find printer in current available printers list
    Printer? printer = _findPrinterByAddress(savedAddress);

    if (printer != null) {
      final connected = await connectPrinter(printer, purpose);
      if (connected) {
        debugPrint('Successfully connected to ${purpose.name} printer');
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return true;
      }
    }

    // Step 2: Printer not in list or connection failed — try rescanning
    _printingStatusController.add(_translate('scanning_for_printer', fallback: 'Scanning for printer...'));
    debugPrint('Printer not found in available list or connection failed, rescanning...');

    try {
      await startScan();
      await Future.delayed(const Duration(seconds: 4));

      _printingStatusController.add(_translate('connecting_printer', fallback: 'Connecting to printer...'));
      printer = _findPrinterByAddress(savedAddress);

      if (printer != null) {
        final connected = await connectPrinter(printer, purpose);
        if (connected) {
          debugPrint('Successfully connected to ${purpose.name} printer after rescan');
          _isPrintingInProgress = false;
          _printingStatusController.add(null);
          return true;
        }
      } else {
        debugPrint('${purpose.name} printer still not found after rescan');
      }
    } catch (e) {
      debugPrint('Error during rescan and reconnect: $e');
    }

    _isPrintingInProgress = false;
    _printingStatusController.add(null);
    debugPrint('Unable to establish ${purpose.name} printer connection');
    return false;
  }

  /// Translation helper using printing language (independent of app language)
  String _translate(String key, {String? fallback}) {
    final printL10n = AppLocalizations(Locale(_config.printingLanguage));
    return _sanitizeForThermal(printL10n.translate(key));
  }

  /// Helper for static text that might not need translation but should be consistent
  String _text(String key, {String? fallback}) {
    return _translate(key, fallback: fallback);
  }

  /// Replace characters that aren't reliably encodable in the common ESC/POS
  /// code pages (CP437 / CP850 / CP858) with safe equivalents.
  ///
  /// Background: cheap thermal printers internally use one of those code
  /// pages even when the app sends `setGlobalCodeTable CP1252`. A character
  /// the printer's page can't represent (canonical example: `œ` in `Bœuf`,
  /// at CP1252 byte 0x9C) causes some driver+firmware combos to stall
  /// mid-stream, the Windows spool's WritePrinter call to block, and the
  /// 10s dispatch timeout to fire — looking like "the printer just refuses
  /// to print this ticket".
  ///
  /// This function is called on every user-typed string (product names,
  /// customer info, notes, addresses) and on every translated label before
  /// it reaches `generator.text(...)`. The mapping table is curated for the
  /// characters that *actually* break — common French (`é è ê à ç ï ô î û`)
  /// is universally supported and passes through untouched.
  ///
  /// The final regex strips anything outside Latin-1 (`> U+00FF`) — CJK,
  /// Cyrillic, Arabic, emoji — replacing with `?`. Those weren't going to
  /// print anyway and silently swallowing them is better than hanging the
  /// whole ticket.
  String _sanitizeForThermal(String? input) => _staticSanitize(input);

  static String _staticSanitize(String? input) {
    if (input == null || input.isEmpty) return input ?? '';
    const replacements = {
      // The actual culprit observed in production: `Bœuf` in product names.
      'œ': 'oe', 'Œ': 'OE',
      // Eastern European / German / Icelandic — defense in depth in case
      // the menu ever includes imported items. Cheap to map; harmless when
      // not present.
      'ß': 'ss',
      'Ÿ': 'Y',
      'Š': 'S', 'š': 's',
      'Ž': 'Z', 'ž': 'z',
      'Č': 'C', 'č': 'c',
      'Đ': 'D', 'đ': 'd',
      'Þ': 'Th', 'þ': 'th',
      // Currency / typographic — present in CP1252 but missing in CP437.
      '€': 'EUR',
      '–': '-', '—': '-',
      '“': '"', '”': '"',
      '‘': "'", '’': "'",
      '…': '...',
      // Ordinal indicators: valid Latin-1, so the >0xFF net below lets them
      // through, but CP437 renders 0xBA as a box-drawing glyph. "No 4F8-JKL"
      // is the conventional abbreviation anyway and cannot garble.
      'º': 'o', 'ª': 'a',
    };
    var out = input;
    replacements.forEach((bad, safe) {
      if (out.contains(bad)) out = out.replaceAll(bad, safe);
    });
    // Final safety net: anything outside Latin-1 becomes '?'. Cheap, and
    // means the next surprise menu item (sushi name in kanji, dish in
    // Cyrillic, emoji) prints as a question mark rather than hanging the
    // whole ticket and freezing the cashier.
    if (out.codeUnits.any((c) => c > 0xFF)) {
      out = out.replaceAll(RegExp(r'[^ -ÿ]'), '?');
    }
    return out;
  }

  /// Shorthand for `_sanitizeForThermal` used at call sites that take a
  /// nullable input. Returns an empty string for null so the caller can
  /// concatenate without a null check.
  String _safe(String? input) => _sanitizeForThermal(input);

  /// Exposed for tests: an unencodable character here does not merely look
  /// wrong, it can stall the printer mid-stream (see [_sanitizeForThermal]).
  @visibleForTesting
  static String sanitizeForThermalTest(String input) =>
      PrintingService._staticSanitize(input);

  /// The operator's own header / footer text.
  ///
  /// Read from the settings provider when one is reachable, and straight from
  /// SharedPreferences when it is not — both are the same key. The fallback is
  /// the point: this service is a singleton that outlives the ProviderScope
  /// that built it, so [_ref] can be stale, and `read` on a stale ref throws.
  /// The old code caught that exception, said nothing, and printed a ticket
  /// with no header — which is exactly the report that sent us looking.
  ///
  /// [ticket] selects the per-type override ('order', 'customer', 'store').
  /// A type with nothing of its own falls back to the shared text, so a till
  /// that only ever configured one header keeps printing it everywhere.
  String _customTicketText(String prefsKey, {String? ticket}) {
    if (_ref != null) {
      try {
        final settings = _ref!.read(settingsProvider);
        final isHeader = prefsKey == SettingsKeys.ticketHeader;
        if (ticket != null) {
          final perType = (isHeader
              ? settings.ticketHeaders
              : settings.ticketFooters)[ticket];
          if (perType != null && perType.isNotEmpty) return perType;
        }
        final value =
            isHeader ? settings.ticketHeader : settings.ticketFooter;
        if (value.isNotEmpty) return value;
      } catch (e) {
        debugPrint('Ticket $prefsKey unreadable from settings ($e) — '
            'falling back to prefs');
      }
    }
    return _prefs?.getString(prefsKey) ?? '';
  }

  /// The "why" under a reduction line, or nothing at all.
  ///
  /// Its own indented line rather than part of the label: a reason is free
  /// text and the label column is eight characters wide on a 58mm roll, so
  /// appending it would truncate the amount instead. Empty when no reason was
  /// given, or when the operator turned the setting off — an undiscounted, or
  /// simply unexplained, ticket is unchanged.
  List<int> _discountReasonLines(Generator generator, String? reason) {
    final text = reason?.trim() ?? '';
    if (text.isEmpty) return const <int>[];
    if (_ref != null) {
      try {
        if (!_ref!.read(settingsProvider).printDiscountReason) {
          return const <int>[];
        }
      } catch (_) {
        // Stale ref: print it. A reduction the ticket cannot explain is the
        // worse of the two failures.
      }
    }
    return generator.text('  ${_sanitizeForThermal(text)}',
        styles: const PosStyles(align: PosAlign.left));
  }

  /// Exposed for tests: what the header/footer resolves to right now.
  @visibleForTesting
  String debugCustomTicketText(String prefsKey, {String? ticket}) =>
      _customTicketText(prefsKey, ticket: ticket);

  /// What actually goes in the KDS banner for a station.
  ///
  /// A station whose name is blank (or is only whitespace, which a careless
  /// catalogue edit produces easily) used to print `***  ***` — a ticket with
  /// no indication of which counter it belongs to. It falls back to the same
  /// "General" label a stationless item gets.
  String _stationBanner(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? _text('general', fallback: 'General') : trimmed;
  }

  /// Exposed for tests: the banner text for a station name.
  @visibleForTesting
  String debugStationBanner(String name) => _stationBanner(name);

  /// The business identity as configured, used whenever a caller does not
  /// supply its own.
  ///
  /// A BLANK value counts as "not supplied", not as "print an empty line".
  /// That distinction is the actual bug this exists to kill: the main screen's
  /// print button passed `storeName: ""`, which is not null, so the header
  /// emitted an empty bold line and the shop's name never appeared — on that
  /// path only. Nobody could see why the same order printed two different
  /// tickets.
  ///
  /// Returns null when neither the caller nor the settings have anything, so
  /// the layout's `!= null` checks still omit the line entirely.
  String? _storeField(String? given, String prefsKey) {
    if ((given ?? '').trim().isNotEmpty) return given;
    final stored = _prefs?.getString(prefsKey)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    // _prefs is set at initialize(); the ref is the belt-and-braces path for a
    // service used before that (tests, an early print on a cold start).
    try {
      final viaRef = _ref?.read(sharedPreferencesProvider).getString(prefsKey);
      if (viaRef != null && viaRef.trim().isNotEmpty) return viaRef.trim();
    } catch (_) {}
    return null;
  }

  /// Test seam for [_storeField] — the resolution every print path now shares.
  @visibleForTesting
  String? debugStoreField(String? given, String prefsKey) =>
      _storeField(given, prefsKey);

  /// The delivery-platform identity for an order, read off the ORDER ROW.
  ///
  /// Never off the queue item: queue rows are purged after 7 days and this is
  /// also the reprint path, which must still produce the courier's code months
  /// later. Callers may pass these explicitly (the LAN server does, for an
  /// order it holds in memory); everyone else gets them resolved from the id.
  /// The per-session order number to print, or null to print nothing.
  ///
  /// Only hits the database when [ticket] has the field switched on and the
  /// caller did not already know the number — the receipt builders get a
  /// ticket id, and a cart held in memory may predate its save.
  Future<int?> _orderNumberFor(String ticket,
      {int? known, int? orderId, int? ticketId}) async {
    if (!_fieldOn(ticket, 'orderNumber')) return null;
    if (known != null) return known;
    if (_ref == null || (orderId == null && ticketId == null)) return null;
    try {
      final db = _ref!.read(databaseProvider);
      var id = orderId;
      if (id == null) {
        final t = await (db.select(db.tickets)
              ..where((t) => t.id.equals(ticketId!))
              ..limit(1))
            .getSingleOrNull();
        id = t?.orderId;
      }
      if (id == null) return null;
      final row = await (db.select(db.orders)
            ..where((o) => o.id.equals(id!))
            ..limit(1))
          .getSingleOrNull();
      return row?.sessionOrderNo;
    } catch (e) {
      debugPrint('Order number lookup failed: $e');
      return null;
    }
  }

  Future<({String? source, String? code, String? customer})> _platformIdentity(
    CurrentOrder order, {
    String? source,
    String? externalOrderCode,
    String? customerName,
  }) async {
    var resolvedCustomer = customerName ?? order.customerName;
    if (source != null || order.orderId == null || _ref == null) {
      return (
        source: source,
        code: externalOrderCode,
        customer: resolvedCustomer,
      );
    }
    try {
      final db = _ref!.read(databaseProvider);
      final row = await (db.select(db.orders)
            ..where((o) => o.id.equals(order.orderId!))
            ..limit(1))
          .getSingleOrNull();
      return (
        source: row?.source,
        code: externalOrderCode ?? row?.externalOrderCode,
        customer: resolvedCustomer,
      );
    } catch (e) {
      // A ticket with no courier block beats no ticket at all.
      debugPrint('Platform identity lookup failed: $e');
      return (
        source: null,
        code: externalOrderCode,
        customer: resolvedCustomer,
      );
    }
  }

  /// Render one of those lines, centred, one printed line per typed line.
  ///
  /// Arabic takes the raster path for the same reason product names do: the
  /// Latin code pages cannot encode it, so `generator.text` would put question
  /// marks on the paper where the shop's own words should be.
  Future<List<int>> _customTextLines(Generator generator, String text) async {
    var bytes = <int>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      if (_containsArabic(line)) {
        bytes += await _arabicImageLine(generator, line, align: PosAlign.center);
      } else {
        bytes += generator.text(
          _safe(line),
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
    }
    return bytes;
  }

  /// Split [text] into lines of at most [maxChars], breaking at spaces.
  ///
  /// Left to itself the printer wraps at the exact column, so a long address
  /// lost its last letter to the next line ("Casablanc" / "a"). A single word
  /// longer than a whole line is the only thing still cut mid-word.
  @visibleForTesting
  static List<String> wordWrap(String text, int maxChars) {
    if (maxChars <= 0) return [text];
    final lines = <String>[];
    var current = '';
    for (var word in text.trim().split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      while (word.length > maxChars) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        lines.add(word.substring(0, maxChars));
        word = word.substring(maxChars);
      }
      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= maxChars) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  /// [generator.text] with word wrapping computed for the paper width and
  /// the text's width multiplier (font A: 48 columns on 80mm, 32 on 58mm).
  List<int> _wrappedText(Generator generator, String text, PosStyles styles) {
    final columns = _config.paperSize == PaperSize.mm58 ? 32 : 48;
    final maxChars = columns ~/ styles.width.value;
    var bytes = <int>[];
    for (final line in wordWrap(text, maxChars)) {
      bytes += generator.text(line, styles: styles);
    }
    return bytes;
  }

  /// Whether [field] should print on the given [ticket] type ('customer' |
  /// 'store' | 'kds'). A missing entry falls back to
  /// [PrinterConfig.fieldDefaultOn] — visible for everything except the
  /// opt-in extras (TVA, cash given, change).
  bool _fieldOn(String ticket, String field) =>
      _config.ticketFields[ticket]?[field] ??
      PrinterConfig.fieldDefaultOn(field, ticket);

  /// Emit one band of a ticket in the operator's configured row order.
  ///
  /// [emitters] is keyed by field id; a field with no emitter, or one
  /// switched off, or one whose data is absent, contributes nothing. The
  /// per-field guards live in the emitters, so a row prints (or does not)
  /// exactly as before wherever it has been dragged to.
  List<int> _emitZone(String ticket, String zone,
      Map<String, List<int> Function()> emitters) {
    var bytes = <int>[];
    for (final field in _config.orderedFields(ticket, zone)) {
      if (!_fieldOn(ticket, field)) continue;
      final emit = emitters[field];
      if (emit != null) bytes += emit();
    }
    return bytes;
  }

  /// True if [s] contains any Arabic-script code point (base block, supplements,
  /// and presentation forms). Latin thermal code pages can't encode these, so
  /// such strings are rendered as raster images instead of `generator.text`.
  bool _containsArabic(String? s) =>
      s != null &&
      RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]')
          .hasMatch(s);

  /// Printable width in dots for the configured paper size — the same values
  /// the logo rasteriser uses (58mm → 384, 80mm → 576).
  int _receiptWidthDots() => _config.paperSize == PaperSize.mm58 ? 384 : 576;

  /// Render [text] to a raster image (auto-wrapping) and return the ESC/POS
  /// bytes. Uses Flutter's text engine so Arabic letters are shaped and ordered
  /// (RTL) correctly — the raw CP864 code page prints unshaped, reversed glyphs
  /// on most printers. On any failure it falls back to sanitised `generator.text`
  /// (prints `?`) so a receipt can never hang mid-print.
  Future<List<int>> _arabicImageLine(
    Generator generator,
    String text, {
    PosAlign align = PosAlign.right,
    bool bold = false,
    bool small = false,
  }) async {
    try {
      final width = _receiptWidthDots();
      final fontSize = small ? 22.0 : 30.0;
      final weight = bold ? FontWeight.bold : FontWeight.normal;
      final textAlign = align == PosAlign.center
          ? TextAlign.center
          : align == PosAlign.left
              ? TextAlign.left
              : TextAlign.right;

      final builder = ParagraphBuilder(ParagraphStyle(
        textAlign: textAlign,
        textDirection: TextDirection.rtl,
        fontSize: fontSize,
        fontWeight: weight,
        maxLines: 4,
      ))
        ..pushStyle(TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSize,
          fontWeight: weight,
        ))
        ..addText(text);
      final paragraph = builder.build()
        ..layout(ParagraphConstraints(width: width.toDouble()));
      final height = paragraph.height.ceil().clamp(1, 4096).toInt();

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      // White background so the printer's 1-bit threshold keeps glyphs black.
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.drawParagraph(paragraph, Offset.zero);
      final uiImage = await recorder.endRecording().toImage(width, height);
      final byteData =
          await uiImage.toByteData(format: ImageByteFormat.rawRgba);
      if (byteData == null) return generator.text(_safe(text));

      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: byteData.buffer.asUint8List().buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return generator.image(image, align: align);
    } catch (e) {
      debugPrint('Arabic image line render failed: $e');
      return generator.text(_safe(text), styles: PosStyles(align: align));
    }
  }

  /// Get AppLocalizations instance for printing language (for daily summary report)
  AppLocalizations _getPrintingL10n() {
    return AppLocalizations(Locale(_config.printingLanguage));
  }

  /// Load business logo from SharedPreferences and decode it as an Image for thermal printing.
  /// Composites alpha onto white background and converts to grayscale for proper thermal output.
  img.Image? _loadBusinessLogo() {
    try {
      if (_ref == null) return null;
      final prefs = _ref!.read(sharedPreferencesProvider);
      final base64Logo = prefs.getString('business_logo');
      if (base64Logo == null || base64Logo.isEmpty) return null;

      final logoBytes = Uint8List.fromList(base64Decode(base64Logo));
      debugPrint('Logo bytes length: ${logoBytes.length}, first bytes: ${logoBytes.take(8).toList()}');

      final decoded = img.decodeImage(logoBytes);
      if (decoded == null) {
        debugPrint('Failed to decode business logo image (decodeImage returned null)');
        return null;
      }

      debugPrint('Logo decoded: ${decoded.width}x${decoded.height}');

      // Crop first, then size: the width setting is a share of the paper,
      // so it has to be measured against what is actually going to print.
      img.Image source = decoded;
      if (_config.hasLogoCrop) {
        final x = (_config.logoCropLeft * decoded.width).round();
        final y = (_config.logoCropTop * decoded.height).round();
        final w = ((_config.logoCropRight - _config.logoCropLeft) *
                decoded.width)
            .round();
        final h = ((_config.logoCropBottom - _config.logoCropTop) *
                decoded.height)
            .round();
        // A degenerate box would throw inside copyCrop and lose the whole
        // receipt, so an unusable crop simply does not apply.
        if (w > 0 && h > 0 && x + w <= decoded.width && y + h <= decoded.height) {
          source = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
        }
      }

      // Printable width in dots (~384 for 58mm, ~576 for 80mm), times the
      // configured share of it.
      final maxWidth = _config.paperSize == PaperSize.mm58 ? 384 : 576;
      final target =
          (maxWidth * _config.logoWidthPercent / 100).round().clamp(1, maxWidth);
      img.Image resized = source;
      if (source.width != target) {
        resized = img.copyResize(source, width: target);
      }

      // Create a new opaque RGBA image with white background.
      // Must keep 4 channels (RGBA) because the printer library's rasterizer
      // calls getBytes(order: ChannelOrder.rgba) and expects 4 bytes per pixel.
      // Do NOT pre-grayscale — the printer library handles grayscale + invert internally.
      final w = resized.width;
      final h = resized.height;
      final result = img.Image(width: w, height: h, numChannels: 4);

      // Fill with opaque white
      img.fill(result, color: img.ColorRgba8(255, 255, 255, 255));

      // Composite the original image onto white, handling alpha blending
      img.compositeImage(result, resized);

      debugPrint('Logo ready for printing: ${result.width}x${result.height}, channels=${result.numChannels}');
      return result;
    } catch (e) {
      debugPrint('Error loading business logo: $e');
      return null;
    }
  }

  PosAlign _logoPosAlign() => switch (_config.logoAlign) {
        LogoAlign.left => PosAlign.left,
        LogoAlign.right => PosAlign.right,
        LogoAlign.center => PosAlign.center,
      };

  /// Print the business logo at the top of a receipt if available.
  /// Returns the bytes to prepend to the receipt.
  List<int> _printLogoHeader(Generator generator) {
    try {
      final logo = _loadBusinessLogo();
      if (logo == null) return [];

      List<int> bytes = [];
      bytes += generator.image(logo, align: _logoPosAlign());
      bytes += generator.emptyLines(1);
      return bytes;
    } catch (e) {
      debugPrint('Error printing logo header: $e');
      return [];
    }
  }

  /// Get appropriate code table for thermal printer based on printing language
  /// Returns the code table name for ESC/POS printers
  String _getCodeTableForLanguage() {
    final language = _config.printingLanguage;

    switch (language) {
      case 'ar':
        return 'CP864';
      // Spanish needs a, e, i, o, u with acute, n with tilde, u with
      // diaeresis, and the inverted marks. CP1252 carries all of them, and
      // so does the CP437/CP850 a cheap printer may actually be sitting on,
      // so nothing here needs a page of its own.
      case 'es':
      case 'fr':
        return 'CP1252';
      case 'en':
      default:
        return 'CP1252';
    }
  }

  /// Print a single-page slip summarising what a waiter owes for a chosen
  /// set of unpaid orders. Operator-initiated from the waiter settlement
  /// dialog — bypasses [shouldPrint] (no rule gate, no source filter)
  /// because the cashier explicitly asked for this print.
  ///
  /// `orders` carries one entry per included order: code, due amount, and
  /// optional table label. The slip lists them, sums to `grandTotal`,
  /// stamps the cashier name + timestamp, then cuts.
  Future<bool> printWaiterSettlementSlip({
    required String waiterName,
    required List<({String code, double due, String? tableName})> orders,
    required double grandTotal,
    String? cashierName,
    String? currency,
  }) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('printWaiterSettlementSlip: receipt printer not ready');
      return false;
    }

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing', fallback: 'Printing...'));

    try {
      final currencySymbol = _getCurrency(currency);
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());
      bytes += _printLogoHeader(generator);

      bytes += generator.text(
        _text('waiter_settlement_slip',
            fallback: 'WAITER SETTLEMENT'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += _sepMinor(generator);
      bytes += generator.text(
        '${_text('waiter', fallback: 'Waiter')}: ${_safe(waiterName)}',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.text(
        '${_text('date', fallback: 'Date')}: ${_formatDateTime(DateTime.now())}',
      );
      if (cashierName != null && cashierName.trim().isNotEmpty) {
        bytes += generator.text(
          '${_translate('cashier')}: ${_safe(cashierName)}',
        );
      }
      bytes += _sepMinor(generator);

      for (final o in orders) {
        // Left col: code (+ optional table). Right col: amount due.
        final leftLine = o.tableName != null && o.tableName!.trim().isNotEmpty
            ? '${_safe(o.code)}  (${_safe(o.tableName!)})'
            : _safe(o.code);
        bytes += generator.row([
          PosColumn(
            text: leftLine,
            width: 8,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text:
                CurrencyFormatter.formatWithCurrency(o.due, currencySymbol),
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      bytes += _sepMinor(generator);
      bytes += generator.row([
        PosColumn(
          text: _text('total_due', fallback: 'TOTAL DUE'),
          width: 6,
          styles: PosStyles(
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(grandTotal, currencySymbol),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      ]);

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return ok;
    } catch (e, st) {
      debugPrint('printWaiterSettlementSlip failed: $e\n$st');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return false;
    }
  });

  /// Print a comprehensive **summary** for a waiter (vs. the slim
  /// "settlement" slip emitted by [printWaiterSettlementSlip]). Same
  /// printer slot and dispatch path; richer body:
  ///   - KPI block (orders, paid, owed)
  ///   - Unpaid list (code + table + due)
  ///   - Paid history (ticket # + method + amount + time)
  ///   - Grand "total due" footer
  ///
  /// Operator-initiated from [WaiterProfileDialog]; bypasses
  /// [shouldPrint] for the same reason the settlement slip does.
  Future<bool> printWaiterProfileSummary({
    required String waiterName,
    required String sessionLabel,
    required int ordersCount,
    required double totalPaid,
    required double totalOwed,
    required List<({String code, double due, String? tableName})> unpaidOrders,
    required List<
        ({String ticketNum, String paymentMethod, double amount, DateTime at})> paidTickets,
    String? cashierName,
    String? currency,
  }) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('printWaiterProfileSummary: receipt printer not ready');
      return false;
    }

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing', fallback: 'Printing...'));

    try {
      final currencySymbol = _getCurrency(currency);
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());
      bytes += _printLogoHeader(generator);

      // Title
      bytes += generator.text(
        _text('waiter_summary_slip', fallback: 'WAITER SUMMARY'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += _sepMinor(generator);

      // Identity block
      bytes += generator.text(
        '${_text('waiter', fallback: 'Waiter')}: ${_safe(waiterName)}',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.text(
        '${_text('session', fallback: 'Session')}: ${_safe(sessionLabel)}',
      );
      if (cashierName != null && cashierName.trim().isNotEmpty) {
        bytes += generator.text(
          '${_translate('cashier')}: ${_safe(cashierName)}',
        );
      }
      bytes += generator.text(
        '${_text('date', fallback: 'Date')}: ${_formatDateTime(DateTime.now())}',
      );
      bytes += _sepMinor(generator);

      // KPIs
      bytes += generator.row([
        PosColumn(
          text: _text('kpi_orders', fallback: 'Orders'),
          width: 8,
        ),
        PosColumn(
          text: '$ordersCount',
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(
          text: _text('kpi_paid', fallback: 'Paid'),
          width: 8,
        ),
        PosColumn(
          text:
              CurrencyFormatter.formatWithCurrency(totalPaid, currencySymbol),
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += generator.row([
        PosColumn(
          text: _text('kpi_owed', fallback: 'Owed'),
          width: 8,
        ),
        PosColumn(
          text:
              CurrencyFormatter.formatWithCurrency(totalOwed, currencySymbol),
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      bytes += _sepMinor(generator);

      // Unpaid orders block (only if any)
      if (unpaidOrders.isNotEmpty) {
        bytes += generator.text(
          _text('tab_unpaid', fallback: 'UNPAID').toUpperCase(),
          styles: const PosStyles(bold: true),
        );
        for (final o in unpaidOrders) {
          final leftLine = o.tableName != null && o.tableName!.trim().isNotEmpty
              ? '${_safe(o.code)}  (${_safe(o.tableName!)})'
              : _safe(o.code);
          bytes += generator.row([
            PosColumn(
              text: leftLine,
              width: 8,
              styles: const PosStyles(align: PosAlign.left),
            ),
            PosColumn(
              text:
                  CurrencyFormatter.formatWithCurrency(o.due, currencySymbol),
              width: 4,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
        bytes += _sepMinor(generator);
      }

      // Paid history block (only if any)
      if (paidTickets.isNotEmpty) {
        bytes += generator.text(
          _text('tab_paid_history', fallback: 'PAID HISTORY').toUpperCase(),
          styles: const PosStyles(bold: true),
        );
        for (final t in paidTickets) {
          final timeStr =
              '${t.at.hour.toString().padLeft(2, '0')}:${t.at.minute.toString().padLeft(2, '0')}';
          bytes += generator.row([
            PosColumn(
              text:
                  '#${_safe(t.ticketNum)}  ${_safe(t.paymentMethod)}',
              width: 7,
              styles: const PosStyles(align: PosAlign.left),
            ),
            PosColumn(
              text: CurrencyFormatter.formatWithCurrency(
                  t.amount, currencySymbol),
              width: 3,
              styles: const PosStyles(align: PosAlign.right),
            ),
            PosColumn(
              text: timeStr,
              width: 2,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
        }
        bytes += _sepMinor(generator);
      }

      // Total due footer
      bytes += generator.row([
        PosColumn(
          text: _text('total_due', fallback: 'TOTAL DUE'),
          width: 6,
          styles: PosStyles(
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(totalOwed, currencySymbol),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      ]);

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return ok;
    } catch (e, st) {
      debugPrint('printWaiterProfileSummary failed: $e\n$st');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return false;
    }
  });

  /// Print order receipt
  Future<bool> printOrderReceipt({
    required CurrentOrder order,
    required String? cashierName,
    String? currency,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    // Delivery-platform identity. Passed in rather than read off CurrentOrder,
    // which is the cart model and has no notion of a platform. Absent (or a
    // non-platform source) means no courier block — what every till order and
    // every DealUp/Web order wants.
    String? source,
    String? externalOrderCode,
    String? pickUpCode,
    String? customerName,
    /// [OrderTicketPrintMode.additionsOnly] prints only units not yet put on
    /// a slip and, on success, records them — so the next Continue prints the
    /// next round rather than the whole bill again. Defaults to [full], which
    /// is what a bill presented to a customer wants and what every existing
    /// caller relied on.
    OrderTicketPrintMode mode = OrderTicketPrintMode.full,
  }) => _enqueue(() async {
    // Try to ensure printer is connected
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection');
      return false;
    }

    // What actually goes on this slip. In additions-only mode the order is
    // narrowed to the un-slipped units BEFORE anything is laid out, so the
    // totals block prices this round rather than the whole table.
    final printedLines = _orderTicketLinesFor(order, mode);
    if (printedLines.isEmpty) {
      // Nothing new since the last slip. Not a failure — the caller asked for
      // additions and there are none, so report success and spend no paper.
      debugPrint('Order ticket: nothing new to print (mode: $mode)');
      return true;
    }
    final fullOrder = order;
    order = order.copyWith(items: printedLines);

    // Identity is resolved HERE, not by the caller. Every call site used to
    // assemble it itself and they had drifted apart — see [_storeField].
    storeName = _storeField(storeName, 'business_name');
    storeAddress = _storeField(storeAddress, 'business_address');
    storePhone = _storeField(storePhone, 'business_phone');
    final storeIce = _storeField(null, 'business_ice');
    final platform = await _platformIdentity(
      fullOrder,
      source: source,
      externalOrderCode: externalOrderCode,
      customerName: customerName,
    );
    source = platform.source;
    externalOrderCode = platform.code;
    customerName = platform.customer;

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing', fallback: 'Printing...'));

    try {
      final currencySymbol = _getCurrency(currency);
      final selectionTypes =
          await _optionSelectionTypes(order.items, _catalogueDatabase);
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Set code table based on current language (supports Arabic, French, English)
      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      // Print business logo if available
      // Courier block FIRST, above the logo and the items: the courier reads
      // the top of the ticket sticking out of the bag, and anything above the
      // code is paper they have to unfold.
      if (sourceHasCourierCode(source) &&
          _config.courierCodeMode == CourierCodeMode.sameTicket) {
        bytes += _buildCourierBlock(
          generator,
          source: source!,
          externalOrderCode: externalOrderCode,
          pickUpCode: pickUpCode,
          customerName: customerName,
          ourOrderCode: order.orderCode ?? '',
        );
        bytes += generator.emptyLines(1);
      }

      bytes += _printLogoHeader(generator);

      // Header
      if (storeName != null) {
        bytes += generator.text(
          _safe(storeName),
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveFieldHeight('order', 'storeName', isHeader: true),
            width: _resolveFieldSize('order', 'storeName', isHeader: true),
          ),
        );
      }

      bytes += _emitZone('order', 'header', {
        'storeAddress': () => storeAddress == null
            ? const <int>[]
            : _wrappedText(
                generator,
                _safe(storeAddress),
                PosStyles(
                  align: PosAlign.center,
                  height: _resolveFieldHeight('order', 'storeAddress'),
                  width: _resolveFieldSize('order', 'storeAddress'),
                ),
              ),
        'storeIce': () => storeIce == null
            ? const <int>[]
            : _wrappedText(
                generator,
                'ICE : ${_safe(storeIce)}',
                PosStyles(
                  align: PosAlign.center,
                  height: _resolveFieldHeight('order', 'storeIce'),
                  width: _resolveFieldSize('order', 'storeIce'),
                ),
              ),
        'storePhone': () => storePhone == null
            ? const <int>[]
            : generator.text(
                '${_text('tel', fallback: 'Tel')}: ${_safe(storePhone)}',
                styles: PosStyles(
                  align: PosAlign.center,
                  height: _resolveFieldHeight('order', 'storePhone'),
                  width: _resolveFieldSize('order', 'storePhone'),
                ),
              ),
      });

      // Custom ticket header
      bytes += await _customTextLines(generator,
          _customTicketText(SettingsKeys.ticketHeader, ticket: 'order'));

      bytes += _sepMajor(generator);

      // Order info
      // Info rows, in the order the operator arranged them (Printers >
      // Ticket content). Each entry keeps the guard it always had, so a row
      // with nothing to say still prints nothing wherever it now sits.
      final orderNumber = await _orderNumberFor('order',
          known: order.sessionOrderNo, orderId: order.orderId);
      bytes += _emitZone('order', 'info', {
        'orderCode': () => generator.text(
              '${_translate("order")} #${order.orderCode ?? "N/A"}',
              styles: PosStyles(
                align: PosAlign.left,
                bold: true,
                height: _resolveFieldHeight('order', 'orderCode'),
                width: _resolveFieldSize('order', 'orderCode'),
              ),
            ),
        'orderNumber': () => orderNumber == null
            ? const <int>[]
            : generator.text(
                '${_text('order_number', fallback: 'No')} #$orderNumber',
                styles: PosStyles(
                  align: PosAlign.left,
                  bold: true,
                  height: _resolveFieldHeight('order', 'orderNumber'),
                  width: _resolveFieldSize('order', 'orderNumber'),
                ),
              ),
        'date': () => generator.text(
              '${_text('date', fallback: 'Date')}: ${_formatDateTime(DateTime.now())}',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('order', 'date'),
                width: _resolveFieldSize('order', 'date'),
              ),
            ),
        'cashier': () => cashierName == null
            ? const <int>[]
            : generator.text(
                '${_translate("cashier")}: ${_safe(cashierName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight('order', 'cashier'),
                  width: _resolveFieldSize('order', 'cashier'),
                ),
              ),
        // Who is serving the table, as opposed to who rang it up. Blank on an
        // order with no waiter attached, so a counter shop never sees the row.
        'waiter': () => (order.waiterName ?? '').trim().isEmpty
            ? const <int>[]
            : generator.text(
                '${_translate("waiter")}: ${_safe(order.waiterName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight('order', 'waiter'),
                  width: _resolveFieldSize('order', 'waiter'),
                ),
              ),
        'table': () => order.tableName == null
            ? const <int>[]
            : generator.text(
                '${_translate("table")}: ${_safe(order.tableName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight('order', 'table'),
                  width: _resolveFieldSize('order', 'table'),
                ),
              ),
        'customerName': () => order.customerName == null
            ? const <int>[]
            : generator.text(
                '${_text('customer', fallback: 'Customer')}: ${_safe(order.customerName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight('order', 'customerName'),
                  width: _resolveFieldSize('order', 'customerName'),
                ),
              ),
        'customerPhone': () =>
            (order.customerPhone == null || order.customerPhone!.isEmpty)
                ? const <int>[]
                : generator.text(
                    '${_text('phone', fallback: 'Phone')}: ${_safe(order.customerPhone)}',
                    styles: PosStyles(
                      align: PosAlign.left,
                      height: _resolveFieldHeight('order', 'customerPhone'),
                      width: _resolveFieldSize('order', 'customerPhone'),
                    ),
                  ),
        'orderType': () => generator.text(
              '${_text('type', fallback: 'Type')}: ${_getOrderTypeText(order.type)}',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('order', 'orderType'),
                width: _resolveFieldSize('order', 'orderType'),
              ),
            ),
        // Delivery address (delivery orders only)
        'deliveryAddress': () => (order.type != 'DELIVERY' ||
                order.deliveryAddress == null ||
                order.deliveryAddress!.trim().isEmpty)
            ? const <int>[]
            : _wrappedText(
                generator,
                '${_text('delivery_address', fallback: 'Delivery address')}: ${_safe(order.deliveryAddress)}',
                PosStyles(
                  align: PosAlign.left,
                  bold: true,
                  height: _resolveFieldHeight('order', 'deliveryAddress'),
                  width: _resolveFieldSize('order', 'deliveryAddress'),
                ),
              ),
        'persons': () => generator.text(
              '${_text('persons', fallback: 'Persons')}: ${order.numberOfPersons}',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('order', 'persons'),
                width: _resolveFieldSize('order', 'persons'),
              ),
            ),
      });

      bytes += _sepMinor(generator);

      // Items
      for (final item in order.items) {
        final priceText = CurrencyFormatter.formatWithCurrency(
            item.totalPrice, currencySymbol);
        if (_containsArabic(item.displayName)) {
          // Arabic name → RTL image line, then qty + price row.
          bytes += await _arabicImageLine(generator, item.displayName,
              align: PosAlign.right, bold: true);
          bytes += generator.row([
            PosColumn(
              text: '${formatQty(item.quantity)}x',
              width: 6,
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('order', 'items'),
                width: _resolveFieldSize('order', 'items'),
              ),
            ),
            PosColumn(
              text: priceText,
              width: 6,
              styles: PosStyles(
                align: PosAlign.right,
                height: _resolveFieldHeight('order', 'items'),
                width: _resolveFieldSize('order', 'items'),
              ),
            ),
          ]);
        } else {
          bytes += generator.row([
            PosColumn(
              text: '${formatQty(item.quantity)}x ${_safe(item.displayName)}',
              width: 8,
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('order', 'items'),
                width: _resolveFieldSize('order', 'items'),
              ),
            ),
            PosColumn(
              text: priceText,
              width: 4,
              styles: PosStyles(
                align: PosAlign.right,
                height: _resolveFieldHeight('order', 'items'),
                width: _resolveFieldSize('order', 'items'),
              ),
            ),
          ]);
        }

        // Components
        for (final comp in item.components) {
          if (comp.quantity <= 0 && !comp.removalCharge) continue;
          if (comp.removalCharge) {
            bytes += generator.text(
              '  ${_safe('${_text('without', fallback: 'NO')} ${comp.name}')}',
              styles: PosStyles(
                align: PosAlign.left,
                bold: true,
                height: _resolveFieldHeight('order', 'items'),
                width: _resolveFieldSize('order', 'items'),
              ),
            );
            continue;
          }
          final label = optionLineLabel(
              comp.name,
              comp.quantity,
              selectionTypes[(item.productId, comp.componentId)] ??
                  ComponentSelectionType.quantity);
          if (_containsArabic(comp.name)) {
            bytes += await _arabicImageLine(generator, '+ $label',
                align: PosAlign.right);
          } else {
            bytes += generator.text(
              '  + ${_safe(label)}',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('order', 'items'),
                width: _resolveFieldSize('order', 'items'),
              ),
            );
          }
        }

        // Note
        if (item.note != null && item.note!.isNotEmpty) {
          if (_containsArabic(item.note)) {
            bytes += await _arabicImageLine(
                generator,
                '${_text('note', fallback: 'Note')}: ${item.note}',
                align: PosAlign.right,
                small: true);
          } else {
            bytes += generator.text(
              '  ${_text('note', fallback: 'Note')}: ${_safe(item.note)}',
              styles: PosStyles(
                align: PosAlign.left,
                fontType: PosFontType.fontB,
                height: _resolveFieldHeight('order', 'items'),
                width: _resolveFieldSize('order', 'items'),
              ),
            );
          }
        }
      }

      bytes += _sepMinor(generator);

      // Totals, in the operator's row order.
      bytes += _emitZone('order', 'totals', {
        'subtotal': () => generator.row([
              PosColumn(
                text: '${_text('subtotal', fallback: 'Subtotal')}:',
                width: 8,
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight('order', 'subtotal'),
                  width: _resolveFieldSize('order', 'subtotal'),
                ),
              ),
              PosColumn(
                text: CurrencyFormatter.formatWithCurrency(
                  order.subtotal,
                  currencySymbol,
                ),
                width: 4,
                styles: PosStyles(
                  align: PosAlign.right,
                  height: _resolveFieldHeight('order', 'subtotal'),
                  width: _resolveFieldSize('order', 'subtotal'),
                ),
              ),
            ]),
        'discount': () => order.totalDiscount <= 0
            ? const <int>[]
            : generator.row([
                PosColumn(
                  text: '${_text('discount', fallback: 'Discount')}:',
                  width: 8,
                  styles: PosStyles(
                    align: PosAlign.left,
                    height: _resolveFieldHeight('order', 'discount'),
                    width: _resolveFieldSize('order', 'discount'),
                  ),
                ),
                PosColumn(
                  text:
                      '-${CurrencyFormatter.formatWithCurrency(order.totalDiscount, currencySymbol)}',
                  width: 4,
                  styles: PosStyles(
                    align: PosAlign.right,
                    height: _resolveFieldHeight('order', 'discount'),
                    width: _resolveFieldSize('order', 'discount'),
                  ),
                ),
              ]) +
                _discountReasonLines(generator, order.discountReason),
        'tva': () => order.tax <= 0
            ? const <int>[]
            : generator.row([
                PosColumn(
                  text: '${_text('tax', fallback: 'Tax')}:',
                  width: 8,
                  styles: PosStyles(
                    align: PosAlign.left,
                    height: _resolveFieldHeight('order', 'tva'),
                    width: _resolveFieldSize('order', 'tva'),
                  ),
                ),
                PosColumn(
                  text: CurrencyFormatter.formatWithCurrency(
                    order.tax,
                    currencySymbol,
                  ),
                  width: 4,
                  styles: PosStyles(
                    align: PosAlign.right,
                    height: _resolveFieldHeight('order', 'tva'),
                    width: _resolveFieldSize('order', 'tva'),
                  ),
                ),
              ]),
      });

      bytes += _sepMinor(generator);

      bytes += generator.row([
        PosColumn(
          text: '${_text('total', fallback: 'TOTAL')}:',
          width: 6,
          styles: PosStyles(
            bold: true,
            height: _resolveFieldHeight('order', 'total', isHeader: true),
            width: _resolveFieldSize('order', 'total', isHeader: true),
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(
            order.total,
            currencySymbol,
          ),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: _resolveFieldHeight('order', 'total', isHeader: true),
            width: _resolveFieldSize('order', 'total', isHeader: true),
          ),
        ),
      ]);

      // Delivery fee, then what the customer actually owes. Same shape (and
      // the same reasoning) as the payment receipt in [printTicketReceipt]:
      // the TOTAL above is products only, so on a delivery order the ticket
      // would otherwise understate the money to collect. Ungated for the same
      // reason the receipt's copy is — a charge the customer pays is not a
      // row the operator should be able to hide.
      if (order.hasDeliveryFee && order.deliveryFeeAmount > 0) {
        bytes += generator.row([
          PosColumn(
            text: '${_text('delivery_fee', fallback: 'Delivery fee')}:',
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: CurrencyFormatter.formatWithCurrency(
                order.deliveryFeeAmount, currencySymbol),
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
        bytes += generator.row([
          PosColumn(
            text: '${_text('total_collected', fallback: 'TOTAL')}:',
            width: 6,
            styles: PosStyles(
              bold: true,
              height: _resolveFieldHeight('order', 'total', isHeader: true),
              width: _resolveFieldSize('order', 'total', isHeader: true),
            ),
          ),
          PosColumn(
            text: CurrencyFormatter.formatWithCurrency(
                order.amountDue, currencySymbol),
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              bold: true,
              height: _resolveFieldHeight('order', 'total', isHeader: true),
              width: _resolveFieldSize('order', 'total', isHeader: true),
            ),
          ),
        ]);
      }

      // No hardcoded thank-you line — only the configured ticket footer
      // (below) prints, so the store controls all footer wording.

      // Add barcode if order code exists
      if (order.orderCode != null && order.orderCode!.isNotEmpty && _fieldOn('order', 'barcode')) {
        bytes += generator.emptyLines(1);
        // Use text() to print the order code as text above barcode for clarity
        bytes += generator.text(
          order.orderCode!,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveFieldHeight('order', 'barcode'),
            width: _resolveFieldSize('order', 'barcode'),
          ),
        );
        bytes += generator.barcode(
          Barcode.code128(order.orderCode!.split('')),
          height: 80,
          align: PosAlign.center,
        );
      }

      // Print custom footer text if configured
      final footer = await _customTextLines(generator,
          _customTicketText(SettingsKeys.ticketFooter, ticket: 'order'));
      if (footer.isNotEmpty) {
        bytes += generator.emptyLines(1);
        bytes += footer;
      }

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      debugPrint('Attempting to print receipt. Bytes length: ${bytes.length}');

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint('Receipt dispatch failed — no paper came out.');
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return false;
      }

      debugPrint('Receipt printed successfully');

      // Only after the printer actually took the bytes: a failed slip that
      // still marked its lines would silently swallow that round, and the
      // customer would never be billed for it. Marked against the TRUE
      // quantities from the unfiltered order, not the deltas just printed.
      if (mode == OrderTicketPrintMode.additionsOnly && _ref != null) {
        final printedIds = {
          for (final line in order.items)
            if (line.id != null) line.id!,
        };
        final originals = [
          for (final line in fullOrder.items)
            if (line.id != null && printedIds.contains(line.id)) line,
        ];
        await _markItemsAsOrderTicketPrinted(
            _ref!.read(databaseProvider), originals);
      }

      _isPrintingInProgress = false;
      _printingStatusController.add(null);

      // Separate-ticket mode: the courier's code on its own paper for the bag,
      // right after the main ticket so the two come out together. This used to
      // live in the print-options dialog, which meant a Glovo order got its
      // courier slip when a cashier pressed Print and never got one when the
      // same order printed automatically. Best-effort: the order ticket has
      // already printed and its success is not this slip's to revoke.
      if (sourceHasCourierCode(source) &&
          _config.courierCodeMode == CourierCodeMode.separateTicket) {
        try {
          await printCourierTicket(
            source: source!,
            externalOrderCode: externalOrderCode,
            ourOrderCode: fullOrder.orderCode ?? '',
            customerName: customerName,
          );
        } catch (e) {
          debugPrint('Courier ticket failed after order ticket: $e');
        }
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing receipt: $e');
      debugPrint('Stack trace: $stackTrace');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return false;
    }
  });

  /// Print KDS ticket (kitchen order)
  /// [stationIds]: if non-empty, only print tickets for those stations. Empty = all stations.
  Future<bool> printKdsTicket({
    required CurrentOrder order,
    required String? cashierName,
    KdsPrintMode? mode,
    List<int> stationIds = const [],
    /// [KdsPrintPurpose.cancel] prints the same ticket, to the same stations,
    /// as a VOID: the lines are taken exactly as given (no delta filtering),
    /// nothing is marked printed, and the layout says plainly that this is
    /// food to stop making.
    KdsPrintPurpose purpose = KdsPrintPurpose.send,
    /// Line ids the caller knows were unpaid when it fired this ticket. The
    /// job runs later, off the queue, and by then a payment may have stamped
    /// them with a ticket — which modificationsOnly would otherwise read as
    /// "settled, not a modification" and drop, leaving the kitchen with no
    /// ticket for an order paid straight from the till.
    Set<int> paidLinesStillOwed = const {},
  }) => _enqueue(() async {
    final isVoid = purpose == KdsPrintPurpose.cancel;
    if (!_config.kdsEnabled) {
      debugPrint('KDS printing is disabled in config');
      return true; // KDS disabled, consider success
    }

    // Resolve print mode from the configured default when caller doesn't
    // override. A cancellation is always 'full': the caller has already
    // narrowed it to precisely the units being pulled, and running that
    // through the delta filter would drop them (they were sent, which is the
    // whole reason they need cancelling).
    final resolvedMode =
        isVoid ? KdsPrintMode.full : (mode ?? _config.defaultKdsMode);

    // Try to ensure printer is connected
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.kds);
    if (!printerReady) {
      debugPrint('Could not establish KDS printer connection');
      return false;
    }

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing_kds', fallback: 'Printing KDS tickets...'));

    try {
      // Whole-order mode: no stations, no station printers, no filtering by
      // what a station is allowed to print. Just the order, N times, on the
      // KDS printer. Checked before the database is even consulted, because
      // none of that information is relevant here.
      if (_config.kdsFullOrderMode) {
        // Committed cursors, not the caller's snapshot — see
        // [_withDbPrintedQuantities]. A void has already been narrowed to the
        // exact units being pulled and must not be re-filtered at all.
        final sourceItems = isVoid || _ref == null
            ? order.items
            : await _withDbPrintedQuantities(
                _ref!.read(databaseProvider), order.items);
        final itemsToPrint = _filterItemsByMode(sourceItems, resolvedMode,
            paidLinesStillOwed: paidLinesStillOwed);
        if (itemsToPrint.isEmpty) {
          debugPrint('No items to print for mode: $resolvedMode');
          _isPrintingInProgress = false;
          _printingStatusController.add(null);
          return true;
        }

        final copies = _config.kdsCopies.clamp(1, 9);
        final label = _text('kds_full_order_banner', fallback: 'ORDER');

        // One driver job holding every copy, cut between them. Sending them as
        // separate jobs is what the consolidate-KDS-job setting exists to
        // avoid: back-to-back jobs overwhelm some Windows spoolers and the
        // third one silently never comes out.
        final ok = await _printConsolidatedKdsBatch(
          order: order,
          itemsByStation: {
            for (var i = 0; i < copies; i++)
              copies == 1 ? label : '$label ${i + 1}/$copies': itemsToPrint,
          },
          mode: resolvedMode,
          purpose: purpose,
        );

        // Marking needs the database, which needs a ref. Without one the
        // ticket still prints — it just cannot record that it did, exactly as
        // the ref-less fallback below already behaves.
        if (ok && !isVoid && _ref != null) {
          await _markItemsAsPrinted(_ref!.read(databaseProvider), itemsToPrint);
        }
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return ok;
      }

      // Get database to fetch product station information
      if (_ref == null) {
        debugPrint('Warning: _ref is null, cannot group by stations');
        // Fall back to single ticket printing
        final itemsToPrint = _filterItemsByMode(order.items, resolvedMode,
            paidLinesStillOwed: paidLinesStillOwed);
        if (itemsToPrint.isEmpty) {
          debugPrint('No items to print for mode: $resolvedMode');
          _isPrintingInProgress = false;
          _printingStatusController.add(null);
          return true;
        }
        // Reset before returning: every other exit from this method clears
        // the flag and the status overlay, and this one used to leave
        // "Printing KDS tickets..." on screen for good.
        final ok = await _printKdsTicketForStation(
          order: order,
          stationName: _text('general', fallback: 'General'),
          items: itemsToPrint,
          cashierName: cashierName,
          mode: resolvedMode,
          purpose: purpose,
        );
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return ok;
      }

      final database = _ref!.read(databaseProvider);

      // Filter items based on print mode, against committed cursors rather
      // than the caller's snapshot — see [_withDbPrintedQuantities].
      final itemsToPrint = _filterItemsByMode(
        isVoid
            ? order.items
            : await _withDbPrintedQuantities(database, order.items),
        resolvedMode,
        paidLinesStillOwed: paidLinesStillOwed,
      );

      if (itemsToPrint.isEmpty) {
        debugPrint('No items to print for mode: $resolvedMode');
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return true; // Nothing to print is success
      }

      // When per-station splitting is disabled, print a single consolidated
      // kitchen ticket with all items instead of grouping by station.
      if (!_config.splitKdsByStation) {
        // When stationless items are suppressed, drop products with no station
        // even on the consolidated ticket.
        var consolidated = itemsToPrint;
        if (!_config.printKdsUnassigned) {
          consolidated = await _itemsWithStationOnly(database, itemsToPrint);
        }
        // Per-station "No printer (KDS only)" applies on the consolidated
        // ticket too: drop items whose every station is silenced.
        consolidated = await _dropSilencedItems(database, consolidated);
        if (consolidated.isEmpty) {
          _isPrintingInProgress = false;
          _printingStatusController.add(null);
          return true;
        }
        final success = await _printKdsTicketForStation(
          order: order,
          stationName: _text('general', fallback: 'General'),
          items: consolidated,
          cashierName: cashierName,
          mode: resolvedMode,
          purpose: purpose,
        );
        if (success && !isVoid) {
          await _markItemsAsPrinted(database, consolidated);
        }
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return success;
      }

      // Group items by station id (null = items with no station / "General").
      // Keyed by int? so we can resolve each station's pool printer without
      // re-parsing names — names are derived lazily for the display layer.
      final Map<int?, List<OrderItem>> itemsByStationId = {};
      final Map<int, String> stationNameCache = {};

      final bool filterByStation = stationIds.isNotEmpty;

      Future<String> stationNameFor(int id) async {
        final cached = stationNameCache[id];
        if (cached != null) return cached;
        final station = await (database.select(database.stations)
              ..where((tbl) => tbl.id.equals(id)))
            .getSingleOrNull();
        // A station the catalogue has not synced yet still has to head its
        // ticket with something the kitchen can act on. Localised, unlike the
        // hardcoded 'Station 3' this used to print on an Arabic till.
        final name = (station?.name ?? '').trim().isNotEmpty
            ? station!.name
            : '${_text('station_fallback', fallback: 'Station')} $id';
        stationNameCache[id] = name;
        return name;
      }

      // Every station a product prints on: its primary one plus any join
      // rows. Cached because a linked option asks the same question again.
      final stationsByProduct = <int, Set<int>>{};
      Future<Set<int>> stationsForProduct(int productId) async {
        final cached = stationsByProduct[productId];
        if (cached != null) return cached;
        final product = await (database.select(database.products)
              ..where((tbl) => tbl.id.equals(productId)))
            .getSingleOrNull();
        final ids = <int>{
          if (product?.stationId != null) product!.stationId!,
        };
        final extraRows = await (database.select(database.productStations)
              ..where((tbl) => tbl.productId.equals(productId)))
            .get();
        ids.addAll(extraRows.map((e) => e.stationId));
        stationsByProduct[productId] = ids;
        return ids;
      }

      // Which options stand for a product of their own, resolved to the
      // product whose stations we should route to. Empty on a server that
      // does not send the link, in which case nothing below changes.
      //
      // A linked *variant* wins over a linked product when both are set, but
      // stations are a property of the product, not the variant — so a linked
      // variant routes by the product that owns it.
      final linkedProductByComponent = <int, int>{};
      // Filled only when the operator asked for catalogue names; empty
      // otherwise, and the option keeps the name the customer chose.
      final linkedNameByComponent = <int, String>{};
      final componentIds = _config.printLinkedComponents
          ? {
              for (final item in itemsToPrint)
                for (final comp in item.components) comp.componentId,
            }
          : const <int>{};
      if (componentIds.isNotEmpty) {
        final rows = await (database.select(database.components)
              ..where((tbl) => tbl.id.isIn(componentIds)))
            .get();

        final variantIds = {
          for (final row in rows)
            if (row.linkedVariantId != null) row.linkedVariantId!,
        };
        final productByVariant = <int, int>{};
        if (variantIds.isNotEmpty) {
          final variants = await (database.select(database.productVariants)
                ..where((tbl) => tbl.id.isIn(variantIds)))
              .get();
          for (final v in variants) {
            productByVariant[v.id] = v.productId;
          }
        }

        for (final row in rows) {
          final viaVariant = row.linkedVariantId == null
              ? null
              : productByVariant[row.linkedVariantId!];
          final linked = viaVariant ?? row.linkedProductId;
          if (linked != null) linkedProductByComponent[row.id] = linked;
        }

        if (_config.linkedComponentLabel == LinkedComponentLabel.product &&
            linkedProductByComponent.isNotEmpty) {
          final linkedProducts = await (database.select(database.products)
                ..where((tbl) =>
                    tbl.id.isIn(linkedProductByComponent.values.toSet())))
              .get();
          final productNameById = {
            for (final p in linkedProducts) p.id: p.name,
          };
          // A linked variant names itself: "Coca 50cl" is more use at the bar
          // than the product it belongs to.
          final variantNameById = <int, String>{};
          if (variantIds.isNotEmpty) {
            final variantRows = await (database.select(database.productVariants)
                  ..where((tbl) => tbl.id.isIn(variantIds)))
                .get();
            for (final v in variantRows) {
              variantNameById[v.id] = v.name;
            }
          }
          for (final row in rows) {
            final linked = linkedProductByComponent[row.id];
            if (linked == null) continue;
            final name = (row.linkedVariantId == null
                    ? null
                    : variantNameById[row.linkedVariantId!]) ??
                productNameById[linked];
            // No catalogue name to be had (a product deleted under us): keep
            // the option's own name rather than printing a blank line.
            if (name != null && name.trim().isNotEmpty) {
              linkedNameByComponent[row.id] = name;
            }
          }
        }
      }

      for (final item in itemsToPrint) {
        final productStationIds = await stationsForProduct(item.productId);

        // A product-linked option prints on ITS product's stations, but only
        // the ones the parent line is not already going to — on the parent's
        // own ticket it is already there as a sub-line, and printing it twice
        // would have the kitchen make it twice.
        for (final comp in item.components) {
          final linkedProductId = linkedProductByComponent[comp.componentId];
          if (linkedProductId == null) continue;
          final linkedStations =
              (await stationsForProduct(linkedProductId)).difference(
                  productStationIds);
          if (linkedStations.isEmpty) continue;

          // The option's quantity is per parent unit, so the bar owes one per
          // unit being sent. In modifications-only mode that is the delta the
          // parent is printing, not the whole line.
          final parentUnits = item.kdsPrintQuantity ?? item.quantity;
          final units = parentUnits * comp.quantity;
          if (units <= 0) continue;

          final linkedItem = OrderItem(
            // No id: this line is not a persisted order product, and the
            // "already sent to the kitchen" bookkeeping must keep counting
            // the parent only.
            productId: linkedProductId,
            productName: linkedNameByComponent[comp.componentId] ?? comp.name,
            finalPrice: 0.0,
            quantity: units,
            state: item.state,
            note: '${_text('from_item', fallback: 'from')} ${item.displayName}',
          );

          for (final sid in linkedStations) {
            if (filterByStation && !stationIds.contains(sid)) continue;
            itemsByStationId.putIfAbsent(sid, () => []).add(linkedItem);
          }
        }

        if (productStationIds.isEmpty) {
          // Stationless product → "General" bucket, unless suppressed by config
          // (or we're printing a station-scoped ticket, which never includes it).
          if (!filterByStation && _config.printKdsUnassigned) {
            itemsByStationId.putIfAbsent(null, () => []).add(item);
          }
          continue;
        }

        // Add the item to EVERY station it belongs to so multi-station
        // products print on each relevant kitchen ticket.
        for (final sid in productStationIds) {
          if (filterByStation && !stationIds.contains(sid)) continue;
          itemsByStationId.putIfAbsent(sid, () => []).add(item);
        }
      }

      if (itemsByStationId.isEmpty) {
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return true;
      }

      // Whose items may appear on somebody ELSE's whole-order ticket.
      //
      // A line is withheld only when EVERY station making it is private: a
      // dish the bar and the kitchen share is still the kitchen's business.
      // Stationless items are never private — nobody claimed them, so the
      // pass is the one place they will be noticed.
      bool itemIsPrivate(OrderItem item) {
        final owners = [
          for (final entry in itemsByStationId.entries)
            if (entry.key != null && entry.value.contains(item)) entry.key!,
        ];
        if (owners.isEmpty) return false;
        return owners.every((sid) => ruleForStation(sid).private);
      }

      // Every line this ticket run could show, in the order they were rung.
      final everyPrintableItem = [
        for (final item in itemsToPrint)
          if (itemsByStationId.values.any((list) => list.contains(item))) item,
      ];

      // What each station's ticket SHOWS, which is no longer the same thing
      // as what it owns. Ownership still decides the delta — see below.
      final ticketItemsByStation = <int?, List<OrderItem>>{};
      for (final entry in itemsByStationId.entries) {
        final rule = ruleForStation(entry.key);
        if (rule.scope == StationTicketScope.ownItems || entry.key == null) {
          ticketItemsByStation[entry.key] = entry.value;
          continue;
        }
        ticketItemsByStation[entry.key] = [
          for (final item in everyPrintableItem)
            if (entry.value.contains(item) || !itemIsPrivate(item)) item,
        ];
      }

      // A station set to "whole order, always" prints even when it is cooking
      // nothing — that is the difference between it and "when used", and the
      // reason a pass gets a sheet for a drinks-only round it has no part in.
      for (final entry in _stationRules.entries) {
        if (entry.value.scope != StationTicketScope.wholeOrderAlways) continue;
        if (ticketItemsByStation.containsKey(entry.key)) continue;
        final shown = [
          for (final item in everyPrintableItem)
            if (!itemIsPrivate(item)) item,
        ];
        if (shown.isEmpty) continue;
        itemsByStationId.putIfAbsent(entry.key, () => <OrderItem>[]);
        ticketItemsByStation[entry.key] = shown;
      }

      // Resolve each station's target printer(s), then group station entries
      // by resolved printer address. Stations with no assignment share a
      // synthetic '__default__' key so they all collapse into the single
      // global-KDS print job (today's behavior). A station assigned SEVERAL
      // printers contributes its section to each of their groups, so the same
      // ticket comes out of every one of them.
      const defaultKey = '__default__';
      final Map<String, _KdsTarget?> targetsByKey = {};
      // Which station id first claimed each displayed name — see below.
      final Map<String, int?> sectionOwner = {};
      final Map<String, Map<String, List<OrderItem>>> printerGroups = {};
      // The same shape, holding only what each section's station actually
      // OWNS. Marking runs off this rather than off what was printed: a pass
      // sheet listing the pizza station's food must not be able to tell the
      // pizza station's delta that the food has been sent — otherwise a jam
      // at the pass silently reprints the kitchen's whole order next round,
      // and a success there hides one at the station that is cooking it.
      final Map<String, Map<String, List<OrderItem>>> ownedGroups = {};

      for (final entry in itemsByStationId.entries) {
        final sid = entry.key;
        final owned = entry.value;
        final items = ticketItemsByStation[sid] ?? owned;
        // "No printer (KDS only)" station → its items never reach any print
        // group; the KDS still shows them via the LAN server.
        if (isStationSilenced(sid)) continue;
        final targets =
            sid != null ? _resolveTargetsForStation(sid) : const <_KdsTarget>[];

        final stationName = sid == null
            ? _text('general', fallback: 'General')
            : await stationNameFor(sid);
        // Sections are keyed by the DISPLAYED name, so two stations that share
        // one — a duplicate from a catalogue sync, or a 'Bar' on each floor —
        // would silently pool their items under a single header and send the
        // lot to whichever printer got there first. Disambiguate rather than
        // merge: the kitchen can live with 'Bar #4', not with another
        // station's food on its ticket.
        final sectionName = sectionOwner.containsKey(stationName) &&
                sectionOwner[stationName] != sid
            ? '$stationName #$sid'
            : stationName;
        sectionOwner.putIfAbsent(stationName, () => sid);

        for (final target in targets.isEmpty
            ? const <_KdsTarget?>[null] // unresolved → global KDS printer
            : targets) {
          final key = target?.address ?? defaultKey;
          targetsByKey[key] = target;
          final group = printerGroups.putIfAbsent(
              key, () => <String, List<OrderItem>>{});
          group.putIfAbsent(sectionName, () => []).addAll(items);
          ownedGroups
              .putIfAbsent(key, () => <String, List<OrderItem>>{})
              .putIfAbsent(sectionName, () => [])
              .addAll(owned);
        }
      }

      // Count how many station sections each item appears in (across ALL
      // printers). Marking deferred until the end and only applied when an
      // item's every section succeeded — multi-station / multi-printer items
      // must not get half-marked.
      final stationsPerItem = <int, int>{};
      for (final printerGroup in ownedGroups.values) {
        for (final stationItems in printerGroup.values) {
          for (final item in stationItems) {
            if (item.id == null) continue;
            stationsPerItem[item.id!] = (stationsPerItem[item.id!] ?? 0) + 1;
          }
        }
      }
      final successesPerItem = <int, int>{};

      bool allSuccessful = true;
      int printerIdx = 0;

      for (final printerEntry in printerGroups.entries) {
        printerIdx++;
        final key = printerEntry.key;
        final itemsByStation = printerEntry.value;
        final target = targetsByKey[key];

        // For each physical printer, prefer the consolidated single-job path
        // when this printer has more than one station section — same Windows
        // USB driver guard that the original code relied on, but now scoped
        // per physical device rather than across all of them.
        final shouldConsolidate =
            _config.consolidateKdsJob && itemsByStation.length > 1;

        debugPrint(
            'Printing KDS group $printerIdx/${printerGroups.length} for '
            '${target?.address ?? 'default KDS printer'} '
            '(${itemsByStation.length} station(s), '
            'consolidated=$shouldConsolidate)');

        // Make sure the right printer is the active connected one for this
        // group. With an override, _ensurePrinterConnected handles cached-
        // handle invalidation when we're switching devices mid-run.
        final printerReady = await _ensurePrinterConnected(
          PrinterPurpose.kds,
          kdsOverride: target,
        );
        if (!printerReady) {
          allSuccessful = false;
          debugPrint(
              'Skipping group ${target?.address ?? 'default'} — printer not reachable');
          continue;
        }

        if (shouldConsolidate) {
          final ok = await _printConsolidatedKdsBatch(
            order: order,
            itemsByStation: itemsByStation,
            mode: resolvedMode,
            kdsOverride: target,
            purpose: purpose,
          );
          if (ok) {
            for (final stationItems
                in (ownedGroups[key] ?? const <String, List<OrderItem>>{})
                    .values) {
              for (final item in stationItems) {
                if (item.id == null) continue;
                successesPerItem[item.id!] =
                    (successesPerItem[item.id!] ?? 0) + 1;
              }
            }
          } else {
            allSuccessful = false;
          }
        } else {
          int sectionCount = 0;
          for (final stationEntry in itemsByStation.entries) {
            sectionCount++;
            final stationName = stationEntry.key;
            final stationItems = stationEntry.value;

            bool success = await _printKdsTicketForStation(
              order: order,
              stationName: stationName,
              items: stationItems,
              cashierName: cashierName,
              mode: resolvedMode,
              kdsOverride: target,
              purpose: purpose,
            );

            // Self-healing retry — same rationale as the previous loop: an
            // Nth print can hit a buffer-drain race, especially on
            // Windows USB drivers. After a failure, reconnect then retry
            // once with a cool-down.
            if (!success) {
              debugPrint(
                  'Station $stationName failed first attempt — reconnecting and retrying after cool-down');
              await Future.delayed(const Duration(milliseconds: 1500));
              final reconnected = await _ensurePrinterConnected(
                PrinterPurpose.kds,
                kdsOverride: target,
              );
              if (reconnected) {
                success = await _printKdsTicketForStation(
                  order: order,
                  stationName: stationName,
                  items: stationItems,
                  cashierName: cashierName,
                  mode: resolvedMode,
                  kdsOverride: target,
                  purpose: purpose,
                );
              }
            }

            if (success) {
              // Only what this station OWNS counts toward the delta — a
              // whole-order copy showing another station's food says nothing
              // about whether that station was told.
              for (final item
                  in (ownedGroups[key]?[stationName] ?? const <OrderItem>[])) {
                if (item.id == null) continue;
                successesPerItem[item.id!] =
                    (successesPerItem[item.id!] ?? 0) + 1;
              }
            } else {
              allSuccessful = false;
              debugPrint(
                  'Failed to print ticket for station: $stationName (after retry)');
            }

            if (sectionCount < itemsByStation.length) {
              await Future.delayed(const Duration(milliseconds: 800));
            }
          }
        }

        // Cool-down between PHYSICAL printers as well — same reasoning as
        // the inter-section pause, just at a coarser grain.
        if (printerIdx < printerGroups.length) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }

      // Mark only items whose every station section (across all printers)
      // succeeded. Dedupe via a Map<int, OrderItem> keyed by order_product
      // id since the same row appears under multiple stations.
      final markedById = <int, OrderItem>{};
      for (final printerGroup in printerGroups.values) {
        for (final stationItems in printerGroup.values) {
          for (final item in stationItems) {
            if (item.id == null) continue;
            if (successesPerItem[item.id!] == stationsPerItem[item.id!]) {
              markedById[item.id!] = item;
            }
          }
        }
      }
      if (markedById.isNotEmpty) {
        if (!isVoid) {
          await _markItemsAsPrinted(database, markedById.values.toList());
        }
      }

      debugPrint('KDS tickets printed: ${allSuccessful ? 'all successful' : 'some failed'} '
          '(marked ${markedById.length}/${stationsPerItem.length} items as printed)');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return allSuccessful;
    } catch (e, stackTrace) {
      debugPrint('Error printing KDS tickets: $e');
      debugPrint('Stack trace: $stackTrace');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return false;
    }
  });

  /// Filter items based on KDS print mode
  List<OrderItem> _filterItemsByMode(
    List<OrderItem> items,
    KdsPrintMode mode, {
    Set<int> paidLinesStillOwed = const {},
  }) {
    switch (mode) {
      case KdsPrintMode.full:
        // Return all items
        return items;
      case KdsPrintMode.modificationsOnly:
        // "Modifications" = units the kitchen hasn't seen yet on still-open
        // business. A paid line (ticketId != null) is by definition not a
        // modification. For everything else the *delta* between the current
        // quantity and what was already printed drives the ticket:
        //   * never-printed line → kdsPrintedQuantity == 0 → delta == quantity
        //     (prints in full, as before).
        //   * increased line (e.g. qty 1 → 3, already printed 1) → delta == 2
        //     → prints "2x" of just the added units.
        // The delta is stashed in the transient kdsPrintQuantity so rendering
        // uses it while quantity stays the true total for the printed-mark.
        final out = <OrderItem>[];
        for (final item in items) {
          if (item.ticketId != null &&
              !(item.id != null && paidLinesStillOwed.contains(item.id))) {
            continue;
          }
          final delta = item.quantity - item.kdsPrintedQuantity;
          if (delta > 0.0001) {
            out.add(item.copyWith(kdsPrintQuantity: delta));
          }
        }
        return out;
    }
  }

  /// Mark items as printed in the database
  /// The lines an order ticket should carry under [mode].
  ///
  /// [OrderTicketPrintMode.full] is every line untouched. `additionsOnly`
  /// keeps only lines with un-slipped units and rewrites each to that delta —
  /// `quantity` itself stays the true total (the mark-as-printed step needs
  /// it), so the delta rides in `orderTicketPrintQuantity`, exactly the way
  /// the KDS path carries its own delta in `kdsPrintQuantity`.
  ///
  /// Paid lines are skipped in additions-only mode: a settled line is on a
  /// payment receipt already, and repeating it on a running slip would ask
  /// the customer to pay for it twice.
  ///
  /// The returned lines carry the DELTA as their `quantity`, not the true
  /// total — so the item rows, the line prices and the totals block all price
  /// this round without every one of them needing to know about the mode.
  /// `orderTicketPrintQuantity` keeps the same value for callers that want to
  /// tell a delta line from a whole one. The true totals live on the original
  /// order, which is what [_markItemsAsOrderTicketPrinted] must be handed.
  /// Test seam for [_orderTicketLinesFor] — the delta selection is the part
  /// worth pinning; the ESC/POS layout around it needs a real printer.
  @visibleForTesting
  List<OrderItem> orderTicketLinesForTesting(
          CurrentOrder order, OrderTicketPrintMode mode) =>
      _orderTicketLinesFor(order, mode);

  List<OrderItem> _orderTicketLinesFor(
      CurrentOrder order, OrderTicketPrintMode mode) {
    if (mode == OrderTicketPrintMode.full) return order.items;
    final out = <OrderItem>[];
    for (final item in order.items) {
      if (item.ticketId != null) continue;
      final delta = item.quantity - item.orderTicketPrintedQuantity;
      if (delta > 0.0001) {
        out.add(item.copyWith(
          quantity: delta,
          orderTicketPrintQuantity: delta,
        ));
      }
    }
    return out;
  }

  /// Record that [items] reached a customer slip, so the next additions-only
  /// ticket carries only what came after them.
  ///
  /// Stores the TRUE total (`item.quantity`), not the delta that was printed —
  /// same rule as [_markItemsAsPrinted]: the column answers "how much of this
  /// line has been slipped", so a later quantity bump re-prints only the bump.
  Future<void> _markItemsAsOrderTicketPrinted(
      AppDatabase database, List<OrderItem> items) async {
    for (final item in items) {
      if (item.id == null) continue;
      try {
        await (database.update(database.orderProducts)
              ..where((tbl) => tbl.id.equals(item.id!)))
            .write(OrderProductsCompanion(
          orderTicketPrintedQuantity: Value(item.quantity),
        ));
      } catch (e) {
        debugPrint('Error marking item ${item.id} as slipped: $e');
      }
    }
  }

  /// Re-read each line's "already sent to the kitchen" cursor from the
  /// database, so the delta filter decides on committed state instead of on
  /// whatever the caller happened to read before it queued.
  ///
  /// Print JOBS are serialized ([_enqueue]); their CALLERS are not. Two waiter
  /// `add-product` calls in quick succession each load the whole order first,
  /// and the second load lands before the first job has stamped
  /// `kdsPrintedQuantity`. Both snapshots then swear the first line was never
  /// sent, and the kitchen makes it twice — three adds, three tickets of the
  /// item that went in first. Refreshing HERE, inside the queued job, shuts
  /// that window for every caller at once rather than per entry point.
  ///
  /// A line whose row cannot be found is passed through on its snapshot
  /// rather than dropped: [OrderRepository.updateOrder] re-inserts unpaid rows
  /// under fresh ids, so "no such row" is a stale id at least as often as it
  /// is a deletion, and printing nothing at all is the worse failure.
  Future<List<OrderItem>> _withDbPrintedQuantities(
      AppDatabase database, List<OrderItem> items) async {
    final ids = [for (final item in items) if (item.id != null) item.id!];
    if (ids.isEmpty) return items;

    Map<int, OrderProduct> rows;
    try {
      final fetched = await (database.select(database.orderProducts)
            ..where((tbl) => tbl.id.isIn(ids)))
          .get();
      rows = {for (final row in fetched) row.id: row};
    } catch (e) {
      debugPrint('Could not refresh KDS print cursors, using snapshot: $e');
      return items;
    }

    return [
      for (final item in items)
        if (item.id == null || rows[item.id] == null)
          item
        else
          item.copyWith(
            kdsPrintedQuantity: rows[item.id]!.kdsPrintedQuantity,
            // A line settled since the caller read it is no longer a
            // modification; _filterItemsByMode drops it on ticketId alone.
            ticketId: rows[item.id]!.ticketId,
          ),
    ];
  }

  /// Test seam for the refresh-then-filter pair the KDS path now runs — the
  /// half worth pinning, since the ESC/POS layout around it needs a printer.
  @visibleForTesting
  Future<List<OrderItem>> kdsLinesForTesting(
          AppDatabase database, CurrentOrder order, KdsPrintMode mode,
          {Set<int> paidLinesStillOwed = const {}}) async =>
      _filterItemsByMode(
          await _withDbPrintedQuantities(database, order.items), mode,
          paidLinesStillOwed: paidLinesStillOwed);

  Future<void> _markItemsAsPrinted(AppDatabase database, List<OrderItem> items) async {
    final now = DateTime.now();
    for (final item in items) {
      if (item.id != null) {
        try {
          await (database.update(database.orderProducts)
            ..where((tbl) => tbl.id.equals(item.id!)))
            .write(OrderProductsCompanion(
              kdsPrintedAt: Value(now),
              // Record the TRUE current total (not the delta) so a later
              // quantity bump only re-prints the newly-added units. item.quantity
              // stays the real total even when kdsPrintQuantity holds the delta.
              kdsPrintedQuantity: Value(item.quantity),
            ));
          debugPrint('Marked item ${item.id} as printed at $now (qty ${item.quantity})');
        } catch (e) {
          debugPrint('Error marking item ${item.id} as printed: $e');
        }
      }
    }
  }

  /// Build the ESC/POS byte buffer for a single station's KDS ticket
  /// (header, items, barcode, cut). Pure function — no dispatch, no DB
  /// access. Extracted from [_printKdsTicketForStation] so the
  /// consolidated-job path can concatenate per-station buffers into one
  /// dispatch.
  @visibleForTesting
  Future<List<int>> kdsTicketBytesForTesting({
    required CurrentOrder order,
    required List<OrderItem> items,
    required Generator generator,
    required AppDatabase database,
    KdsPrintPurpose purpose = KdsPrintPurpose.send,
  }) =>
      _buildKdsTicketBytesForStation(
        order: order,
        stationName: 'Test',
        items: items,
        mode: KdsPrintMode.full,
        generator: generator,
        purpose: purpose,
        database: database,
      );

  /// Each option's effective group mode, keyed by (productId, componentId)
  /// because a product can override its group's default. Resolved through
  /// [loadComponentGroupRules], the same path the modifier picker takes.
  /// Empty without a database, and a missing entry prints as QUANTITY.
  Future<Map<(int, int), ComponentSelectionType>> _optionSelectionTypes(
      List<OrderItem> items, AppDatabase? database) async {
    final result = <(int, int), ComponentSelectionType>{};
    if (database == null) return result;
    final componentIds = {
      for (final item in items)
        for (final comp in item.components) comp.componentId,
    };
    if (componentIds.isEmpty) return result;
    try {
      final rows = await (database.select(database.components)
            ..where((tbl) => tbl.id.isIn(componentIds)))
          .get();
      final groupByComponent = {
        for (final row in rows) row.id: row.componentGroupId,
      };
      final rulesByProduct = <int, Map<int?, ComponentGroupRule>>{};
      for (final item in items) {
        if (item.components.isEmpty) continue;
        final rules = rulesByProduct[item.productId] ??=
            await loadComponentGroupRules(database, item.productId);
        for (final comp in item.components) {
          final rule = rules[groupByComponent[comp.componentId]];
          if (rule != null) {
            result[(item.productId, comp.componentId)] = rule.selectionType;
          }
        }
      }
    } catch (e) {
      // A lookup failure must not cost the kitchen its ticket; the lines
      // just keep their quantities.
      debugPrint('Option selection types unavailable: $e');
    }
    return result;
  }

  Future<List<int>> _buildKdsTicketBytesForStation({
    required CurrentOrder order,
    required String stationName,
    required List<OrderItem> items,
    required KdsPrintMode mode,
    required Generator generator,
    KdsPrintPurpose purpose = KdsPrintPurpose.send,
    AppDatabase? database,
  }) async {
    final isVoid = purpose == KdsPrintPurpose.cancel;
    final selectionTypes = await _optionSelectionTypes(
        items, database ?? _catalogueDatabase);
    List<int> bytes = [];

    // Set code table based on current language (supports Arabic, French, English)
    bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

    // STATION NAME — the single element the kitchen reads at a glance, so it
    // stays double-size. Everything else follows the compact receipt layout
    // (normal text, left-aligned, thin separators) to save paper.
      final banner = _stationBanner(stationName);
      if (_containsArabic(banner)) {
        // Same raster path the item names and the order note already take:
        // ESC/POS cannot shape Arabic, and `_safe` would replace every letter
        // with '?' — which is exactly what an Arabic station printed.
        // Rendered bold at the raster's full size rather than double-width,
        // since a bitmap line cannot be scaled by the printer.
        bytes += await _arabicImageLine(generator, '*** $banner ***',
            align: PosAlign.center, bold: true);
      } else {
        bytes += generator.text(
          '*** ${_safe(banner).toUpperCase()} ***',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveFieldHeight('kds', 'stationName',
                fallback: PosTextSize.size2),
            width: _resolveFieldSize('kds', 'stationName',
                fallback: PosTextSize.size2),
          ),
        );
      }

      // A cancellation announces itself before anything else. Reverse video
      // and a rule above and below: this is read across a hot pass, at a
      // glance, and being mistaken for food to make is the one failure that
      // costs more than not printing it at all.
      if (isVoid) {
        bytes += generator.text(''.padLeft(32, '*'),
            styles: const PosStyles(align: PosAlign.center));
        final cancelled = _text('kds_cancelled', fallback: 'CANCELLED');
        if (_containsArabic(cancelled)) {
          bytes += await _arabicImageLine(generator, cancelled,
              align: PosAlign.center, bold: true);
        } else {
          bytes += generator.text(
            _safe(cancelled).toUpperCase(),
            styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              reverse: true,
              height: _resolveFieldHeight('kds', 'stationName',
                  fallback: PosTextSize.size2),
              width: _resolveFieldSize('kds', 'stationName',
                  fallback: PosTextSize.size2),
            ),
          );
        }
        bytes += generator.text(''.padLeft(32, '*'),
            styles: const PosStyles(align: PosAlign.center));
      }

      // Print mode indicator (only for modifications mode) — one compact line.
      if (!isVoid && mode == KdsPrintMode.modificationsOnly) {
        bytes += generator.text(
          '=== ${_text('new_items', fallback: 'NEW ITEMS')} ===',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            reverse: true, // Inverted colors for emphasis
          ),
        );
      }

      bytes += _sepMajor(generator);

      // Order number, time and the rest of the head block, in the order the
      // operator arranged them. Order code is left-aligned & bold like the
      // receipt header; table stays bold because it is the second thing the
      // runner looks for.
      final orderNumber = await _orderNumberFor('kds',
          known: order.sessionOrderNo, orderId: order.orderId);
      bytes += _emitZone('kds', 'info', {
        'orderCode': () => generator.text(
              '${_text('order', fallback: 'ORDER')} #${_safe(order.orderCode ?? "N/A")}',
              styles: PosStyles(
                align: PosAlign.left,
                bold: true,
                height: _resolveFieldHeight('kds', 'orderCode'),
                width: _resolveFieldSize('kds', 'orderCode'),
              ),
            ),
        'orderNumber': () => orderNumber == null
            ? const <int>[]
            : generator.text(
                '${_text('order_number', fallback: 'No')} #$orderNumber',
                styles: PosStyles(
                  align: PosAlign.left,
                  bold: true,
                  height: _resolveFieldHeight('kds', 'orderNumber'),
                  width: _resolveFieldSize('kds', 'orderNumber'),
                ),
              ),
        'time': () => generator.text(
              '${_text('time', fallback: 'Time')}: ${_formatKdsStamp(DateTime.now())}',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('kds', 'time'),
                width: _resolveFieldSize('kds', 'time'),
              ),
            ),
        // The kitchen calls the waiter, not the cashier — so the KDS ticket
        // carries the waiter and never the cashier. Bold: on a busy pass it is
        // the line that says who to shout for.
        'waiter': () => (order.waiterName ?? '').trim().isEmpty
            ? const <int>[]
            : generator.text(
                '${_text('waiter', fallback: 'Waiter')}: ${_safe(order.waiterName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  bold: true,
                  height: _resolveFieldHeight('kds', 'waiter'),
                  width: _resolveFieldSize('kds', 'waiter'),
                ),
              ),
        'orderType': () => generator.text(
              '${_text('type', fallback: 'Type')}: ${_getOrderTypeText(order.type, uppercase: true)}',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('kds', 'orderType'),
                width: _resolveFieldSize('kds', 'orderType'),
              ),
            ),
        'table': () => order.tableName == null
            ? const <int>[]
            : generator.text(
                '${_text('table', fallback: 'TABLE')}: ${_safe(order.tableName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  bold: true,
                  height: _resolveFieldHeight('kds', 'table'),
                  width: _resolveFieldSize('kds', 'table'),
                ),
              ),
        'persons': () => generator.text(
              '${_text('persons', fallback: 'Persons')}: ${order.numberOfPersons}',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('kds', 'persons'),
                width: _resolveFieldSize('kds', 'persons'),
              ),
            ),
        'customerName': () => order.customerName == null
            ? const <int>[]
            : generator.text(
                '${_text('customer', fallback: 'Customer')}: ${_safe(order.customerName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight('kds', 'customerName'),
                  width: _resolveFieldSize('kds', 'customerName'),
                ),
              ),
        'customerPhone': () =>
            (order.customerPhone == null || order.customerPhone!.isEmpty)
                ? const <int>[]
                : generator.text(
                    '${_text('phone', fallback: 'Phone')}: ${_safe(order.customerPhone)}',
                    styles: PosStyles(
                      align: PosAlign.left,
                      height: _resolveFieldHeight('kds', 'customerPhone'),
                      width: _resolveFieldSize('kds', 'customerPhone'),
                    ),
                  ),
      });

      // Order-level note, above the items and double-width, because it usually
      // changes how the whole ticket is made ("allergy: nuts", "serve
      // together"). Per-item notes still print inline with their line.
      if (order.hasNote && _fieldOn('kds', 'orderNote')) {
        bytes += _sepMinor(generator);
        bytes += generator.text(
          '** ${_text('order_note', fallback: 'ORDER NOTE')} **',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveFieldHeight('kds', 'orderNote'),
            width: _resolveFieldSize('kds', 'orderNote'),
          ),
        );
        if (_containsArabic(order.note)) {
          bytes += await _arabicImageLine(generator, order.note!,
              align: PosAlign.center, bold: true);
        } else {
          bytes += generator.text(
            _safe(order.note),
            styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: _resolveFieldHeight('kds', 'orderNote', isHeader: true),
              width: _resolveFieldSize('kds', 'orderNote', isHeader: true),
            ),
          );
        }
      }

      bytes += _sepMinor(generator);

      // Items — bold names at normal size, tight lines (no blank line between
      // items) so the ticket stays short. The qty prefix keeps them separable.
      //
      // Courses (entrée / plat / dessert) split this into sections, but ONLY
      // when the lines on this ticket actually carry more than one — see
      // [shouldSplitByCourse]. A ticket with one line, or with every line on
      // the same course, or with none tagged at all, prints exactly as it
      // always has. That is the whole contract of the feature: it costs
      // nothing until somebody uses it.
      //
      // Note the sections are decided from the lines being PRINTED, not from
      // the order: the bar's ticket does not sprout a "Starter" heading
      // because the kitchen's half of the same order had one.
      final splitCourses =
          shouldSplitByCourse([for (final i in items) i.courseNo]);
      // Flattened to (header?, item) rows so the body below is untouched —
      // one section header is emitted before the first line that needs it.
      final rows = <({String? header, OrderItem item})>[];
      if (splitCourses) {
        groupByCourse<OrderItem>(items, (i) => i.courseNo)
            .forEach((courseNo, own) {
          final course = OrderCourse.fromNumber(courseNo);
          final label = course == null
              ? _text('other_items', fallback: 'Other')
              : _text(course.labelKey, fallback: 'Course $courseNo');
          for (var i = 0; i < own.length; i++) {
            rows.add((header: i == 0 ? label : null, item: own[i]));
          }
        });
      } else {
        for (final item in items) {
          rows.add((header: null, item: item));
        }
      }

      for (final row in rows) {
        if (row.header != null) {
          bytes += _sepMinor(generator);
          if (_containsArabic(row.header!)) {
            // Same rule as the station banner: ESC/POS cannot shape Arabic,
            // and `_safe` would turn every letter into '?'.
            bytes += await _arabicImageLine(generator, '- ${row.header} -',
                align: PosAlign.center, bold: true);
          } else {
            bytes += generator.text(
              '- ${_safe(row.header).toUpperCase()} -',
              styles: PosStyles(
                align: PosAlign.center,
                bold: true,
                height: _resolveFieldHeight('kds', 'items'),
                width: _resolveFieldSize('kds', 'items'),
              ),
            );
          }
        }
        final item = row.item;
        // In modifications-only mode kdsPrintQuantity carries the delta (added
        // units); otherwise fall back to the full quantity.
        final printQty = item.kdsPrintQuantity ?? item.quantity;
        // A leading minus on every cancelled line: the banner says what the
        // ticket is, this says it again per line, for the cook who only ever
        // sees the middle of the paper.
        final qtyLabel =
            '${isVoid ? '- ' : ''}${formatQty(printQty)}x';
        if (_containsArabic(item.displayName)) {
          bytes += await _arabicImageLine(
              generator, '$qtyLabel ${item.displayName}',
              align: PosAlign.right, bold: true);
        } else {
          bytes += generator.text(
            '$qtyLabel ${_safe(item.displayName)}',
            styles: PosStyles(
              align: PosAlign.left,
              bold: true,
              height: _resolveFieldHeight('kds', 'items'),
              width: _resolveFieldSize('kds', 'items'),
            ),
          );
        }

        // Components
        for (final comp in item.components) {
          // A charged removal is money, not food. The kitchen learns the
          // default was taken off from the zero-quantity row below it; a
          // second line here would read as something to put on the plate.
          if (comp.removalCharge) continue;

          // Zero quantity IS the removal: say so in words rather than
          // printing "+ Cheese x0", which reads as a mistake.
          if (comp.quantity <= 0) {
            final without =
                '${_text('without', fallback: 'NO')} ${comp.name}';
            if (_containsArabic(comp.name)) {
              bytes += await _arabicImageLine(generator, '*** $without ***',
                  align: PosAlign.right, bold: true);
            } else {
              bytes += generator.text(
                '   *** ${_safe(without.toUpperCase())} ***',
                styles: PosStyles(
                  align: PosAlign.left,
                  bold: true,
                  height: _resolveFieldHeight('kds', 'items'),
                  width: _resolveFieldSize('kds', 'items'),
                ),
              );
            }
            continue;
          }

          final label = optionLineLabel(
              comp.name,
              comp.quantity,
              selectionTypes[(item.productId, comp.componentId)] ??
                  ComponentSelectionType.quantity);
          if (_containsArabic(comp.name)) {
            bytes += await _arabicImageLine(generator, '+ $label',
                align: PosAlign.right);
          } else {
            bytes += generator.text(
              '   + ${_safe(label)}',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight('kds', 'items'),
                width: _resolveFieldSize('kds', 'items'),
              ),
            );
          }
        }

        // Note - highlighted for kitchen
        if (item.note != null && item.note!.isNotEmpty) {
          if (_containsArabic(item.note)) {
            bytes += await _arabicImageLine(
                generator, '*** ${item.note} ***',
                align: PosAlign.right, bold: true);
          } else {
            bytes += generator.text(
              '   *** ${_safe(item.note)} ***',
              styles: PosStyles(
                align: PosAlign.left,
                bold: true,
                height: _resolveFieldHeight('kds', 'items'),
                width: _resolveFieldSize('kds', 'items'),
              ),
            );
          }
        }
      }

      bytes += _sepMinor(generator);

      // Add barcode if order code exists — gated by the KDS "Ticket content"
      // toggle so kitchens that don't scan can reclaim the paper.
      if (order.orderCode != null &&
          order.orderCode!.isNotEmpty &&
          _fieldOn('kds', 'barcode')) {
        bytes += generator.text(
          order.orderCode!,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveFieldHeight('kds', 'barcode'),
            width: _resolveFieldSize('kds', 'barcode'),
          ),
        );
        bytes += generator.barcode(
          Barcode.code128(order.orderCode!.split('')),
          height: 60,
          align: PosAlign.center,
        );
      }

      bytes += generator.emptyLines(1);
      bytes += generator.cut();

      return bytes;
  }

  /// Print a single station's KDS ticket (build bytes + dispatch). Returns
  /// true only when the printer accepted the bytes. The caller is
  /// responsible for stamping `kdsPrintedAt` on success — see
  /// [printKdsTicket] for the multi-station bookkeeping.
  Future<bool> _printKdsTicketForStation({
    required CurrentOrder order,
    required String stationName,
    required List<OrderItem> items,
    required String? cashierName,
    KdsPrintMode mode = KdsPrintMode.modificationsOnly,
    _KdsTarget? kdsOverride,
    KdsPrintPurpose purpose = KdsPrintPurpose.send,
  }) async {
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      final bytes = await _buildKdsTicketBytesForStation(
        order: order,
        stationName: stationName,
        items: items,
        mode: mode,
        generator: generator,
        purpose: purpose,
      );

      debugPrint(
        'Attempting to print KDS ticket for $stationName. Bytes length: ${bytes.length}',
      );

      final ok =
          await _dispatchBytes(PrinterPurpose.kds, bytes, kdsOverride: kdsOverride);
      if (!ok) {
        // CRITICAL: do NOT pretend success. The caller (printKdsTicket)
        // only stamps `kdsPrintedAt` on items when this returns true; if
        // we lied here, the items would be marked printed even though no
        // paper came out and `KdsPrintMode.modificationsOnly` would
        // permanently skip them on retry.
        debugPrint(
            'KDS dispatch failed for $stationName — items will NOT be marked printed.');
        return false;
      }

      debugPrint('KDS ticket for $stationName printed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing KDS ticket for $stationName: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Build all station tickets into one buffer and dispatch as a SINGLE
  /// print job, with paper cuts between stations. Used when
  /// `_config.consolidateKdsJob` is enabled.
  ///
  /// Rationale: on Windows USB drivers, sending three back-to-back
  /// `printData` calls creates three separate spool jobs. Some drivers
  /// can't sequence rapid jobs cleanly — the third hits the driver before
  /// the second has fully cleared, the spool stalls, and `printData` blocks
  /// past the 10s timeout. One driver job side-steps that class of failure
  /// entirely; the printer sees one stream of bytes, performs the cuts at
  /// the section boundaries, and the kitchen still gets visually separate
  /// tickets.
  ///
  /// Returns true iff the single dispatch succeeded. There is no per-
  /// station partial success in this mode — by design.
  Future<bool> _printConsolidatedKdsBatch({
    required CurrentOrder order,
    required Map<String, List<OrderItem>> itemsByStation,
    required KdsPrintMode mode,
    _KdsTarget? kdsOverride,
    KdsPrintPurpose purpose = KdsPrintPurpose.send,
  }) async {
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];
      for (final entry in itemsByStation.entries) {
        bytes += await _buildKdsTicketBytesForStation(
          order: order,
          stationName: entry.key,
          items: entry.value,
          mode: mode,
          generator: generator,
          purpose: purpose,
        );
      }
      debugPrint(
        'Attempting consolidated KDS print: ${itemsByStation.length} stations, '
        '${bytes.length} bytes total',
      );
      final ok =
          await _dispatchBytes(PrinterPurpose.kds, bytes, kdsOverride: kdsOverride);
      if (!ok) {
        debugPrint('Consolidated KDS dispatch failed — items will NOT be marked printed.');
      }
      return ok;
    } catch (e, stackTrace) {
      debugPrint('Error in consolidated KDS print: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Print ticket receipt
  Future<bool> printTicketReceipt({
    required int ticketId,
    required String ticketNumber,
    required double amount,
    /// Delivery charge collected with this ticket. Printed as its own line
    /// under the products total and added into the "total collected" figure —
    /// never folded into [amount], which is the products figure the ticket row
    /// and every sales total are built from. Null = no fee on this ticket.
    double? deliveryFee,
    /// VAT already included in [amount]. Printed as an informational line
    /// ("dont TVA") when the `tva` ticket field is on. Null or 0 prints
    /// nothing — a zero-rated ticket shouldn't claim a tax line.
    double? tvaAmount,
    /// Why the reduction was given, printed under it when the operator has
    /// that setting on. Null or blank prints nothing.
    String? discountReason,
    /// Every reduction already taken off [amount]: per-line discounts plus the
    /// order-level remise, as one figure.
    ///
    /// The paid receipt had no discount row at all, so a discounted sale
    /// printed only its reduced total and the customer had no way to see what
    /// came off — and neither did anyone auditing the till. Null or 0 prints
    /// nothing, so an undiscounted sale looks exactly as it did.
    double? discountAmount,
    /// Cash the customer handed over and what goes back to them. Only known
    /// for a tender the cashier actually keyed, so both are nullable and
    /// each prints independently of the other.
    double? amountGiven,
    double? changeDue,
    required String paymentMethod,
    required DateTime createdAt,
    required List<Map<String, dynamic>> items,
    String? currency,
    String? orderCode,
    String? cashierName,
    /// Who is serving the table, printed beside the cashier. The receipt
    /// builders have no CurrentOrder to read it from, unlike the order and
    /// KDS tickets, so it travels as its own argument. Null / blank prints
    /// nothing, which is what a counter shop wants.
    String? waiterName,
    String? storeName,
    // Store-level fields rendered in the header next to storeName so the
    // payment receipt has the same identity block as the order ticket.
    String? storeAddress,
    String? storePhone,
    String? customerName,
    String? customerPhone,
    String? deliveryAddress,
    // Order-context fields rendered in the metadata section under the
    // ticket #. Match the same layout as printOrderReceipt so the two
    // documents look like they belong to the same family.
    String? tableName,
    int? numberOfPersons,
    String? orderType,
    bool storeCopy = false,
    bool isReprint = false,
  }) => _enqueue(() async {
    // Try to ensure printer is connected
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for ticket');
      return false;
    }

    // Same identity resolution as printOrderReceipt — see [_storeField].
    storeName = _storeField(storeName, 'business_name');
    storeAddress = _storeField(storeAddress, 'business_address');
    storePhone = _storeField(storePhone, 'business_phone');
    final storeIce = _storeField(null, 'business_ice');

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing', fallback: 'Printing...'));

    try {
      final currencySymbol = _getCurrency(currency);
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Set code table based on current language (supports Arabic, French, English)
      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      // Which field-visibility profile applies to this document.
      final tkt = storeCopy ? 'store' : 'customer';

      // Print business logo if available
      bytes += _printLogoHeader(generator);

      // Header — store identity block. Same shape as printOrderReceipt
      // so the payment receipt and the order ticket carry matching
      // letterheads.
      if (storeName != null) {
        bytes += generator.text(
          _safe(storeName),
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveFieldHeight(tkt, 'storeName', isHeader: true),
            width: _resolveFieldSize(tkt, 'storeName', isHeader: true),
          ),
        );
      }
      bytes += _emitZone(tkt, 'header', {
        'storeAddress': () =>
            storeAddress == null
                ? const <int>[]
                : _wrappedText(
                    generator,
                    _safe(storeAddress),
                    PosStyles(
                      align: PosAlign.center,
                      height: _resolveFieldHeight(tkt, 'storeAddress'),
                      width: _resolveFieldSize(tkt, 'storeAddress'),
                    ),
                  ),
        'storeIce': () => storeIce == null
            ? const <int>[]
            : _wrappedText(
                generator,
                'ICE : ${_safe(storeIce)}',
                PosStyles(
                  align: PosAlign.center,
                  height: _resolveFieldHeight(tkt, 'storeIce'),
                  width: _resolveFieldSize(tkt, 'storeIce'),
                ),
              ),
        'storePhone': () => storePhone == null
            ? const <int>[]
            : generator.text(
                '${_text('tel', fallback: 'Tel')}: ${_safe(storePhone)}',
                styles: PosStyles(
                  align: PosAlign.center,
                  height: _resolveFieldHeight(tkt, 'storePhone'),
                  width: _resolveFieldSize(tkt, 'storePhone'),
                ),
              ),
      });

      bytes += generator.text(
        _text('payment_receipt', fallback: 'PAYMENT RECEIPT'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      // Store copy / reprint banners
      if (storeCopy) {
        bytes += generator.text(
          _text('store_copy', fallback: 'STORE COPY'),
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveHeaderHeight(),
            width: _resolveHeaderSize(),
          ),
        );
      }
      if (isReprint && _config.reprintWatermark) {
        bytes += generator.text(
          '*** ${_text('duplicate_ticket', fallback: 'DUPLICATA')} ***',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }

      // Custom ticket header
      bytes += await _customTextLines(generator,
          _customTicketText(SettingsKeys.ticketHeader, ticket: tkt));

      bytes += _sepMinor(generator);

      // Ticket info
      bytes += generator.text(
        '${_text('ticket', fallback: 'Ticket')} #$ticketNumber',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      // Info rows, in the operator's configured order.
      final orderNumber = await _orderNumberFor(tkt, ticketId: ticketId);
      bytes += _emitZone(tkt, 'info', {
        'orderCode': () => (orderCode == null || orderCode.isEmpty)
            ? const <int>[]
            : generator.text(
                '${_text('order', fallback: 'Order')}: ${_safe(orderCode)}',
                styles: PosStyles(
                  align: PosAlign.center,
                  bold: true,
                  height: _resolveFieldHeight(tkt, 'orderCode'),
                  width: _resolveFieldSize(tkt, 'orderCode'),
                ),
              ),
        'orderNumber': () => orderNumber == null
            ? const <int>[]
            : generator.text(
                '${_text('order_number', fallback: 'No')} #$orderNumber',
                styles: PosStyles(
                  align: PosAlign.center,
                  bold: true,
                  height: _resolveFieldHeight(tkt, 'orderNumber'),
                  width: _resolveFieldSize(tkt, 'orderNumber'),
                ),
              ),
        'date': () => generator.text(
              '${_text('date', fallback: 'Date')}: ${_formatDateTime(createdAt)}',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight(tkt, 'date'),
                width: _resolveFieldSize(tkt, 'date'),
              ),
            ),
        'cashier': () => cashierName == null
            ? const <int>[]
            : generator.text(
                '${_translate("cashier")}: ${_safe(cashierName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight(tkt, 'cashier'),
                  width: _resolveFieldSize(tkt, 'cashier'),
                ),
              ),
        'waiter': () => (waiterName ?? '').trim().isEmpty
            ? const <int>[]
            : generator.text(
                '${_translate("waiter")}: ${_safe(waiterName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight(tkt, 'waiter'),
                  width: _resolveFieldSize(tkt, 'waiter'),
                ),
              ),
        'orderType': () => (orderType == null || orderType.isEmpty)
            ? const <int>[]
            : generator.text(
                '${_text('type', fallback: 'Type')}: ${_getOrderTypeText(orderType)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight(tkt, 'orderType'),
                  width: _resolveFieldSize(tkt, 'orderType'),
                ),
              ),
        'table': () => (tableName == null || tableName.trim().isEmpty)
            ? const <int>[]
            : generator.text(
                '${_translate("table")}: ${_safe(tableName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight(tkt, 'table'),
                  width: _resolveFieldSize(tkt, 'table'),
                ),
              ),
        'persons': () => (numberOfPersons == null || numberOfPersons <= 1)
            ? const <int>[]
            : generator.text(
                '${_text('persons', fallback: 'Persons')}: $numberOfPersons',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight(tkt, 'persons'),
                  width: _resolveFieldSize(tkt, 'persons'),
                ),
              ),
        'customerName': () => customerName == null
            ? const <int>[]
            : generator.text(
                '${_text('customer', fallback: 'Customer')}: ${_safe(customerName)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight(tkt, 'customerName'),
                  width: _resolveFieldSize(tkt, 'customerName'),
                ),
              ),
        'customerPhone': () => (customerPhone == null || customerPhone.isEmpty)
            ? const <int>[]
            : generator.text(
                '${_text('phone', fallback: 'Phone')}: ${_safe(customerPhone)}',
                styles: PosStyles(
                  align: PosAlign.left,
                  height: _resolveFieldHeight(tkt, 'customerPhone'),
                  width: _resolveFieldSize(tkt, 'customerPhone'),
                ),
              ),
        'deliveryAddress': () =>
            (deliveryAddress == null || deliveryAddress.trim().isEmpty)
                ? const <int>[]
                : _wrappedText(
                    generator,
                    '${_text('delivery_address', fallback: 'Delivery address')}: ${_safe(deliveryAddress)}',
                    PosStyles(
                      align: PosAlign.left,
                      bold: true,
                      height: _resolveFieldHeight(tkt, 'deliveryAddress'),
                      width: _resolveFieldSize(tkt, 'deliveryAddress'),
                    ),
                  ),
        'paymentMethod': () => generator.text(
              '${_text('payment', fallback: 'Payment')}: $paymentMethod',
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight(tkt, 'paymentMethod'),
                width: _resolveFieldSize(tkt, 'paymentMethod'),
              ),
            ),
      });

      bytes += _sepMinor(generator);

      // Items
      for (final item in items) {
        final rawName = item['name'] as String? ?? 'Unknown';
        final qty = formatQty(((item['quantity'] ?? 1) as num).toDouble());
        final price = item['price'] ?? 0.0;
        final priceText =
            CurrencyFormatter.formatWithCurrency(price as double, currencySymbol);

        if (_containsArabic(rawName)) {
          // Arabic name → its own RTL image line (correct shaping + direction),
          // then quantity + price as a normal text row underneath.
          bytes += await _arabicImageLine(generator, rawName,
              align: PosAlign.right, bold: true);
          bytes += generator.row([
            PosColumn(
              text: '${qty}x',
              width: 6,
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight(tkt, 'items'),
                width: _resolveFieldSize(tkt, 'items'),
              ),
            ),
            PosColumn(
              text: priceText,
              width: 6,
              styles: PosStyles(
                align: PosAlign.right,
                height: _resolveFieldHeight(tkt, 'items'),
                width: _resolveFieldSize(tkt, 'items'),
              ),
            ),
          ]);
        } else {
          bytes += generator.row([
            PosColumn(
              text: '${qty}x ${_safe(rawName)}',
              width: 8,
              styles: PosStyles(
                align: PosAlign.left,
                height: _resolveFieldHeight(tkt, 'items'),
                width: _resolveFieldSize(tkt, 'items'),
              ),
            ),
            PosColumn(
              text: priceText,
              width: 4,
              styles: PosStyles(
                align: PosAlign.right,
                height: _resolveFieldHeight(tkt, 'items'),
                width: _resolveFieldSize(tkt, 'items'),
              ),
            ),
          ]);
        }

        // Add components if available
        final components = item['components'] as List<dynamic>?;
        if (components != null && components.isNotEmpty) {
          for (final comp in components) {
            final rawCompName = comp['name'] as String? ?? '';
            final compQty = comp['quantity'] ?? 1;
            final compPrice = comp['price'] ?? 0.0;
            final isRemoval = comp['removalCharge'] as bool? ?? false;
            // The signal row is a message to the server, not to the customer;
            // the charged row beside it is what they need to see.
            if (!isRemoval && compQty is num && compQty <= 0) continue;
            final priceSuffix = compPrice > 0
                ? ' (+${CurrencyFormatter.formatWithCurrency(compPrice * compQty, currencySymbol)})'
                : '';
            if (isRemoval) {
              // Said plainly: they asked for it off and are still paying for
              // it. A line that looked like an added extra would be a
              // complaint at the counter.
              bytes += generator.text(
                '  ${_safe('${_text('without', fallback: 'NO')} '
                    '$rawCompName')}$priceSuffix',
                styles: PosStyles(
                  align: PosAlign.left,
                  fontType: PosFontType.fontB,
                  height: _resolveFieldHeight(tkt, 'items'),
                  width: _resolveFieldSize(tkt, 'items'),
                ),
              );
              continue;
            }

            if (_containsArabic(rawCompName)) {
              bytes += await _arabicImageLine(
                generator,
                '+ ${compQty}x $rawCompName$priceSuffix',
                align: PosAlign.right,
                small: true,
              );
            } else {
              bytes += generator.text(
                '  + ${compQty}x ${_safe(rawCompName)}$priceSuffix',
                styles: PosStyles(
                  align: PosAlign.left,
                  fontType: PosFontType.fontB,
                  height: _resolveFieldHeight(tkt, 'items'),
                  width: _resolveFieldSize(tkt, 'items'),
                ),
              );
            }
          }
        }
      }

      // Shared two-column line for the money block. Body-sized so the PAID
      // line stays the thing the customer's eye lands on.
      List<int> totalsRow(String label, double value, [String field = '']) =>
          generator.row([
            PosColumn(
              text: label,
              width: 6,
              styles: PosStyles(
                height: _resolveFieldHeight(tkt, field),
                width: _resolveFieldSize(tkt, field),
              ),
            ),
            PosColumn(
              text: CurrencyFormatter.formatWithCurrency(value, currencySymbol),
              width: 6,
              styles: PosStyles(
                align: PosAlign.right,
                height: _resolveFieldHeight(tkt, field),
                width: _resolveFieldSize(tkt, field),
              ),
            ),
          ]);

      // What came off, and the tax inside the price — ABOVE the total, the
      // way the order ticket reads and the way a customer reads down a
      // receipt: the adjustments, then the figure they actually paid. They
      // used to sit underneath it, where a reduction looks like an
      // afterthought rather than part of how the total was reached.
      final adjustments = _emitZone(tkt, 'totals', {
        // Guarded on > 0.005 rather than > 0: a rounding crumb is not a
        // reduction and must not put a "-0.00" line on the receipt.
        'discount': () => (discountAmount == null || discountAmount <= 0.005)
            ? const <int>[]
            : totalsRow('${_text('discount', fallback: 'Discount')}:',
                    -discountAmount, 'discount') +
                _discountReasonLines(generator, discountReason),
        'tva': () => (tvaAmount == null || tvaAmount <= 0)
            ? const <int>[]
            : totalsRow('${_text('vat_included', fallback: 'Incl. VAT')}:',
                tvaAmount, 'tva'),
      });
      if (adjustments.isNotEmpty) {
        bytes += generator.emptyLines(1);
        bytes += adjustments;
      }

      bytes += _sepMinor(generator);

      // Total
      bytes += generator.row([
        PosColumn(
          text: '${_text('paid', fallback: 'PAID')}:',
          width: 6,
          styles: PosStyles(
            bold: true,
            height: _resolveFieldHeight(tkt, 'total', isHeader: true),
            width: _resolveFieldSize(tkt, 'total', isHeader: true),
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(amount, currencySymbol),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: _resolveFieldHeight(tkt, 'total', isHeader: true),
            width: _resolveFieldSize(tkt, 'total', isHeader: true),
          ),
        ),
      ]);

      // Delivery fee, then the real total collected. Printed whenever a fee
      // rides on this ticket: the PAID line above is products only, so without
      // these two lines the receipt would not add up to the money taken.
      if (deliveryFee != null && deliveryFee > 0) {
        bytes += totalsRow(
            '${_text('delivery_fee', fallback: 'Delivery fee')}:', deliveryFee);
        bytes += generator.row([
          PosColumn(
            text: '${_text('total_collected', fallback: 'TOTAL')}:',
            width: 6,
            styles: PosStyles(
              bold: true,
              height: _resolveFieldHeight(tkt, 'total', isHeader: true),
              width: _resolveFieldSize(tkt, 'total', isHeader: true),
            ),
          ),
          PosColumn(
            text: CurrencyFormatter.formatWithCurrency(
                amount + deliveryFee, currencySymbol),
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              bold: true,
              height: _resolveFieldHeight(tkt, 'total', isHeader: true),
              width: _resolveFieldSize(tkt, 'total', isHeader: true),
            ),
          ),
        ]);
      }

      // The tender: what was handed over and what went back. Below the
      // total, because that is the order the exchange happens in.
      final tender = _emitZone(tkt, 'totals', {
        'amountGiven': () => (amountGiven == null || amountGiven <= 0)
            ? const <int>[]
            : totalsRow('${_text('cash_given', fallback: 'Cash given')}:',
                amountGiven, 'amountGiven'),
        // A zero change line is still worth printing when a tender was keyed
        // - it's the proof the customer paid the exact amount.
        'change': () =>
            (changeDue == null || changeDue < 0 || amountGiven == null)
                ? const <int>[]
                : totalsRow('${_text('change_due', fallback: 'Change')}:',
                    changeDue, 'change'),
      });
      if (tender.isNotEmpty) {
        bytes += generator.emptyLines(1);
        bytes += tender;
      }

      // No hardcoded thank-you line — only the configured ticket footer
      // (below) prints, so the store controls all footer wording.

      // Add barcode if order code exists
      if (orderCode != null && orderCode.isNotEmpty && _fieldOn(tkt, 'barcode')) {
        bytes += generator.emptyLines(1);
        bytes += generator.text(
          orderCode,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveFieldHeight(tkt, 'barcode'),
            width: _resolveFieldSize(tkt, 'barcode'),
          ),
        );
        bytes += generator.barcode(
          Barcode.code128(orderCode.split('')),
          height: 80,
          align: PosAlign.center,
        );
      }

      // Print custom footer text if configured
      final footer = await _customTextLines(generator,
          _customTicketText(SettingsKeys.ticketFooter, ticket: tkt));
      if (footer.isNotEmpty) {
        bytes += generator.emptyLines(1);
        bytes += footer;
      }

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      debugPrint(
        'Attempting to print ticket receipt. Bytes length: ${bytes.length}',
      );

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint('Ticket receipt dispatch failed — no paper came out.');
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return false;
      }

      debugPrint('Ticket receipt printed successfully');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing ticket receipt: $e');
      debugPrint('Stack trace: $stackTrace');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return false;
    }
  });

  /// Helper method to get order type text
  /// Label for an order type, as printed on every ticket that carries a
  /// "Type:" line.
  ///
  /// DELIVERY used to fall through to the take-away branch, so a delivery
  /// order told the kitchen and the customer the wrong thing — "À emporter"
  /// in French, "Take Away" in English. An unknown or null type still reads
  /// as take away, which is what the POS defaults an order to.
  String _getOrderTypeText(String? type, {bool uppercase = false}) {
    switch (type) {
      case 'DINE_IN':
        return uppercase
            ? _text('dine_in_upper', fallback: 'DINE IN')
            : _text('dine_in', fallback: 'Dine In');
      case 'DELIVERY':
        return uppercase
            ? _text('delivery_upper', fallback: 'DELIVERY')
            : _text('delivery', fallback: 'Delivery');
      default:
        return uppercase
            ? _text('take_away_upper', fallback: 'TAKE AWAY')
            : _text('take_away', fallback: 'Take Away');
    }
  }

  /// Exposed for tests: the printed label for an order type, in the
  /// configured printing language.
  @visibleForTesting
  String debugOrderTypeText(String? type, {bool uppercase = false}) =>
      _getOrderTypeText(type, uppercase: uppercase);


  /// Find printer by address in available printers
  Printer? _findPrinterByAddress(String? address) {
    if (address == null) return null;
    try {
      return _availablePrinters.firstWhere((p) => p.address == address);
    } catch (_) {
      return null;
    }
  }

  /// Format date time for receipts
  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Format time only
  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  /// Day and time for a kitchen ticket: `19/09 14:32`.
  ///
  /// The year is left off deliberately — a ticket on the pass is hours old at
  /// most, so the year is a column of noise on a 58mm roll. The day is there
  /// because a ticket that sat overnight, or came off a device whose clock is
  /// wrong, is otherwise indistinguishable from one printed a minute ago.
  /// Seconds go too: nothing in a kitchen is decided on them.
  String _formatKdsStamp(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m $hh:$mm';
  }

  /// Test seam for [_formatKdsStamp] — the shape of the stamp is the part
  /// worth pinning; the ESC/POS row around it needs a printer.
  @visibleForTesting
  String kdsStampForTesting(DateTime dt) => _formatKdsStamp(dt);

  /// Format date only
  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  /// Print daily summary report
  Future<bool> printDailySummaryReport({
    required DailySummaryReport report,
    AppLocalizations? l10n,
    CurrencyFormatter? currencyFormatter,
    String? businessName,
    // 'Z' prints the day-close report; anything else — 'X' or null — prints
    // an X. A Z is a legal document that exists only once its Z is closed, so
    // it must be asked for explicitly: only printZReport (after the close) and
    // the reprint of a fully closed day do.
    String? reportType,
    /// What the floor still owes AT THE MOMENT OF PRINTING — open tables and
    /// parked orders. Deliberately not part of [report]: the summary is a
    /// closed-period statement of what was taken, while this is a live
    /// snapshot of what has not been. Null omits the block entirely.
    ///
    /// It belongs on this ticket because a cashier closing a shift has to
    /// hand something over, and the figure they are handing over is not in
    /// the takings — it is what is still sitting on the floor.
    UnpaidOrdersSummary? outstanding,
    /// The Z's printed identity, e.g. "2026-09-25 · Z1". Null omits the line.
    String? zLabel,
    /// A Z printed again after its close: stamped DUPLICATA, so a second copy
    /// can never pass for the original.
    bool isReprint = false,
  }) => _enqueue(() async {
    // Actively (re)establish the receipt printer connection — mirroring every
    // other print method. The previous null-check alone reported "not printed"
    // (or, with the dialog bug, a false "printed") whenever the socket had
    // dropped, even though the printer was reachable.
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for summary report');
      return false;
    }

    try {
      // Use printing language instead of passed-in l10n
      final printL10n = _getPrintingL10n();

      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Set code table based on current language (supports Arabic, French, English)
      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      // Print business logo if available
      bytes += _printLogoHeader(generator);

      // ─────────────────────────────────────────────────────────────────
      // Banded X / Z report. The two differ only in their heading and
      // footer: an X is the same figures taken mid-shift, which is why the
      // sections below never ask which one they are on.
      // ─────────────────────────────────────────────────────────────────
      final s = report.sections;
      final isX = reportType != 'Z';
      final money = currencyFormatter ?? CurrencyFormatter(_getCurrency(null));
      String cash(double v) => money.format(v);

      final sep = ''.padLeft(32, '=');
      final thin = ''.padLeft(32, '-');

      List<int> rule() =>
          generator.text(sep, styles: const PosStyles(align: PosAlign.center));
      List<int> thinRule() =>
          generator.text(thin, styles: const PosStyles(align: PosAlign.center));

      /// A label on the left and its value hard right — the shape of almost
      /// every row on this ticket.
      List<int> kv(String label, String value, {bool bold = false}) =>
          generator.row([
            PosColumn(
              text: _safe(label),
              width: 7,
              styles: PosStyles(
                bold: bold,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            ),
            PosColumn(
              text: _safe(value),
              width: 5,
              styles: PosStyles(
                align: PosAlign.right,
                bold: bold,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            ),
          ]);

      /// A section heading: "1) RESUME GENERAL".
      List<int> section(int no, String title) {
        var out = rule();
        out += generator.text(
          '$no) ${_safe(title)}',
          styles: PosStyles(
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
        return out;
      }

      /// Name / quantity / amount — §7 and §8.
      List<int> triple(String a, String b, String c,
              {bool bold = false, bool underline = false}) =>
          generator.row([
            PosColumn(
              text: _safe(a),
              width: 6,
              styles: PosStyles(
                bold: bold,
                underline: underline,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            ),
            PosColumn(
              text: _safe(b),
              width: 2,
              styles: PosStyles(
                align: PosAlign.right,
                bold: bold,
                underline: underline,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            ),
            PosColumn(
              text: _safe(c),
              width: 4,
              styles: PosStyles(
                align: PosAlign.right,
                bold: bold,
                underline: underline,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            ),
          ]);

      String qty(double v) =>
          v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3);

      // ── Letterhead ────────────────────────────────────────────────────
      bytes += generator.text(
        _safe(businessName ?? 'Caisse212'),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      final storeAddr = _prefs?.getString('business_address');
      final storeTel = _prefs?.getString('business_phone');
      final storeIce = _prefs?.getString('business_ice');
      if (storeAddr != null) {
        bytes += _wrappedText(generator, _safe(storeAddr),
            const PosStyles(align: PosAlign.center));
      }
      if (storeIce != null) {
        bytes += generator.text('ICE : ${_safe(storeIce)}',
            styles: const PosStyles(align: PosAlign.center));
      }
      if (storeTel != null) {
        bytes += generator.text(
            '${_translate('phone')} : ${_safe(storeTel)}',
            styles: const PosStyles(align: PosAlign.center));
      }

      // ── Title band ────────────────────────────────────────────────────
      bytes += rule();
      bytes += generator.text(
        isX ? _translate('x_report_title') : _translate('z_report_title'),
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        isX ? _translate('x_report_subtitle') : _translate('z_report_subtitle'),
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += rule();
      if (isReprint) {
        bytes += generator.text(
          '*** ${_text('duplicate_ticket', fallback: 'DUPLICATA')} ***',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
      }

      // ── Identity block ────────────────────────────────────────────────
      final posName = _prefs?.getString('pos_name');
      if (posName != null) {
        bytes += kv(_translate('till'), posName);
      }
      if (zLabel != null) {
        bytes += kv('Z', zLabel, bold: true);
      }
      final sessionCodes = report.sessions.map((x) => x.sessionCode).toList();
      if (sessionCodes.isNotEmpty) {
        bytes += kv(
          _translate('session'),
          sessionCodes.length == 1
              ? sessionCodes.first
              : '${sessionCodes.length}',
        );
      }
      final cashierNames = report.sessions
          .map((x) => x.cashierName)
          .whereType<String>()
          .where((n) => n.trim().isNotEmpty)
          .toSet()
          .toList();
      if (cashierNames.isNotEmpty) {
        bytes += kv(_translate('cashier'), cashierNames.join(', '));
      }
      bytes += kv(_translate('date'), _formatDate(report.endDate));
      bytes += kv(_translate('printed_at'), _formatTime(DateTime.now()));
      bytes += kv(
        _translate('period'),
        '${_formatTime(report.startDate)} -> ${_formatTime(report.endDate)}',
      );

      // Sections are numbered by a running counter, not literals: a
      // conditional section (annulments, outstanding) must not leave a gap
      // in the sequence, and renumbering by hand is how §4 got out of step
      // with its own banner when the VAT block was pulled.
      var sec = 0;
      // ── RESUME GENERAL ─────────────────────────────────────────────
      final g = s.general;
      bytes += section(++sec, _translate('general_summary'));
      bytes += kv(_translate('gross_sales'), cash(g.grossSales));
      bytes += kv(_translate('discounts_reductions'), '-${cash(g.discounts)}');
      bytes += kv(_translate('cancelled_tickets'), '-${cash(g.cancelledTickets)}');
      bytes += kv(_translate('cancelled_lines'), '-${cash(g.cancelledLines)}');
      bytes += kv(_translate('refunds_returns'), '-${cash(g.refunds)}');
      bytes += thinRule();
      bytes += kv(_translate('total_net_ttc'), cash(g.netTotal), bold: true);

      // ── VENTES PAR TYPE ────────────────────────────────────────────
      bytes += section(++sec, _translate('sales_by_type'));
      var typeTotal = 0.0;
      for (final entry in s.salesByType.entries) {
        typeTotal += entry.value;
        bytes += kv(_getOrderTypeText(entry.key), cash(entry.value));
      }
      if (s.salesByType.isEmpty) {
        bytes += kv(_translate('no_data'), cash(0));
      }
      bytes += thinRule();
      bytes += kv(_translate('total'), cash(typeTotal), bold: true);

      // ── PAIEMENTS ──────────────────────────────────────────────────
      // Cheque / Bon / Credit client are not printed: TransactionType has no
      // such members, so they would be indistinguishable from any other
      // "Other" and a line that can only ever be 0,00 is worse than no line.
      bytes += section(++sec, _translate('payments'));
      bytes += kv(_translate('cash'), cash(report.totalPaidByCash));
      bytes += kv(_translate('card'), cash(report.totalPaidByCard));
      bytes += kv(_translate('mobile_payment'), cash(report.totalPaidByPhone));
      bytes += kv(_translate('other'), cash(report.totalPaidByOther));
      bytes += thinRule();
      bytes += kv(_translate('total_payments'), cash(report.totalPaid),
          bold: true);

      // The VAT breakdown that used to print here as section 4 was removed
      // from both the X and the Z on request. CashReportSections still
      // computes vatBands / vatTotalHt / vatTotalVat / vatTotalTtc, so the
      // block can be restored by printing them again - nothing upstream was
      // torn out.

      // ── MOUVEMENTS DE CAISSE ───────────────────────────────────────
      final c = s.cash;
      bytes += section(++sec, _translate('cash_movements'));
      bytes += kv(_translate('opening_float'), cash(c.openingFloat));
      bytes += kv(_translate('cash_in'), cash(c.cashIn));
      bytes += kv(_translate('cash_out'), cash(c.cashOut));
      // Why the drawer exceeds the ticket rows. Only when there were any: on
      // a shift with no deliveries this is a line of noise.
      if (c.cashDeliveryFees > 0.005) {
        bytes += kv(_translate('delivery_fee'), cash(c.cashDeliveryFees));
      }
      bytes += kv(_translate('expected_cash'), cash(c.expectedCash));
      // An open shift has counted nothing yet, so these read "--" rather than
      // claiming a zero count and a variance equal to the whole drawer.
      bytes += kv(_translate('counted_cash'),
          c.countedCash == null ? '--' : cash(c.countedCash!));
      bytes += kv(_translate('cash_variance'),
          c.variance == null ? '--' : cash(c.variance!));

      // ── INDICATEURS ────────────────────────────────────────────────
      final ind = s.indicators;
      bytes += section(++sec, _translate('restaurant_indicators'));
      bytes += kv(_translate('ticket_count'), '${ind.ticketCount}');
      bytes += kv(_translate('average_ticket'), cash(ind.averageTicket));
      bytes += kv(_translate('cancelled_tickets'), '${ind.cancelledTicketCount}');
      bytes += kv(_translate('cancelled_lines'), '${ind.cancelledLineCount}');
      bytes += kv(_translate('total_discounts'), cash(ind.totalDiscounts));
      bytes += kv(_translate('total_refunds'), cash(ind.totalRefunds));
      bytes += kv(_translate('covers'), '${ind.covers}');
      bytes += kv(_translate('tables_open'), '${ind.tablesOpen}');
      bytes += kv(_translate('tables_closed'), '${ind.tablesClosed}');
      // One row per station the shop actually runs, rather than a hardcoded
      // kitchen/bar pair that would be wrong for anyone with three.
      for (final entry in ind.ordersByStation.entries) {
        bytes += kv(
            '${_translate('orders_to')} ${_safe(entry.key)}', '${entry.value}');
      }

      // ── RESUME PAR FAMILLE ─────────────────────────────────────────
      bytes += section(++sec, _translate('summary_by_family'));
      bytes += triple(_translate('family'), _translate('qty'),
          _translate('revenue_ttc'),
          underline: true);
      for (final row in s.families) {
        bytes += triple(row.name, qty(row.quantity), cash(row.amount));
      }

      // ── TOP ARTICLES ───────────────────────────────────────────────
      bytes += section(++sec, _translate('top_articles'));
      bytes += triple(_translate('article'), _translate('qty'),
          _translate('revenue_ttc'),
          underline: true);
      for (final row in s.topArticles) {
        bytes += triple(row.name, qty(row.quantity), cash(row.amount));
      }

      // ── STATUTS EN COURS ───────────────────────────────────────────
      final live = s.live;
      bytes += section(++sec, _translate('live_statuses'));
      bytes += kv(_translate('parked_orders'), '${live.parkedOrders}');
      bytes += kv(_translate('tables_in_progress'), '${live.openTables}');
      bytes += kv(_translate('sent_to_kitchen'), '${live.sentToKitchen}');
      bytes += kv(_translate('ready_not_served'), '${live.readyNotServed}');

      // ── ANNULATIONS ─────────────────────────────────────────────────
      // Lines pulled OFF a saved order during the shift, read from the
      // annulment tombstones — the `order_products` rows themselves are long
      // gone. Z only: the Z is the shift's closing statement and the figure
      // somebody is accountable for, while an X is a mid-service read where a
      // half-finished annulment picture invites the wrong conclusion.
      //
      // Printed only when there is something to print, like OUTSTANDING below:
      // a permanent "ANNULATIONS: 0,00" teaches the reader to skip the band on
      // the day it finally says something.
      final removed = s.removedItems;
      if (!isX && !removed.isEmpty) {
        bytes += section(++sec, _translate('cancellations'));
        bytes += triple(_translate('article'), _translate('qty'),
            _translate('amount'),
            underline: true);
        for (final row in removed.rows) {
          bytes += triple(row.name, qty(row.quantity), cash(row.amount));
        }
        bytes += thinRule();
        bytes += kv(_translate('removed_lines'), '${removed.lineCount}');
        bytes += kv(_translate('removed_quantity'), qty(removed.quantity));
        // The half that actually cost something: the kitchen had already been
        // told to make it.
        bytes += kv(_translate('removed_after_kitchen'),
            qty(removed.afterKitchenQuantity));
        bytes += kv(_translate('removed_after_kitchen_amount'),
            cash(removed.afterKitchenAmount));
        bytes += kv(_translate('removed_total'), cash(removed.amount),
            bold: true);
      }

      // What the floor still owes, when the caller supplied it. Not part of
      // the sections: the report is a statement of what was taken, this is a
      // live snapshot of what has not been.
      if (outstanding != null && outstanding.count > 0) {
        bytes += section(++sec, _translate('outstanding_on_floor'));
        bytes += kv(_translate('unpaid_orders'), '${outstanding.count}');
        bytes += kv(_translate('amount_due'), cash(outstanding.totalDue));
      }

      bytes += rule();
      bytes += generator.text(
        _translate('information_document'),
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        isX ? _translate('x_report_no_close') : _translate('z_report_closed'),
        styles: const PosStyles(align: PosAlign.center),
      );


      // Footer
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        '${printL10n.translate('printed_at')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      debugPrint(
        'Attempting to print daily summary report. Bytes length: ${bytes.length}',
      );

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint(
            'Daily summary report dispatch failed — no paper came out.');
        return false;
      }

      debugPrint('Daily summary report printed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing daily summary report: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  });

  /// Print the compact "Z-DAY TOTAL" extension — a short rollup of every
  /// session sharing the closing session's z-day, meant to print right after
  /// the per-session Z when Z tracking is off. Totals-only (no per-session
  /// detail, no variance): date, session/order/ticket counts, the payment
  /// breakdown, and the grand day total. [report] should come from
  /// [DailySummaryService.generateZDayReport].
  Future<bool> printZDayTotal({
    required DailySummaryReport report,
  }) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for z-day total');
      return false;
    }

    try {
      final printL10n = _getPrintingL10n();
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      final cur = _getCurrency(null);
      final sep = ''.padLeft(32, '-');
      final doubleSep = ''.padLeft(32, '=');
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      List<int> twoCol(String left, String right, {bool bold = false}) {
        return generator.row([
          PosColumn(
            text: left,
            width: 7,
            styles: PosStyles(
              align: PosAlign.left,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: right,
            width: 5,
            styles: PosStyles(
              align: PosAlign.right,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

      bytes += generator.emptyLines(1);
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(
        printL10n.translate('z_day_total'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveHeaderHeight(),
          width: _resolveHeaderSize(),
        ),
      );
      bytes += generator.text(
        _formatDate(report.startDate),
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      bytes += twoCol('${printL10n.translate('number_of_sessions')}:',
          '${report.totalSessions}');
      bytes += twoCol('${printL10n.translate('total_orders')}:',
          '${report.totalOrders}');
      bytes += twoCol('${printL10n.translate('total_tickets')}:',
          '${report.totalTickets}');

      bytes += generator.text(sep,
          styles: const PosStyles(align: PosAlign.center));

      bytes += twoCol('${printL10n.translate('paid_by_cash')}:',
          CurrencyFormatter.formatWithCurrency(report.totalPaidByCash, cur));
      bytes += twoCol('${printL10n.translate('paid_by_card')}:',
          CurrencyFormatter.formatWithCurrency(report.totalPaidByCard, cur));
      bytes += twoCol('${printL10n.translate('paid_by_phone')}:',
          CurrencyFormatter.formatWithCurrency(report.totalPaidByPhone, cur));
      bytes += twoCol('${printL10n.translate('paid_by_other')}:',
          CurrencyFormatter.formatWithCurrency(report.totalPaidByOther, cur));

      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += twoCol(
        '${printL10n.translate('day_total')}:',
        CurrencyFormatter.formatWithCurrency(report.totalPaid, cur),
        bold: true,
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      bytes += generator.emptyLines(1);
      bytes += generator.text(
        '${printL10n.translate('printed_at')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint('Z-day total dispatch failed — no paper came out.');
      }
      return ok;
    } catch (e, stackTrace) {
      debugPrint('Error printing z-day total: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  });

  /// `HH:mm` — the only time form the extra close-time tickets need.
  String _formatClock(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Scope banner shared by the two extra close-time tickets: the Z code and
  /// number when a whole shift is being printed, otherwise the session code.
  Future<List<int>> _reportScopeHeader(
    Generator generator,
    AppLocalizations printL10n, {
    required String scopeLabel,
    String? zCode,
    int? zNumber,
    required int sessionCount,
  }) async {
    List<int> bytes = [];
    final isZ = zCode != null;
    bytes += generator.text(
      isZ
          ? '${printL10n.translate('report_scope_z')}: $zCode'
          : '${printL10n.translate('report_scope_session')}: ${_safe(scopeLabel)}',
      styles: PosStyles(
        align: PosAlign.center,
        height: _resolveTextHeight(),
        width: _resolveTextSize(),
      ),
    );
    if (isZ && zNumber != null) {
      bytes += generator.text(
        '${printL10n.translate('z_number')}: $zNumber'
        '${sessionCount > 1 ? '  (${printL10n.translate('number_of_sessions')}: $sessionCount)' : ''}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
    }
    return bytes;
  }

  /// Prints one line of user-supplied text, rasterising it when it contains
  /// Arabic so the glyphs are shaped and ordered correctly. These are the first
  /// report tickets to carry product / waiter / table names, so the raster path
  /// matters here in a way it never did for the pure-numeric summaries.
  Future<List<int>> _reportTextLine(
    Generator generator,
    String text, {
    PosAlign align = PosAlign.left,
    bool bold = false,
  }) async {
    if (_containsArabic(text)) {
      return _arabicImageLine(generator, text,
          align: align == PosAlign.left ? PosAlign.right : align,
          bold: bold,
          small: true);
    }
    return generator.text(
      _safe(text),
      styles: PosStyles(
        align: align,
        bold: bold,
        height: _resolveTextHeight(),
        width: _resolveTextSize(),
      ),
    );
  }

  /// "Orders done" ticket — every order in the closing scope, oldest first,
  /// with cancelled ones flagged and excluded from the totals block.
  ///
  /// Printed as its own ticket with its own cut so the cashier can hand it over
  /// (or file it) separately from the X/Z.
  Future<bool> printOrdersList({
    required OrdersListReport report,
    String? businessName,
  }) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for orders list');
      return false;
    }

    try {
      final printL10n = _getPrintingL10n();
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      final cur = _getCurrency(null);
      final narrow = _config.paperSize == PaperSize.mm58;
      final sep = ''.padLeft(32, '-');
      final doubleSep = ''.padLeft(32, '=');
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      List<int> twoCol(String left, String right, {bool bold = false}) {
        return generator.row([
          PosColumn(
            text: left,
            width: 7,
            styles: PosStyles(
              align: PosAlign.left,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: right,
            width: 5,
            styles: PosStyles(
              align: PosAlign.right,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

      bytes += generator.emptyLines(1);
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(
        printL10n.translate(
            report.discountedOnly ? 'discounted_orders' : 'orders_list'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveHeaderHeight(),
          width: _resolveHeaderSize(),
        ),
      );
      if (businessName != null && businessName.trim().isNotEmpty) {
        bytes += await _reportTextLine(generator, businessName,
            align: PosAlign.center);
      }
      bytes += await _reportScopeHeader(
        generator,
        printL10n,
        scopeLabel: report.scopeLabel,
        zCode: report.zCode,
        zNumber: report.zNumber,
        sessionCount: report.sessionCodes.length,
      );
      bytes += generator.text(
        _formatDate(report.start),
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      if (report.orders.isEmpty) {
        bytes += generator.text(
          printL10n.translate('no_orders_in_scope'),
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }

      for (final o in report.orders) {
        final marker = o.isCancelled ? '[X] ' : '';
        bytes += twoCol(
          '$marker#${_safe(o.code)}',
          CurrencyFormatter.formatWithCurrency(o.total, cur),
          bold: !o.isCancelled,
        );

        // Second line: context. Dropped on 58mm paper, where it wraps badly.
        if (!narrow) {
          final ctx = <String>[
            _formatClock(o.createdAt),
            o.type,
            if (o.tableName != null && o.tableName!.isNotEmpty) o.tableName!,
            if (o.waiterName != null && o.waiterName!.isNotEmpty) o.waiterName!,
            if (o.paymentMethods.isNotEmpty) o.paymentMethods,
          ];
          bytes += await _reportTextLine(generator, '  ${ctx.join(' · ')}');
        }
        // What came off this order. Always shown on the reductions ticket —
        // it is the column the whole document exists for — and on the ordinary
        // orders list only when there is something to show.
        if (report.discountedOnly || o.discount.abs() > 0.005) {
          bytes += twoCol(
            '  ${printL10n.translate('discounts_reductions')}',
            '-${CurrencyFormatter.formatWithCurrency(o.discount, cur)}',
          );
        }
        if (!o.isCancelled && o.due > 0.005) {
          bytes += twoCol(
            '  ${printL10n.translate('unpaid')}',
            CurrencyFormatter.formatWithCurrency(o.due, cur),
          );
        }
      }

      bytes += generator.text(sep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += twoCol(
          '${printL10n.translate('orders_count')}:', '${report.count}');
      bytes += twoCol('${printL10n.translate('total_paid')}:',
          CurrencyFormatter.formatWithCurrency(report.paid, cur));
      if (report.discountedOnly) {
        bytes += twoCol(
          '${printL10n.translate('total_discounts')}:',
          CurrencyFormatter.formatWithCurrency(
              report.orders.fold<double>(0, (s, o) => s + o.discount), cur),
          bold: true,
        );
      }
      if (report.unpaid > 0.005) {
        bytes += twoCol('${printL10n.translate('unpaid')}:',
            CurrencyFormatter.formatWithCurrency(report.unpaid, cur));
      }
      if (report.cancelledCount > 0) {
        bytes += twoCol(
          '${printL10n.translate('cancelled')}:',
          '${report.cancelledCount} · '
              '${CurrencyFormatter.formatWithCurrency(report.cancelledTotal, cur)}',
        );
      }

      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += twoCol(
        '${printL10n.translate('total')}:',
        CurrencyFormatter.formatWithCurrency(report.total, cur),
        bold: true,
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      bytes += generator.emptyLines(1);
      bytes += generator.text(
        '${printL10n.translate('printed_at')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint('Orders list dispatch failed — no paper came out.');
      }
      return ok;
    } catch (e, stackTrace) {
      debugPrint('Error printing orders list: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  });

  /// True when this order came from a platform that gives couriers a code.
  ///
  /// DealUp and Web are our own channels — no courier, no platform code — so the
  /// block must never appear on them.
  static bool sourceHasCourierCode(String? source) {
    final s = (source ?? '').toUpperCase();
    return s == 'GLOVO' || s == 'KOOUL';
  }

  /// The courier block: platform name, the code in the largest type on the
  /// ticket, a scannable symbol, and the few identifiers staff need.
  ///
  /// The symbol encodes **exactly** [externalOrderCode] — no URL, no JSON, no
  /// prefix. The courier's app scans the raw value and anything wrapped around
  /// it makes the scan useless.
  List<int> _buildCourierBlock(
    Generator generator, {
    required String source,
    required String? externalOrderCode,
    String? pickUpCode,
    String? customerName,
    required String ourOrderCode,
  }) {
    final printL10n = _getPrintingL10n();
    final narrow = _config.paperSize == PaperSize.mm58;
    final sep = ''.padLeft(narrow ? 32 : 42, '=');
    List<int> bytes = [];

    bytes += generator.text(sep,
        styles: const PosStyles(align: PosAlign.center));

    // Platform name, big — the first thing a courier looks for.
    bytes += generator.text(
      source.toUpperCase(),
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );

    final code = (externalOrderCode ?? '').trim();
    if (code.isEmpty) {
      // Should not happen for GLOVO/KOOUL. Print something a human can act on
      // rather than an empty box, and leave a trace for whoever investigates.
      debugPrint('WARNING: courier block for $source has no externalOrderCode; '
          'falling back to our own order code ($ourOrderCode), no symbol.');
      bytes += generator.text(
        ourOrderCode,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        printL10n.translate('courier_code_missing'),
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(sep,
          styles: const PosStyles(align: PosAlign.center));
      return bytes;
    }

    // The code itself — the largest text on the ticket, per the contract.
    bytes += generator.text(
      // _safe maps the ordinal indicator to a plain 'o', so this prints
      // "No 4F8-JKL" on every code page instead of a box-drawing character.
      _safe('Nº $code'),
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size3,
        width: PosTextSize.size3,
      ),
    );
    bytes += generator.emptyLines(1);

    switch (_config.courierCodeSymbology) {
      case CourierCodeSymbology.qr:
        // size4 on 58mm keeps the module count inside the paper width with a
        // usable quiet zone; 80mm can afford one step larger.
        bytes += generator.qrcode(
          code,
          align: PosAlign.center,
          size: narrow ? QRSize.size4 : QRSize.size6,
          // M over L: a bag-mounted ticket gets creased and smudged, and the
          // extra redundancy is worth more than the density saving.
          cor: QRCorrection.M,
        );
        break;

      case CourierCodeSymbology.code128:
        bytes += generator.barcode(
          Barcode.code128(code.split('')),
          height: narrow ? 60 : 80,
          align: PosAlign.center,
          // The human-readable line is printed above already, so this would be
          // a duplicate that eats vertical space.
          textPos: BarcodeText.none,
        );
        break;

      case CourierCodeSymbology.text:
        break;
    }

    bytes += generator.emptyLines(1);

    if ((pickUpCode ?? '').trim().isNotEmpty) {
      bytes += generator.text(
        '${printL10n.translate('pickup_code')}: ${pickUpCode!.trim()}',
        styles: const PosStyles(
            align: PosAlign.center, bold: true, height: PosTextSize.size2),
      );
    }
    if ((customerName ?? '').trim().isNotEmpty) {
      bytes += generator.text(
        '${printL10n.translate('customer')}: ${customerName!.trim()}',
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    // Ours, small — for staff reconciling, not for the courier.
    bytes += generator.text(
      ourOrderCode,
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.text(sep,
        styles: const PosStyles(align: PosAlign.center));
    return bytes;
  }

  /// Standalone courier ticket for the bag — [CourierCodeMode.separateTicket].
  ///
  /// Its own paper and its own cut, so it can be stuck to the bag while the
  /// kitchen keeps the item ticket.
  Future<bool> printCourierTicket({
    required String source,
    required String? externalOrderCode,
    required String ourOrderCode,
    String? pickUpCode,
    String? customerName,
  }) => _enqueue(() async {
    if (!sourceHasCourierCode(source)) return false;
    if (_config.courierCodeMode == CourierCodeMode.off) return false;

    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Courier ticket: no receipt printer connection');
      return false;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];
      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());
      bytes += generator.emptyLines(1);
      bytes += _buildCourierBlock(
        generator,
        source: source,
        externalOrderCode: externalOrderCode,
        pickUpCode: pickUpCode,
        customerName: customerName,
        ourOrderCode: ourOrderCode,
      );
      bytes += generator.emptyLines(2);
      bytes += generator.cut();
      return await _dispatchBytes(PrinterPurpose.receipt, bytes);
    } catch (e, st) {
      debugPrint('Error printing courier ticket: $e');
      debugPrint('$st');
      return false;
    }
  });

  /// Refund slip.
  ///
  /// The refund `code` is the reference support will ask the customer for, so it
  /// is printed large and first — everything else on this slip is context for
  /// it. Also carries the original order code, because the pair is what makes a
  /// refund traceable back to the sale.
  ///
  /// Its own ticket with its own cut, like the other report slips: a refund is
  /// handed to the customer, not stapled to a sales receipt.
  Future<bool> printRefundSlip({
    required RefundSlipData data,
    String? businessName,
  }) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for refund slip');
      return false;
    }

    try {
      final printL10n = _getPrintingL10n();
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      final cur = _getCurrency(null);
      final narrow = _config.paperSize == PaperSize.mm58;
      final sep = ''.padLeft(32, '-');
      final doubleSep = ''.padLeft(32, '=');
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      List<int> twoCol(String left, String right, {bool bold = false}) {
        return generator.row([
          PosColumn(
            text: left,
            width: 7,
            styles: PosStyles(
              align: PosAlign.left,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: right,
            width: 5,
            styles: PosStyles(
              align: PosAlign.right,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

      bytes += generator.emptyLines(1);
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(
        printL10n.translate('refund_slip_title'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveHeaderHeight(),
          width: _resolveHeaderSize(),
        ),
      );
      if (businessName != null && businessName.trim().isNotEmpty) {
        bytes += await _reportTextLine(generator, businessName,
            align: PosAlign.center);
      }
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      // The support reference, given its own emphasis. A customer reading this
      // back over the phone should not have to hunt for it.
      bytes += generator.text(
        data.code,
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveHeaderHeight(),
          width: _resolveHeaderSize(),
        ),
      );
      bytes += generator.emptyLines(1);

      bytes += twoCol('${printL10n.translate('order')}:', data.orderCode);
      // Raw method code, exactly as the dialog shows it — the cashier picked
      // "CASH" on screen and should read "CASH" on the paper.
      bytes += twoCol(
          '${printL10n.translate('refund_method')}:', data.method);
      if (data.cashierName != null && data.cashierName!.trim().isNotEmpty) {
        bytes += await _reportTextLine(
            generator, '${printL10n.translate('cashier')}: ${data.cashierName}');
      }
      bytes += twoCol('${printL10n.translate('date')}:',
          _formatDateTime(data.refundedAt));

      bytes += generator.text(sep,
          styles: const PosStyles(align: PosAlign.center));

      for (final line in data.lines) {
        // Product names are user-supplied and may be Arabic — same treatment as
        // every other report line.
        bytes += await _reportTextLine(generator, line.name, bold: true);
        bytes += twoCol(
          '  ${_fmtSlipQty(line.quantity)} x',
          CurrencyFormatter.formatWithCurrency(line.amount, cur),
        );
        // The exact unit returned. Printed because a serialised item's slip is
        // the customer's proof for THAT unit, not merely for the model.
        if (line.serialNumber != null && line.serialNumber!.isNotEmpty) {
          bytes += generator.text(
            '  ${line.serialNumber}',
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
        }
        // Waste is worth saying out loud: the customer's goods did not go back
        // on the shelf, and a later stock query should not surprise anyone.
        if (!line.restock && !narrow) {
          bytes += generator.text(
            '  ${printL10n.translate('not_restocked')}',
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
        }
      }

      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += twoCol(
        '${printL10n.translate('total_refunded')}:',
        CurrencyFormatter.formatWithCurrency(data.total, cur),
        bold: true,
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      if (data.reason != null && data.reason!.trim().isNotEmpty) {
        bytes += generator.emptyLines(1);
        bytes += await _reportTextLine(
            generator, '${printL10n.translate('reason')}: ${data.reason}');
      }

      bytes += generator.emptyLines(1);
      bytes += generator.text(
        '${printL10n.translate('printed_at')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint('Refund slip dispatch failed — no paper came out.');
      }
      return ok;
    } catch (e, stackTrace) {
      debugPrint('Error printing refund slip: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  });

  /// Whole quantities print as "2", weighed ones keep their decimals.
  String _fmtSlipQty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3);

  /// "Products summary" ticket — what was actually sold in the closing scope,
  /// busiest first. Cancelled orders are excluded. Own ticket, own cut.
  Future<bool> printProductsSummary({
    required ProductsSummaryReport report,
    String? businessName,
    /// Break the list into category sections, each with its own subtotal,
    /// instead of one flat quantity-ranked list. What a manager reading a
    /// day's trading wants; the flat list stays the default because that is
    /// what session close has always printed.
    bool groupByCategory = false,
    /// Row order, and section order when grouped. Quantity is what every
    /// existing caller printed.
    ProductsSort sort = ProductsSort.quantity,
    /// False prints quantities only — the kitchen's copy, where prices are
    /// noise and not the kitchen's business.
    bool showAmounts = true,
  }) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint(
          'Could not establish receipt printer connection for products summary');
      return false;
    }

    try {
      final printL10n = _getPrintingL10n();
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      final cur = _getCurrency(null);
      final nameLimit = _config.paperSize == PaperSize.mm58 ? 16 : 22;
      final sep = ''.padLeft(32, '-');
      final doubleSep = ''.padLeft(32, '=');
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      List<int> twoCol(String left, String right, {bool bold = false}) {
        return generator.row([
          PosColumn(
            text: left,
            width: 8,
            styles: PosStyles(
              align: PosAlign.left,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: right,
            width: 4,
            styles: PosStyles(
              align: PosAlign.right,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

      String qty(double v) =>
          v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

      bytes += generator.emptyLines(1);
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(
        printL10n.translate('products_summary'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveHeaderHeight(),
          width: _resolveHeaderSize(),
        ),
      );
      if (businessName != null && businessName.trim().isNotEmpty) {
        bytes += await _reportTextLine(generator, businessName,
            align: PosAlign.center);
      }
      bytes += await _reportScopeHeader(
        generator,
        printL10n,
        scopeLabel: report.scopeLabel,
        zCode: report.zCode,
        zNumber: report.zNumber,
        sessionCount: report.sessionCodes.length,
      );
      bytes += generator.text(
        _formatDate(report.start),
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      if (report.rows.isEmpty) {
        bytes += generator.text(
          printL10n.translate('no_orders_in_scope'),
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }

      Future<List<int>> productRow(ProductSummaryEntry r) async {
        var out = <int>[];
        final name = r.name.length > nameLimit
            ? r.name.substring(0, nameLimit)
            : r.name;
        final label = '${qty(r.quantity)}x $name';
        if (!showAmounts) {
          return _containsArabic(name)
              ? await _reportTextLine(generator, label)
              : twoCol(_safe(label), '');
        }
        final amount = CurrencyFormatter.formatWithCurrency(r.net, cur);
        // Arabic product names can't go through `row()` (raster images are
        // whole lines), so they print as their own shaped line + amount.
        if (_containsArabic(name)) {
          out += await _reportTextLine(generator, '${qty(r.quantity)}x $name');
          out += generator.text(
            amount,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
        } else {
          out += twoCol(_safe(label), amount);
        }
        return out;
      }

      final rows = sortProductRows(report.rows, sort);

      if (groupByCategory) {
        final sections = <String, List<ProductSummaryEntry>>{};
        for (final r in rows) {
          final key = (r.categoryName ?? '').trim().isEmpty
              ? printL10n.translate('uncategorized')
              : r.categoryName!.trim();
          sections.putIfAbsent(key, () => []).add(r);
        }
        double sum(List<ProductSummaryEntry> l, double Function(ProductSummaryEntry) f) =>
            l.fold(0.0, (s, r) => s + f(r));
        final ordered = sections.entries.toList()
          ..sort((a, b) {
            switch (sort) {
              case ProductsSort.quantity:
                return sum(b.value, (r) => r.quantity)
                    .compareTo(sum(a.value, (r) => r.quantity));
              case ProductsSort.amount:
                return sum(b.value, (r) => r.net)
                    .compareTo(sum(a.value, (r) => r.net));
              case ProductsSort.name:
                return a.key.toLowerCase().compareTo(b.key.toLowerCase());
            }
          });
        for (final entry in ordered) {
          bytes += generator.text(sep,
              styles: const PosStyles(align: PosAlign.center));
          bytes += await _reportTextLine(generator, entry.key.toUpperCase(),
              bold: true);
          for (final r in entry.value) {
            bytes += await productRow(r);
          }
          final catQty = entry.value.fold(0.0, (s, r) => s + r.quantity);
          final catNet = entry.value.fold(0.0, (s, r) => s + r.net);
          bytes += twoCol(
            '  ${printL10n.translate('subtotal')} (${qty(catQty)})',
            showAmounts ? CurrencyFormatter.formatWithCurrency(catNet, cur) : '',
            bold: true,
          );
        }
      } else {
        for (final r in rows) {
          bytes += await productRow(r);
        }
      }

      bytes += generator.text(sep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += twoCol('${printL10n.translate('products_total_qty')}:',
          qty(report.totalQuantity));
      bytes += twoCol(
          '${printL10n.translate('quantity')}:', '${report.distinctProducts}');
      if (showAmounts) {
        if (report.totalDiscount > 0.005) {
          bytes += twoCol('${printL10n.translate('discount')}:',
              CurrencyFormatter.formatWithCurrency(report.totalDiscount, cur));
        }

        bytes += generator.text(doubleSep,
            styles: const PosStyles(align: PosAlign.center));
        bytes += twoCol(
          '${printL10n.translate('products_total_net')}:',
          CurrencyFormatter.formatWithCurrency(report.totalNet, cur),
          bold: true,
        );
      }
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      bytes += generator.emptyLines(1);
      bytes += generator.text(
        '${printL10n.translate('printed_at')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint('Products summary dispatch failed — no paper came out.');
      }
      return ok;
    } catch (e, stackTrace) {
      debugPrint('Error printing products summary: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  });

  /// The outstanding-position document: every unpaid table and parked order,
  /// with what has been collected on each and what has not.
  ///
  /// Printed on its own from the Z dialog, so a manager can walk the floor
  /// against a piece of paper at the end of the night. Tables and non-table
  /// orders are sectioned separately because they mean different things to
  /// whoever is closing up: an open table is somebody still sitting there, a
  /// parked takeaway is money nobody collected.
  ///
  /// Names the holder on every line — after a shift change that is whoever
  /// last worked the order, which is exactly who to ask about it.
  Future<bool> printUnpaidOrders({
    required UnpaidOrdersSummary summary,
    String? businessName,
    String? scopeLabel,
  }) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for unpaid');
      return false;
    }

    try {
      final printL10n = _getPrintingL10n();
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      final cur = _getCurrency(null);
      final nameLimit = _config.paperSize == PaperSize.mm58 ? 14 : 20;
      final sep = ''.padLeft(32, '-');
      final doubleSep = ''.padLeft(32, '=');
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      List<int> twoCol(String left, String right, {bool bold = false}) {
        return generator.row([
          PosColumn(
            text: left,
            width: 8,
            styles: PosStyles(
              align: PosAlign.left,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: right,
            width: 4,
            styles: PosStyles(
              align: PosAlign.right,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

      Future<List<int>> entryLines(UnpaidOrderEntry e) async {
        var out = <int>[];
        final label =
            e.label.length > nameLimit ? e.label.substring(0, nameLimit) : e.label;
        final due = CurrencyFormatter.formatWithCurrency(e.due, cur);
        if (_containsArabic(label)) {
          out += await _reportTextLine(generator, label, bold: true);
          out += generator.text(
            due,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
        } else {
          out += twoCol(_safe(label), due, bold: true);
        }
        // The order code makes the sheet checkable against the till later; a
        // table name alone is ambiguous once the table turns over.
        out += await _reportTextLine(generator,
            '  ${e.order.code}   ${e.holderName ?? ''}'.trimRight());
        if (e.paid > 0.005) {
          out += twoCol('  ${printL10n.translate('paid')}',
              CurrencyFormatter.formatWithCurrency(e.paid, cur));
        }
        return out;
      }

      bytes += await _reportTextLine(
          generator, printL10n.translate('unpaid_orders').toUpperCase(),
          align: PosAlign.center, bold: true);
      if (businessName != null && businessName.trim().isNotEmpty) {
        bytes += await _reportTextLine(generator, businessName,
            align: PosAlign.center);
      }
      if (scopeLabel != null && scopeLabel.trim().isNotEmpty) {
        bytes += await _reportTextLine(generator, scopeLabel,
            align: PosAlign.center);
      }
      bytes += generator.text(
        '${printL10n.translate('printed_at')}: ${_formatDateTime(summary.at)}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      if (summary.entries.isEmpty) {
        bytes += await _reportTextLine(
            generator, printL10n.translate('nothing_outstanding'),
            align: PosAlign.center);
      }

      if (summary.tables.isNotEmpty) {
        bytes += await _reportTextLine(
            generator, printL10n.translate('tables').toUpperCase(),
            bold: true);
        for (final e in summary.tables) {
          bytes += await entryLines(e);
        }
        bytes += generator.text(sep,
            styles: const PosStyles(align: PosAlign.center));
        bytes += twoCol(
          '${printL10n.translate('tables')} (${summary.tableCount})',
          CurrencyFormatter.formatWithCurrency(summary.tablesDue, cur),
          bold: true,
        );
      }

      if (summary.others.isNotEmpty) {
        bytes += generator.text(sep,
            styles: const PosStyles(align: PosAlign.center));
        bytes += await _reportTextLine(
            generator, printL10n.translate('other_orders').toUpperCase(),
            bold: true);
        for (final e in summary.others) {
          bytes += await entryLines(e);
        }
        bytes += generator.text(sep,
            styles: const PosStyles(align: PosAlign.center));
        bytes += twoCol(
          '${printL10n.translate('other_orders')} '
          '(${summary.others.length})',
          CurrencyFormatter.formatWithCurrency(summary.othersDue, cur),
          bold: true,
        );
      }

      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += twoCol('${printL10n.translate('total')}:',
          CurrencyFormatter.formatWithCurrency(summary.totalValue, cur));
      bytes += twoCol('${printL10n.translate('paid')}:',
          CurrencyFormatter.formatWithCurrency(summary.totalPaid, cur));
      bytes += twoCol(
        '${printL10n.translate('remaining')}:',
        CurrencyFormatter.formatWithCurrency(summary.totalDue, cur),
        bold: true,
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint('Unpaid orders dispatch failed — no paper came out.');
      }
      return ok;
    } catch (e, stackTrace) {
      debugPrint('Error printing unpaid orders: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  });

  /// The "sales by staff" ticket — a day's trading split per waiter or per
  /// cashier, or narrowed to one of them.
  ///
  /// Laid out like the products summary on purpose: a manager reading both at
  /// the end of a day should not have to learn two shapes. Each row carries
  /// what the person sold and what has actually been collected, because the
  /// gap between those two is the whole reason a waiter's ticket gets printed.
  Future<bool> printStaffSales({
    required StaffSalesReport report,
    String? businessName,
  }) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for staff sales');
      return false;
    }

    try {
      final printL10n = _getPrintingL10n();
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      final cur = _getCurrency(null);
      final nameLimit = _config.paperSize == PaperSize.mm58 ? 16 : 22;
      final sep = ''.padLeft(32, '-');
      final doubleSep = ''.padLeft(32, '=');
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      List<int> twoCol(String left, String right, {bool bold = false}) {
        return generator.row([
          PosColumn(
            text: left,
            width: 8,
            styles: PosStyles(
              align: PosAlign.left,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: right,
            width: 4,
            styles: PosStyles(
              align: PosAlign.right,
              bold: bold,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

      String qty(double v) =>
          v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

      final heading = report.grouping == StaffGrouping.waiter
          ? printL10n.translate('sales_by_waiter')
          : printL10n.translate('sales_by_cashier');
      bytes += await _reportTextLine(generator, heading.toUpperCase(),
          align: PosAlign.center, bold: true);
      if (businessName != null && businessName.trim().isNotEmpty) {
        bytes += await _reportTextLine(generator, businessName,
            align: PosAlign.center);
      }
      bytes += await _reportScopeHeader(
        generator,
        printL10n,
        scopeLabel: report.scopeLabel,
        zCode: report.zCode,
        zNumber: report.zNumber,
        sessionCount: report.sessionCodes.length,
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      if (report.rows.isEmpty) {
        bytes += generator.text(
          printL10n.translate('no_orders_in_scope'),
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }

      for (final r in report.rows) {
        final name =
            r.name.length > nameLimit ? r.name.substring(0, nameLimit) : r.name;
        // The name gets its own line so the three figures under it can be
        // labelled; a single row would force "12x Mohammed  1 240,00" and
        // lose the paid/due split that makes this ticket worth printing.
        bytes += await _reportTextLine(generator, name, bold: true);
        bytes += twoCol(
          '  ${printL10n.translate('orders')}: ${r.orderCount}   '
          '${printL10n.translate('quantity')}: ${qty(r.itemCount)}',
          CurrencyFormatter.formatWithCurrency(r.net, cur),
        );
        bytes += twoCol(
          '  ${printL10n.translate('paid')}',
          CurrencyFormatter.formatWithCurrency(r.paid, cur),
        );
        if (r.due > 0.005) {
          bytes += twoCol(
            '  ${printL10n.translate('remaining')}',
            CurrencyFormatter.formatWithCurrency(r.due, cur),
            bold: true,
          );
        }
        bytes += generator.text(sep,
            styles: const PosStyles(align: PosAlign.center));
      }

      bytes += twoCol(
          '${printL10n.translate('orders')}:', '${report.orderCount}');
      bytes += twoCol('${printL10n.translate('paid')}:',
          CurrencyFormatter.formatWithCurrency(report.totalPaid, cur));
      if (report.totalDue > 0.005) {
        bytes += twoCol('${printL10n.translate('remaining')}:',
            CurrencyFormatter.formatWithCurrency(report.totalDue, cur));
      }
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));
      bytes += twoCol(
        '${printL10n.translate('total')}:',
        CurrencyFormatter.formatWithCurrency(report.totalNet, cur),
        bold: true,
      );
      bytes += generator.text(doubleSep,
          styles: const PosStyles(align: PosAlign.center));

      bytes += generator.emptyLines(1);
      bytes += generator.text(
        '${printL10n.translate('printed_at')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint('Staff sales dispatch failed — no paper came out.');
      }
      return ok;
    } catch (e, stackTrace) {
      debugPrint('Error printing staff sales: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  });

  /// Print daily orders summary for a specific user
  Future<bool> printDailyOrdersForUser({
    required String userName,
    required String userCode,
    required List<UserDailyOrderEntry> orders,
    required DateTime reportDate,
    String? currency,
    String? storeName,
  }) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for daily orders');
      return false;
    }

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing', fallback: 'Printing...'));

    try {
      final currencySymbol = _getCurrency(currency);
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());
      bytes += _printLogoHeader(generator);

      if (storeName != null) {
        bytes += generator.text(
          storeName,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveHeaderHeight(),
            width: _resolveHeaderSize(),
          ),
        );
      }

      bytes += generator.text(
        _translate('daily_orders_report', fallback: 'Daily Orders Report'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      bytes += _sepMinor(generator);

      bytes += generator.text(
        '${_text('date', fallback: 'Date')}: ${_formatDate(reportDate)}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_text('user', fallback: 'User')}: $userName ($userCode)',
        styles: PosStyles(
          align: PosAlign.left,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_text('total_orders', fallback: 'Orders')}: ${orders.length}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      bytes += _sepMinor(generator);

      bytes += generator.row([
        PosColumn(
          text: _text('order', fallback: 'Order'),
          width: 4,
          styles: PosStyles(
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: _text('amount', fallback: 'Amount'),
          width: 5,
          styles: PosStyles(
            bold: true,
            align: PosAlign.right,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: _text('status', fallback: 'Status'),
          width: 3,
          styles: PosStyles(
            bold: true,
            align: PosAlign.right,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += _sepMinor(generator);

      for (final order in orders) {
        bytes += generator.row([
          PosColumn(
            text: order.orderCode,
            width: 4,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: CurrencyFormatter.formatWithCurrency(order.amount, currencySymbol),
            width: 5,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: order.isPaid
                ? _text('paid', fallback: 'PAID')
                : _text('unpaid', fallback: 'UNPD'),
            width: 3,
            styles: PosStyles(
              align: PosAlign.right,
              bold: order.isPaid,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

      bytes += _sepMinor(generator);

      final paidOrders = orders.where((o) => o.isPaid).toList();
      final unpaidOrders = orders.where((o) => !o.isPaid).toList();
      final totalPaid = paidOrders.fold(0.0, (sum, o) => sum + o.amount);
      final totalUnpaid = unpaidOrders.fold(0.0, (sum, o) => sum + o.amount);

      bytes += generator.row([
        PosColumn(
          text: '${_text('paid', fallback: 'Paid')} (${paidOrders.length}):',
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(totalPaid, currencySymbol),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: '${_text('unpaid', fallback: 'Unpaid')} (${unpaidOrders.length}):',
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(totalUnpaid, currencySymbol),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += _sepMinor(generator);

      bytes += generator.row([
        PosColumn(
          text: '${_text('total', fallback: 'TOTAL')}:',
          width: 6,
          styles: PosStyles(
            bold: true,
            height: _resolveHeaderHeight(),
            width: _resolveHeaderSize(),
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(totalPaid + totalUnpaid, currencySymbol),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: _resolveHeaderHeight(),
            width: _resolveHeaderSize(),
          ),
        ),
      ]);

      bytes += generator.emptyLines(1);
      bytes += generator.text(
        '${_text('printed_at', fallback: 'Printed')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(PrinterPurpose.receipt, bytes);
      if (!ok) {
        debugPrint(
            'Daily orders report dispatch failed — no paper came out.');
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return false;
      }

      debugPrint('Daily orders report printed successfully');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing daily orders report: $e');
      debugPrint('Stack trace: $stackTrace');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return false;
    }
  });

  /// Print a test page to verify printer is working.
  Future<bool> printTestPage(PrinterPurpose purpose) => _enqueue(() async {
    final printerReady = await _ensurePrinterConnected(purpose);
    if (!printerReady) {
      debugPrint('Test print: could not connect ${purpose.name} printer');
      return false;
    }

    _isPrintingInProgress = true;
    _printingStatusController.add('Printing test page...');

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());
      bytes += generator.text(
        '=== TEST PRINT ===',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        purpose == PrinterPurpose.receipt ? 'RECEIPT PRINTER' : 'KDS PRINTER',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += _sepMinor(generator);
      bytes += generator.text(
        _formatDateTime(DateTime.now()),
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        'Paper: ${_config.paperSize == PaperSize.mm58 ? "58mm" : "80mm"}  '
        'Text: ${_config.textSize == 1 ? "Normal" : _config.textSize == 2 ? "Large" : "XL"}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += _sepMinor(generator);
      bytes += generator.text(
        'Printer OK',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final ok = await _dispatchBytes(purpose, bytes);
      if (!ok) {
        debugPrint('Test page dispatch failed for ${purpose.name}.');
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return false;
      }

      debugPrint('Test page printed successfully for ${purpose.name}');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return true;
    } catch (e) {
      debugPrint('Error printing test page: $e');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return false;
    }
  });

  /// Test-print to a specific pool (per-station) printer — reuses the same
  /// override plumbing station tickets use, so it reconnects to that exact
  /// device (USB) or opens a socket to its address (NETWORK), independent of
  /// the global receipt/KDS slots. Lets the cashier verify each station printer.
  Future<bool> testPoolPrinter(NamedPrinter printer) async {
    final target = _KdsTarget(
      address: printer.address,
      name: printer.name.isNotEmpty ? printer.name : printer.label,
      type: printer.connectionType,
    );
    final ready =
        await _ensurePrinterConnected(PrinterPurpose.kds, kdsOverride: target);
    if (!ready) return false;
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];
      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());
      bytes += generator.text('=== TEST PRINT ===',
          styles: const PosStyles(
              align: PosAlign.center,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2));
      bytes += generator.emptyLines(1);
      bytes += generator.text(printer.label,
          styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: _resolveTextHeight(),
              width: _resolveTextSize()));
      bytes += _sepMinor(generator);
      bytes += generator.text('${printer.connectionType.name} · ${printer.address}',
          styles: PosStyles(
              align: PosAlign.center,
              height: _resolveTextHeight(),
              width: _resolveTextSize()));
      bytes += generator.text(_formatDateTime(DateTime.now()),
          styles: PosStyles(
              align: PosAlign.center,
              height: _resolveTextHeight(),
              width: _resolveTextSize()));
      bytes += _sepMinor(generator);
      bytes += generator.text('Printer OK',
          styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: _resolveTextHeight(),
              width: _resolveTextSize()));
      bytes += generator.emptyLines(2);
      bytes += generator.cut();
      return await _dispatchBytes(PrinterPurpose.kds, bytes, kdsOverride: target);
    } catch (e) {
      debugPrint('testPoolPrinter failed: $e');
      return false;
    }
  }

  /// Dispose streams
  void dispose() {
    _printersController.close();
    _scanningController.close();
    _configController.close();
    _printingStatusController.close();
    _printAlertController.close();
    _printQueue.dispose();
  }
}
