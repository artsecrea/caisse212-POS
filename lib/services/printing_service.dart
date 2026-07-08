// filepath: /home/artecrea/StudioProjects/posecrea/lib/services/printing_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Socket;
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
import '../data/database/app_database.dart';
import '../domain/models/order_models.dart';
import '../utils/app_localizations.dart';
import '../utils/currency_formatter.dart';
import 'daily_summary_service.dart';

/// Enum for printer purpose
enum PrinterPurpose {
  receipt, // For customer receipts
  kds, // For kitchen display/tickets
}

/// Enum for KDS print mode
enum KdsPrintMode {
  full, // Print all items in the order
  modificationsOnly, // Print only new/unprinted items
}

/// Distinct print outputs whose auto-printing can be configured independently.
enum PrintOutput { orderTicket, customerReceipt, storeCopy, kds }

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
  final bool cashDrawerKick; // Open cash drawer
  final bool cashDrawerCashOnly; // Only kick drawer for cash payments
  final bool splitKdsByStation; // Split kitchen tickets per station
  final KdsPrintMode defaultKdsMode; // Default kitchen print mode
  // When `splitKdsByStation` is on AND there's more than one station to
  // print, send all station tickets to the printer in a SINGLE driver job
  // (one `_dispatchBytes` call) — with paper cuts between sections — instead
  // of one job per station. This avoids the "third sequential print fails"
  // class of bug on Windows USB drivers, where rapid back-to-back jobs
  // overwhelm the spooler / driver. Default is true; turn it off if you
  // prefer the legacy per-job behavior.
  final bool consolidateKdsJob;

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
    this.orderTicketRule = const PrintRule(),
    this.customerReceiptRule = const PrintRule(),
    this.storeCopyRule = const PrintRule(enabled: false),
    this.kdsRule = const PrintRule(),
    this.autoPrintOnPayment = true,
    this.customerCopies = 1,
    this.reprintWatermark = true,
    this.cashDrawerKick = false,
    this.cashDrawerCashOnly = true,
    this.splitKdsByStation = true,
    this.defaultKdsMode = KdsPrintMode.modificationsOnly,
    this.consolidateKdsJob = true,
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
    bool? cashDrawerKick,
    bool? cashDrawerCashOnly,
    bool? splitKdsByStation,
    KdsPrintMode? defaultKdsMode,
    bool? consolidateKdsJob,
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
      cashDrawerKick: cashDrawerKick ?? this.cashDrawerKick,
      cashDrawerCashOnly: cashDrawerCashOnly ?? this.cashDrawerCashOnly,
      splitKdsByStation: splitKdsByStation ?? this.splitKdsByStation,
      defaultKdsMode: defaultKdsMode ?? this.defaultKdsMode,
      consolidateKdsJob: consolidateKdsJob ?? this.consolidateKdsJob,
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
    'cashDrawerKick': cashDrawerKick,
    'cashDrawerCashOnly': cashDrawerCashOnly,
    'splitKdsByStation': splitKdsByStation,
    'defaultKdsMode': defaultKdsMode.index,
    'consolidateKdsJob': consolidateKdsJob,
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
          : const PrintRule(),
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
      cashDrawerKick: json['cashDrawerKick'] ?? false,
      cashDrawerCashOnly: json['cashDrawerCashOnly'] ?? true,
      splitKdsByStation: json['splitKdsByStation'] ?? true,
      defaultKdsMode: json['defaultKdsMode'] != null
          ? KdsPrintMode.values[json['defaultKdsMode']]
          : KdsPrintMode.modificationsOnly,
      consolidateKdsJob: json['consolidateKdsJob'] ?? true,
    );
  }
}

/// A named entry in the per-station printer pool. Lives in SharedPrefs as
/// part of a JSON-encoded list under `station_printer_pool_v1`. Identified
/// by a stable [id] so [stationAssignments] (stationId -> printerId) keeps
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

/// SharedPrefs key holding the JSON-encoded list of [NamedPrinter] entries.
const _kPrefsPrinterPool = 'station_printer_pool_v1';

/// SharedPrefs key holding the JSON-encoded `Map<String stationId, String printerId>`.
const _kPrefsStationAssignments = 'station_printer_assignments_v1';

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

  // Per-station printer routing (SharedPrefs-persisted, survives DB sync).
  List<NamedPrinter> _printerPool = [];
  Map<int, String> _stationAssignments = {}; // stationId -> NamedPrinter.id

  final _poolController = StreamController<List<NamedPrinter>>.broadcast();
  final _assignmentsController =
      StreamController<Map<int, String>>.broadcast();

  // Stream controllers
  final _printersController = StreamController<List<Printer>>.broadcast();
  final _scanningController = StreamController<bool>.broadcast();
  final _configController = StreamController<PrinterConfig>.broadcast();
  final _printingStatusController = StreamController<String?>.broadcast();

  bool _isPrintingInProgress = false;

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

  /// stationId -> NamedPrinter.id. Stations missing from this map fall back
  /// to the global KDS printer at print time.
  Map<int, String> get stationAssignments => Map.unmodifiable(_stationAssignments);

  Stream<List<NamedPrinter>> get printerPoolStream => _poolController.stream;
  Stream<Map<int, String>> get stationAssignmentsStream =>
      _assignmentsController.stream;

  /// Stream of printing status messages (null = idle, non-null = status text shown in overlay)
  Stream<String?> get printingStatusStream => _printingStatusController.stream;

  /// Initialize the printing service
  Future<void> initialize(SharedPreferences prefs, Ref ref) async {
    _ref = ref; // Store the ref

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
      orderTicketRule: loadRule('printer_rule_order_ticket'),
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
      defaultKdsMode: defaultKdsModeIndex != null
          ? KdsPrintMode.values[defaultKdsModeIndex]
          : KdsPrintMode.modificationsOnly,
      consolidateKdsJob:
          prefs.getBool('printer_consolidate_kds_job') ?? true,
    );
    _configController.add(_config);
  }

  /// Save configuration to SharedPreferences
  Future<void> saveConfig(
    SharedPreferences prefs,
    PrinterConfig newConfig,
  ) async {
    _config = newConfig;

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
    await prefs.setInt(
        'printer_default_kds_mode', newConfig.defaultKdsMode.index);
    await prefs.setBool(
        'printer_consolidate_kds_job', newConfig.consolidateKdsJob);

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
        _stationAssignments = map.map(
          (k, v) => MapEntry(int.parse(k.toString()), v.toString()),
        );
      } catch (e) {
        debugPrint('Failed to decode station assignments: $e');
      }
    }

    _poolController.add(printerPool);
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
    final pruned = <int, String>{};
    var changed = false;
    for (final entry in _stationAssignments.entries) {
      if (validIds.contains(entry.value)) {
        pruned[entry.key] = entry.value;
      } else {
        changed = true;
      }
    }
    if (changed) {
      await saveStationAssignments(prefs, pruned);
    }
  }

  /// Persist the station→printer map.
  Future<void> saveStationAssignments(
    SharedPreferences prefs,
    Map<int, String> assignments,
  ) async {
    _stationAssignments = Map.of(assignments);
    final encoded = jsonEncode(
      _stationAssignments.map((k, v) => MapEntry(k.toString(), v)),
    );
    await prefs.setString(_kPrefsStationAssignments, encoded);
    _assignmentsController.add(stationAssignments);
  }

  /// Resolve which physical printer a given station's items should go to.
  /// Returns `null` to mean "use the default global KDS printer" — covers a
  /// null stationId (no station on the product), an unassigned station, and
  /// a station mapped to a now-deleted pool entry.
  _KdsTarget? _resolveTargetForStation(int? stationId) {
    if (stationId == null) return null;
    final printerId = _stationAssignments[stationId];
    if (printerId == null) return null;
    final printer = _printerPool.where((p) => p.id == printerId).cast<NamedPrinter?>().firstWhere(
          (_) => true,
          orElse: () => null,
        );
    if (printer == null) return null;
    return _KdsTarget(
      address: printer.address,
      name: printer.name.isNotEmpty ? printer.name : printer.label,
      type: printer.connectionType,
    );
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
  }) async {
    if (address.isEmpty) return false;
    final parts = address.split(':');
    final host = parts[0];
    final port = parts.length > 1
        ? int.tryParse(parts[1]) ?? 9100
        : 9100;
    Socket? sock;
    try {
      sock = await Socket.connect(host, port, timeout: timeout);
      if (bytes.isNotEmpty) {
        sock.add(bytes);
        await sock.flush();
      }
      await sock.close();
      return true;
    } catch (e) {
      debugPrint('TCP send failed for $host:$port: $e');
      try {
        await sock?.close();
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
  Future<bool> _dispatchBytes(
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
  Future<bool> sendRawBytes(PrinterPurpose purpose, List<int> bytes) async {
    if (bytes.isEmpty) return false;
    return _dispatchBytes(purpose, bytes);
  }

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
  Future<bool> kickCashDrawer() async {
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
  }

  /// Orchestrates all payment-time printing according to [PrinterConfig]:
  /// customer receipt (x copies), store copy, and the cash drawer kick.
  /// Honors the per-output rules and the [autoPrintOnPayment] master switch.
  Future<void> printPaymentDocuments({
    required int ticketId,
    required String ticketNumber,
    required double amount,
    required String paymentMethod,
    required DateTime createdAt,
    required List<Map<String, dynamic>> items,
    required String orderType,
    required bool hasTable,
    String source = 'POS',
    String? currency,
    String? orderCode,
    String? cashierName,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    String? customerName,
    String? customerPhone,
    String? deliveryAddress,
    String? tableName,
    int? numberOfPersons,
  }) async {
    if (!_config.printingEnabled || !_config.autoPrintOnPayment) return;

    Future<void> printOne({required bool storeCopy}) {
      return printTicketReceipt(
        ticketId: ticketId,
        ticketNumber: ticketNumber,
        amount: amount,
        paymentMethod: paymentMethod,
        createdAt: createdAt,
        items: items,
        currency: currency,
        orderCode: orderCode,
        cashierName: cashierName,
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
  }

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
  Future<bool> _ensurePrinterConnected(PrinterPurpose purpose,
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
  String _sanitizeForThermal(String? input) {
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

      // Resize to fit receipt width (max ~384px for 58mm, ~576px for 80mm)
      final maxWidth = _config.paperSize == PaperSize.mm58 ? 384 : 576;
      img.Image resized = decoded;
      if (decoded.width > maxWidth) {
        resized = img.copyResize(decoded, width: maxWidth);
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

  /// Print the business logo at the top of a receipt if available.
  /// Returns the bytes to prepend to the receipt.
  List<int> _printLogoHeader(Generator generator) {
    try {
      final logo = _loadBusinessLogo();
      if (logo == null) return [];

      List<int> bytes = [];
      bytes += generator.image(logo, align: PosAlign.center);
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
  }) async {
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
  }

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
  }) async {
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
  }

  /// Print order receipt
  Future<bool> printOrderReceipt({
    required CurrentOrder order,
    required String? cashierName,
    String? currency,
    String? storeName,
    String? storeAddress,
    String? storePhone,
  }) async {
    // Try to ensure printer is connected
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection');
      return false;
    }

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing', fallback: 'Printing...'));

    try {
      final currencySymbol = _getCurrency(currency);
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Set code table based on current language (supports Arabic, French, English)
      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      // Print business logo if available
      bytes += _printLogoHeader(generator);

      // Header
      if (storeName != null) {
        bytes += generator.text(
          _safe(storeName),
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveHeaderHeight(),
            width: _resolveHeaderSize(),
          ),
        );
      }

      if (storeAddress != null) {
        bytes += generator.text(
          _safe(storeAddress),
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }

      if (storePhone != null) {
        bytes += generator.text(
          '${_text('tel', fallback: 'Tel')}: ${_safe(storePhone)}',
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }

      // Custom ticket header
      if (_ref != null) {
        try {
          final settings = _ref!.read(settingsProvider);
          if (settings.ticketHeader.isNotEmpty) {
            bytes += generator.text(
              _safe(settings.ticketHeader),
              styles: PosStyles(
                align: PosAlign.center,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            );
          }
        } catch (e) {
          debugPrint('Error reading ticket header from settings: $e');
        }
      }

      bytes += _sepMajor(generator);

      // Order info
      bytes += generator.text(
        '${_translate("order")} #${order.orderCode ?? "N/A"}',
        styles: PosStyles(
          align: PosAlign.left,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_text('date', fallback: 'Date')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      if (cashierName != null) {
        bytes += generator.text(
          '${_translate("cashier")}: ${_safe(cashierName)}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (order.tableName != null) {
        bytes += generator.text(
          '${_translate("table")}: ${_safe(order.tableName)}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (order.customerName != null) {
        bytes += generator.text(
          '${_text('customer', fallback: 'Customer')}: ${_safe(order.customerName)}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (order.customerPhone != null && order.customerPhone!.isNotEmpty) {
        bytes += generator.text(
          '${_text('phone', fallback: 'Phone')}: ${_safe(order.customerPhone)}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      bytes += generator.text(
        '${_text('type', fallback: 'Type')}: ${_getOrderTypeText(order.type)}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      // Delivery address (delivery orders only)
      if (order.type == 'DELIVERY' &&
          order.deliveryAddress != null &&
          order.deliveryAddress!.trim().isNotEmpty) {
        bytes += generator.text(
          '${_text('delivery_address', fallback: 'Delivery address')}: ${_safe(order.deliveryAddress)}',
          styles: PosStyles(
            align: PosAlign.left,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      bytes += generator.text(
        '${_text('persons', fallback: 'Persons')}: ${order.numberOfPersons}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      bytes += _sepMinor(generator);

      // Items
      for (final item in order.items) {
        bytes += generator.row([
          PosColumn(
            text: '${item.quantity}x ${_safe(item.displayName)}',
            width: 8,
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: CurrencyFormatter.formatWithCurrency(
              item.totalPrice,
              currencySymbol,
            ),
            width: 4,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        // Components
        for (final comp in item.components) {
          bytes += generator.text(
            '  + ${_safe(comp.name)} x${comp.quantity}',
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
        }

        // Note
        if (item.note != null && item.note!.isNotEmpty) {
          bytes += generator.text(
            '  ${_text('note', fallback: 'Note')}: ${_safe(item.note)}',
            styles: PosStyles(
              align: PosAlign.left,
              fontType: PosFontType.fontB,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
        }
      }

      bytes += _sepMinor(generator);

      // Totals
      bytes += generator.row([
        PosColumn(
          text: '${_text('subtotal', fallback: 'Subtotal')}:',
          width: 8,
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
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
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      if (order.totalDiscount > 0) {
        bytes += generator.row([
          PosColumn(
            text: '${_text('discount', fallback: 'Discount')}:',
            width: 8,
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
            '-${CurrencyFormatter.formatWithCurrency(order.totalDiscount, currencySymbol)}',
            width: 4,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }


      if (order.tax > 0) {
        bytes += generator.row([
          PosColumn(
            text: '${_text('tax', fallback: 'Tax')}:',
            width: 8,
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
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
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

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
          text: CurrencyFormatter.formatWithCurrency(
            order.total,
            currencySymbol,
          ),
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
        _text('thank_you_message', fallback: 'Thank you for your purchase!'),
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      // Add barcode if order code exists
      if (order.orderCode != null && order.orderCode!.isNotEmpty) {
        bytes += generator.emptyLines(1);
        // Use text() to print the order code as text above barcode for clarity
        bytes += generator.text(
          order.orderCode!,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.barcode(
          Barcode.code128(order.orderCode!.split('')),
          height: 80,
          align: PosAlign.center,
        );
      }

      // Print custom footer text if configured
      if (_ref != null) {
        try {
          final settings = _ref!.read(settingsProvider);
          if (settings.ticketFooter.isNotEmpty) {
            bytes += generator.emptyLines(1);
            bytes += generator.text(
              settings.ticketFooter,
              styles: PosStyles(
                align: PosAlign.center,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            );
          }
        } catch (e) {
          debugPrint('Error reading ticket footer from settings: $e');
        }
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
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing receipt: $e');
      debugPrint('Stack trace: $stackTrace');
      _isPrintingInProgress = false;
      _printingStatusController.add(null);
      return false;
    }
  }

  /// Print KDS ticket (kitchen order)
  /// [stationIds]: if non-empty, only print tickets for those stations. Empty = all stations.
  Future<bool> printKdsTicket({
    required CurrentOrder order,
    required String? cashierName,
    KdsPrintMode? mode,
    List<int> stationIds = const [],
  }) async {
    if (!_config.kdsEnabled) {
      debugPrint('KDS printing is disabled in config');
      return true; // KDS disabled, consider success
    }

    // Resolve print mode from the configured default when caller doesn't override
    final resolvedMode = mode ?? _config.defaultKdsMode;

    // Try to ensure printer is connected
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.kds);
    if (!printerReady) {
      debugPrint('Could not establish KDS printer connection');
      return false;
    }

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing_kds', fallback: 'Printing KDS tickets...'));

    try {
      // Get database to fetch product station information
      if (_ref == null) {
        debugPrint('Warning: _ref is null, cannot group by stations');
        // Fall back to single ticket printing
        final itemsToPrint = _filterItemsByMode(order.items, resolvedMode);
        if (itemsToPrint.isEmpty) {
          debugPrint('No items to print for mode: $resolvedMode');
          _isPrintingInProgress = false;
          _printingStatusController.add(null);
          return true;
        }
        return await _printKdsTicketForStation(
          order: order,
          stationName: _text('general', fallback: 'General'),
          items: itemsToPrint,
          cashierName: cashierName,
          mode: resolvedMode,
        );
      }

      final database = _ref!.read(databaseProvider);

      // Filter items based on print mode
      final itemsToPrint = _filterItemsByMode(order.items, resolvedMode);

      if (itemsToPrint.isEmpty) {
        debugPrint('No items to print for mode: $resolvedMode');
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return true; // Nothing to print is success
      }

      // When per-station splitting is disabled, print a single consolidated
      // kitchen ticket with all items instead of grouping by station.
      if (!_config.splitKdsByStation) {
        final success = await _printKdsTicketForStation(
          order: order,
          stationName: _text('general', fallback: 'General'),
          items: itemsToPrint,
          cashierName: cashierName,
          mode: resolvedMode,
        );
        if (success) {
          await _markItemsAsPrinted(database, itemsToPrint);
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
        final name = station?.name ?? 'Station $id';
        stationNameCache[id] = name;
        return name;
      }

      for (final item in itemsToPrint) {
        final product = await (database.select(database.products)
              ..where((tbl) => tbl.id.equals(item.productId)))
            .getSingleOrNull();

        // Full station set: primary stationId + extra (join) stations.
        final productStationIds = <int>{
          if (product?.stationId != null) product!.stationId!,
        };
        final extraRows = await (database.select(database.productStations)
              ..where((tbl) => tbl.productId.equals(item.productId)))
            .get();
        productStationIds.addAll(extraRows.map((e) => e.stationId));

        if (productStationIds.isEmpty) {
          if (!filterByStation) {
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

      // Resolve each station's target printer, then group station entries by
      // resolved printer address. Stations with no assignment share a
      // synthetic '__default__' key so they all collapse into the single
      // global-KDS print job (today's behavior).
      const defaultKey = '__default__';
      final Map<String, _KdsTarget?> targetsByKey = {};
      final Map<String, Map<String, List<OrderItem>>> printerGroups = {};

      for (final entry in itemsByStationId.entries) {
        final sid = entry.key;
        final items = entry.value;
        final target = sid != null ? _resolveTargetForStation(sid) : null;
        final key = target?.address ?? defaultKey;
        targetsByKey[key] = target;

        final stationName = sid == null
            ? _text('general', fallback: 'General')
            : await stationNameFor(sid);

        final group = printerGroups.putIfAbsent(key, () => <String, List<OrderItem>>{});
        group.putIfAbsent(stationName, () => []).addAll(items);
      }

      // Count how many station sections each item appears in (across ALL
      // printers). Marking deferred until the end and only applied when an
      // item's every section succeeded — multi-station / multi-printer items
      // must not get half-marked.
      final stationsPerItem = <int, int>{};
      for (final printerGroup in printerGroups.values) {
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
          );
          if (ok) {
            for (final stationItems in itemsByStation.values) {
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
                );
              }
            }

            if (success) {
              for (final item in stationItems) {
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
        await _markItemsAsPrinted(database, markedById.values.toList());
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
  }

  /// Filter items based on KDS print mode
  List<OrderItem> _filterItemsByMode(List<OrderItem> items, KdsPrintMode mode) {
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
          if (item.ticketId != null) continue;
          final delta = item.quantity - item.kdsPrintedQuantity;
          if (delta > 0.0001) {
            out.add(item.copyWith(kdsPrintQuantity: delta));
          }
        }
        return out;
    }
  }

  /// Mark items as printed in the database
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
  Future<List<int>> _buildKdsTicketBytesForStation({
    required CurrentOrder order,
    required String stationName,
    required List<OrderItem> items,
    required KdsPrintMode mode,
    required Generator generator,
  }) async {
    List<int> bytes = [];

    // Set code table based on current language (supports Arabic, French, English)
    bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

    // STATION NAME - Very prominent at the top
      bytes += generator.text(
        '*** ${_safe(stationName).toUpperCase()} ***',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );

      bytes += generator.emptyLines(1);

      // Print mode indicator (only for modifications mode)
      if (mode == KdsPrintMode.modificationsOnly) {
        bytes += generator.text(
          '=== ${_text('new_items', fallback: 'NEW ITEMS')} ===',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
            reverse: true, // Inverted colors for emphasis
          ),
        );
        bytes += generator.emptyLines(1);
      }

      // Large order number
      bytes += generator.text(
        '${_text('order', fallback: 'ORDER')} #${_safe(order.orderCode ?? "N/A")}',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveHeaderHeight(),
          width: _resolveHeaderSize(),
        ),
      );

      bytes += generator.emptyLines(1);

      // Order info
      bytes += generator.text(
        '${_text('time', fallback: 'Time')}: ${_formatTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_text('type', fallback: 'Type')}: ${_getOrderTypeText(order.type, uppercase: true)}',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      if (order.tableName != null) {
        bytes += generator.text(
          '${_text('table', fallback: 'TABLE')}: ${_safe(order.tableName)}',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveHeaderHeight(),
            width: _resolveHeaderSize(),
          ),
        );
      }

      bytes += generator.text(
        '${_text('persons', fallback: 'Persons')}: ${order.numberOfPersons}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      if (order.customerName != null) {
        bytes += generator.text(
          '${_text('customer', fallback: 'Customer')}: ${_safe(order.customerName)}',
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (order.customerPhone != null && order.customerPhone!.isNotEmpty) {
        bytes += generator.text(
          '${_text('phone', fallback: 'Phone')}: ${_safe(order.customerPhone)}',
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }

      bytes += generator.hr(ch: '=');

      // Items - large and clear for kitchen (only items for this station)
      for (final item in items) {
        // In modifications-only mode kdsPrintQuantity carries the delta (added
        // units); otherwise fall back to the full quantity.
        final printQty = item.kdsPrintQuantity ?? item.quantity;
        bytes += generator.text(
          '${formatQty(printQty)}x ${_safe(item.displayName)}',
          styles: PosStyles(
            align: PosAlign.left,
            bold: true,
            height: _resolveHeaderHeight(),
            width: _resolveHeaderSize(),
          ),
        );

        // Components
        for (final comp in item.components) {
          bytes += generator.text(
            '   + ${_safe(comp.name)} x${comp.quantity}',
            styles: PosStyles(
              align: PosAlign.left,
              bold: true,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
        }

        // Note - highlighted for kitchen
        if (item.note != null && item.note!.isNotEmpty) {
          bytes += generator.text(
            '   *** ${_safe(item.note)} ***',
            styles: PosStyles(
              align: PosAlign.left,
              bold: true,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
        }

        bytes += generator.emptyLines(1);
      }

      bytes += generator.hr(ch: '=');

      // Add barcode if order code exists
      if (order.orderCode != null && order.orderCode!.isNotEmpty) {
        bytes += generator.emptyLines(1);
        bytes += generator.text(
          order.orderCode!,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.barcode(
          Barcode.code128(order.orderCode!.split('')),
          height: 80,
          align: PosAlign.center,
        );
      }

      bytes += generator.emptyLines(2);
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
    required String paymentMethod,
    required DateTime createdAt,
    required List<Map<String, dynamic>> items,
    String? currency,
    String? orderCode,
    String? cashierName,
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
  }) async {
    // Try to ensure printer is connected
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for ticket');
      return false;
    }

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing', fallback: 'Printing...'));

    try {
      final currencySymbol = _getCurrency(currency);
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Set code table based on current language (supports Arabic, French, English)
      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

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
            height: _resolveHeaderHeight(),
            width: _resolveHeaderSize(),
          ),
        );
      }
      if (storeAddress != null && storeAddress.trim().isNotEmpty) {
        bytes += generator.text(
          _safe(storeAddress),
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (storePhone != null && storePhone.trim().isNotEmpty) {
        bytes += generator.text(
          '${_text('tel', fallback: 'Tel')}: ${_safe(storePhone)}',
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }

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
      if (_ref != null) {
        try {
          final settings = _ref!.read(settingsProvider);
          if (settings.ticketHeader.isNotEmpty) {
            bytes += generator.text(
              _safe(settings.ticketHeader),
              styles: PosStyles(
                align: PosAlign.center,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            );
          }
        } catch (e) {
          debugPrint('Error reading ticket header from settings: $e');
        }
      }

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

      // Add order code if available
      if (orderCode != null && orderCode.isNotEmpty) {
        bytes += generator.text(
          '${_text('order', fallback: 'Order')}: ${_safe(orderCode)}',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }

      bytes += generator.text(
        '${_text('date', fallback: 'Date')}: ${_formatDateTime(createdAt)}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      if (cashierName != null) {
        bytes += generator.text(
          '${_translate("cashier")}: ${_safe(cashierName)}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (orderType != null && orderType.isNotEmpty) {
        bytes += generator.text(
          '${_text('type', fallback: 'Type')}: ${_getOrderTypeText(orderType)}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (tableName != null && tableName.trim().isNotEmpty) {
        bytes += generator.text(
          '${_translate("table")}: ${_safe(tableName)}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (numberOfPersons != null && numberOfPersons > 1) {
        bytes += generator.text(
          '${_text('persons', fallback: 'Persons')}: $numberOfPersons',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (customerName != null) {
        bytes += generator.text(
          '${_text('customer', fallback: 'Customer')}: ${_safe(customerName)}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (customerPhone != null && customerPhone.isNotEmpty) {
        bytes += generator.text(
          '${_text('phone', fallback: 'Phone')}: ${_safe(customerPhone)}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (deliveryAddress != null && deliveryAddress.trim().isNotEmpty) {
        bytes += generator.text(
          '${_text('delivery_address', fallback: 'Delivery address')}: ${_safe(deliveryAddress)}',
          styles: PosStyles(
            align: PosAlign.left,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
      }
      bytes += generator.text(
        '${_text('payment', fallback: 'Payment')}: $paymentMethod',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      bytes += _sepMinor(generator);

      // Items
      for (final item in items) {
        final name = _safe(item['name'] as String? ?? 'Unknown');
        final qty = item['quantity'] ?? 1;
        final price = item['price'] ?? 0.0;

        bytes += generator.row([
          PosColumn(
            text: '${qty}x $name',
            width: 8,
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: CurrencyFormatter.formatWithCurrency(
              price as double,
              currencySymbol,
            ),
            width: 4,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        // Add components if available
        final components = item['components'] as List<dynamic>?;
        if (components != null && components.isNotEmpty) {
          for (final comp in components) {
            final compName = _safe(comp['name'] as String? ?? '');
            final compQty = comp['quantity'] ?? 1;
            final compPrice = comp['price'] ?? 0.0;

            if (compPrice > 0) {
              bytes += generator.text(
                '  + ${compQty}x $compName (+${CurrencyFormatter.formatWithCurrency(compPrice * compQty, currencySymbol)})',
                styles: PosStyles(
                  align: PosAlign.left,
                  fontType: PosFontType.fontB,
                  height: _resolveTextHeight(),
                  width: _resolveTextSize(),
                ),
              );
            } else {
              bytes += generator.text(
                '  + ${compQty}x $compName',
                styles: PosStyles(
                  align: PosAlign.left,
                  fontType: PosFontType.fontB,
                  height: _resolveTextHeight(),
                  width: _resolveTextSize(),
                ),
              );
            }
          }
        }
      }

      bytes += _sepMinor(generator);

      // Total
      bytes += generator.row([
        PosColumn(
          text: '${_text('paid', fallback: 'PAID')}:',
          width: 6,
          styles: PosStyles(
            bold: true,
            height: _resolveHeaderHeight(),
            width: _resolveHeaderSize(),
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(amount, currencySymbol),
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
        _text('thank_you', fallback: 'Thank you!'),
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );

      // Add barcode if order code exists
      if (orderCode != null && orderCode.isNotEmpty) {
        bytes += generator.emptyLines(1);
        bytes += generator.text(
          orderCode,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.barcode(
          Barcode.code128(orderCode.split('')),
          height: 80,
          align: PosAlign.center,
        );
      }

      // Print custom footer text if configured
      if (_ref != null) {
        try {
          final settings = _ref!.read(settingsProvider);
          if (settings.ticketFooter.isNotEmpty) {
            bytes += generator.emptyLines(1);
            bytes += generator.text(
              settings.ticketFooter,
              styles: PosStyles(
                align: PosAlign.center,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            );
          }
        } catch (e) {
          debugPrint('Error reading ticket footer from settings: $e');
        }
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
  }

  /// Helper method to get order type text
  String _getOrderTypeText(String? type, {bool uppercase = false}) {
    if (type == "DINE_IN") {
      return uppercase ? _text('dine_in_upper', fallback: 'DINE IN') : _text('dine_in', fallback: 'Dine In');
    } else {
      return uppercase ? _text('take_away_upper', fallback: 'TAKE AWAY') : _text('take_away', fallback: 'Take Away');
    }
  }


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
  }) async {
    if (_connectedReceiptPrinter == null) {
      debugPrint('No receipt printer connected');
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

      final separator = ''.padLeft(32, '-');
      final doubleSeparator = ''.padLeft(32, '=');

      // Header
      bytes += generator.text(
        businessName ?? 'POS SYSTEM',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        printL10n.translate('daily_summary_report'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        doubleSeparator,
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);

      // Date range
      bytes += generator.text(
        '${printL10n.translate('date_range')}:',
        styles: PosStyles(
          align: PosAlign.left,
          bold: true,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_formatDate(report.startDate)} - ${_formatDate(report.endDate)}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${printL10n.translate('number_of_sessions')}: ${report.totalSessions}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextHeight(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        separator,
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);

      // Sessions details
      for (final session in report.sessions) {
        bytes += generator.text(
          '${printL10n.translate('session')} #${session.sessionCode}',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.text(
          separator,
          styles: const PosStyles(align: PosAlign.center),
        );

        bytes += generator.row([
          PosColumn(
            text: printL10n.translate('cashier'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: session.cashierName ?? '#${session.cashierId}',
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
            text: printL10n.translate('starting_balance'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
                currencyFormatter?.format(session.startingBalance) ??
                session.startingBalance.toStringAsFixed(2),
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
            text: printL10n.translate('total_orders'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: '${session.totalOrders}',
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
            text: printL10n.translate('expected_from_orders'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
                currencyFormatter?.format(session.expectedFromOrders) ??
                session.expectedFromOrders.toStringAsFixed(2),
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
            text: printL10n.translate('total_tickets'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: '${session.totalTickets}',
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
            text:
                printL10n.translate('expected_from_tickets'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
                currencyFormatter?.format(session.expectedFromTickets) ??
                session.expectedFromTickets.toStringAsFixed(2),
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.emptyLines(1);

        bytes += generator.row([
          PosColumn(
            text: printL10n.translate('unpaid_orders'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: '${session.unpaidOrders}',
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
            text: printL10n.translate('unpaid_amount'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
                currencyFormatter?.format(session.unpaidAmount) ??
                session.unpaidAmount.toStringAsFixed(2),
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.emptyLines(1);

        bytes += generator.row([
          PosColumn(
            text: printL10n.translate('paid_by_cash'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
                currencyFormatter?.format(session.paidByCash) ??
                session.paidByCash.toStringAsFixed(2),
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
            text: printL10n.translate('paid_by_card'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
                currencyFormatter?.format(session.paidByCard) ??
                session.paidByCard.toStringAsFixed(2),
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
            text: printL10n.translate('paid_by_phone'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
                currencyFormatter?.format(session.paidByPhone) ??
                session.paidByPhone.toStringAsFixed(2),
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
            text: printL10n.translate('paid_by_other'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
                currencyFormatter?.format(session.paidByOther) ??
                session.paidByOther.toStringAsFixed(2),
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.emptyLines(1);

        bytes += generator.row([
          PosColumn(
            text: printL10n.translate('status'),
            width: 6,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: session.status.toUpperCase(),
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              bold: true,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        // Per-session waiter breakdown. Skipped when the session has no
        // waiter-attributed orders (cashier-only shift).
        if (session.waiterBreakdown.isNotEmpty) {
          bytes += generator.emptyLines(1);
          bytes += generator.text(
            printL10n.translate('by_waiter').toUpperCase(),
            styles: PosStyles(
              align: PosAlign.left,
              bold: true,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
          for (final w in session.waiterBreakdown) {
            bytes += generator.text(
              w.waiterName,
              styles: PosStyles(
                align: PosAlign.left,
                bold: true,
                height: _resolveTextHeight(),
                width: _resolveTextSize(),
              ),
            );
            bytes += generator.row([
              PosColumn(
                text:
                    '  ${printL10n.translate('orders')}: ${w.ordersCount}',
                width: 6,
                styles: const PosStyles(align: PosAlign.left),
              ),
              PosColumn(
                text:
                    '${printL10n.translate('paid')}: ${currencyFormatter?.format(w.paid) ?? w.paid.toStringAsFixed(2)}',
                width: 6,
                styles: const PosStyles(align: PosAlign.right),
              ),
            ]);
            if (w.owed > 0.005) {
              bytes += generator.row([
                PosColumn(
                  text: '  ${printL10n.translate('owed')}',
                  width: 6,
                  styles: const PosStyles(align: PosAlign.left, bold: true),
                ),
                PosColumn(
                  text: currencyFormatter?.format(w.owed) ??
                      w.owed.toStringAsFixed(2),
                  width: 6,
                  styles:
                      const PosStyles(align: PosAlign.right, bold: true),
                ),
              ]);
            }
          }
        }

        bytes += generator.text(
          separator,
          styles: const PosStyles(align: PosAlign.center),
        );
        bytes += generator.emptyLines(1);
      }

      // Summary
      bytes += generator.text(
        doubleSeparator,
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        printL10n.translate('summary'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        doubleSeparator,
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);

      bytes += generator.row([
        PosColumn(
          text: printL10n.translate('total_orders'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: '${report.totalOrders}',
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: printL10n.translate('expected_from_orders'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text:
              currencyFormatter?.format(report.totalExpectedFromOrders) ??
              report.totalExpectedFromOrders.toStringAsFixed(2),
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
          text: printL10n.translate('total_tickets'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: '${report.totalTickets}',
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: printL10n.translate('expected_from_tickets'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text:
              currencyFormatter?.format(report.totalExpectedFromTickets) ??
              report.totalExpectedFromTickets.toStringAsFixed(2),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.emptyLines(1);

      bytes += generator.row([
        PosColumn(
          text: printL10n.translate('unpaid_orders'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: '${report.totalUnpaidOrders}',
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
          text: printL10n.translate('unpaid_amount'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text:
              currencyFormatter?.format(report.totalUnpaidAmount) ??
              report.totalUnpaidAmount.toStringAsFixed(2),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.emptyLines(1);
      bytes += generator.text(
        separator,
        styles: const PosStyles(align: PosAlign.center),
      );

      bytes += generator.row([
        PosColumn(
          text: printL10n.translate('paid_by_cash'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text:
              currencyFormatter?.format(report.totalPaidByCash) ??
              report.totalPaidByCash.toStringAsFixed(2),
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
          text: printL10n.translate('paid_by_card'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text:
              currencyFormatter?.format(report.totalPaidByCard) ??
              report.totalPaidByCard.toStringAsFixed(2),
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
          text: printL10n.translate('paid_by_phone'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text:
              currencyFormatter?.format(report.totalPaidByPhone) ??
              report.totalPaidByPhone.toStringAsFixed(2),
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
          text: printL10n.translate('paid_by_other'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text:
              currencyFormatter?.format(report.totalPaidByOther) ??
              report.totalPaidByOther.toStringAsFixed(2),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.text(
        separator,
        styles: const PosStyles(align: PosAlign.center),
      );

      bytes += generator.row([
        PosColumn(
          text: printL10n.translate('total_paid'),
          width: 6,
          styles: PosStyles(
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text:
              currencyFormatter?.format(report.totalPaid) ??
              report.totalPaid.toStringAsFixed(2),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: printL10n.translate('total_starting_balance'),
          width: 6,
          styles: PosStyles(
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text:
              currencyFormatter?.format(report.totalStartingBalance) ??
              report.totalStartingBalance.toStringAsFixed(2),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.text(
        doubleSeparator,
        styles: const PosStyles(align: PosAlign.center),
      );

      // Z-report block — only when the report is scoped to a single session
      // AND the cashier actually entered a counted-cash figure on close. This
      // turns the daily-summary print into a session reconciliation slip
      // without changing how regular multi-session daily summaries render.
      if (report.sessions.length == 1 &&
          report.sessions.first.countedCash != null) {
        final s = report.sessions.first;
        // Mirrors SessionSummary.expectedCashAtEnd.
        final expected = s.startingBalance + s.paidByCash;
        final counted = s.countedCash ?? expected;
        final variance = s.variance ?? (counted - expected);
        final cur = _getCurrency(null);

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
        bytes += generator.text(
          doubleSeparator,
          styles: const PosStyles(align: PosAlign.center),
        );
        bytes += generator.text(
          printL10n.translate('z_report'),
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.text(
          doubleSeparator,
          styles: const PosStyles(align: PosAlign.center),
        );
        bytes += twoCol(
          '${printL10n.translate('expected_cash')}:',
          CurrencyFormatter.formatWithCurrency(expected, cur),
        );
        bytes += twoCol(
          '${printL10n.translate('counted_cash')}:',
          CurrencyFormatter.formatWithCurrency(counted, cur),
        );
        bytes += twoCol(
          '${printL10n.translate('variance')}:',
          '${variance >= 0 ? '+' : ''}${CurrencyFormatter.formatWithCurrency(variance, cur)}',
          bold: true,
        );
        if (s.countNotes != null && s.countNotes!.trim().isNotEmpty) {
          bytes += generator.emptyLines(1);
          bytes += generator.text(
            '${printL10n.translate('count_notes')}:',
            styles: PosStyles(
              bold: true,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
          bytes += generator.text(
            s.countNotes!,
            styles: PosStyles(
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
        }
        bytes += generator.text(
          doubleSeparator,
          styles: const PosStyles(align: PosAlign.center),
        );
      }

      // Report-level waiter rollup. Skipped when no session had a waiter.
      if (report.totalWaiterBreakdown.isNotEmpty) {
        bytes += generator.emptyLines(1);
        bytes += generator.text(
          doubleSeparator,
          styles: const PosStyles(align: PosAlign.center),
        );
        bytes += generator.text(
          printL10n.translate('by_waiter').toUpperCase(),
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextHeight(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.text(
          doubleSeparator,
          styles: const PosStyles(align: PosAlign.center),
        );
        bytes += generator.emptyLines(1);

        for (final w in report.totalWaiterBreakdown) {
          bytes += generator.text(
            w.waiterName,
            styles: PosStyles(
              align: PosAlign.left,
              bold: true,
              height: _resolveTextHeight(),
              width: _resolveTextSize(),
            ),
          );
          bytes += generator.row([
            PosColumn(
              text: '  ${printL10n.translate('orders')}: ${w.ordersCount}',
              width: 6,
              styles: const PosStyles(align: PosAlign.left),
            ),
            PosColumn(
              text:
                  '${printL10n.translate('paid')}: ${currencyFormatter?.format(w.paid) ?? w.paid.toStringAsFixed(2)}',
              width: 6,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]);
          if (w.owed > 0.005) {
            bytes += generator.row([
              PosColumn(
                text: '  ${printL10n.translate('owed')}',
                width: 6,
                styles: const PosStyles(align: PosAlign.left, bold: true),
              ),
              PosColumn(
                text: currencyFormatter?.format(w.owed) ??
                    w.owed.toStringAsFixed(2),
                width: 6,
                styles: const PosStyles(align: PosAlign.right, bold: true),
              ),
            ]);
          }
          bytes += generator.emptyLines(1);
        }
      }

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
  }

  /// Print daily orders summary for a specific user
  Future<bool> printDailyOrdersForUser({
    required String userName,
    required String userCode,
    required List<UserDailyOrderEntry> orders,
    required DateTime reportDate,
    String? currency,
    String? storeName,
  }) async {
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
  }

  /// Print a test page to verify printer is working.
  Future<bool> printTestPage(PrinterPurpose purpose) async {
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
  }

  /// Dispose streams
  void dispose() {
    _printersController.close();
    _scanningController.close();
    _configController.close();
    _printingStatusController.close();
  }
}
