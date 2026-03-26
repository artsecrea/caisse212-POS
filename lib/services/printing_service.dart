// filepath: /home/artecrea/StudioProjects/posecrea/lib/services/printing_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/localization_provider.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/order_models.dart';
import '../utils/app_localizations.dart';
import '../utils/currency_formatter.dart';
import 'daily_summary_service.dart';

/// Enum for printer purpose
enum PrinterPurpose {
  receipt, // For customer receipts
  kds, // For kitchen display/tickets
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
  final PaperSize paperSize;
  final int textSize; // 1=Normal, 2=Medium, 3=Large

  const PrinterConfig({
    this.receiptPrinterAddress,
    this.receiptPrinterName,
    this.receiptConnectionType,
    this.kdsPrinterAddress,
    this.kdsPrinterName,
    this.kdsConnectionType,
    this.kdsEnabled = true,
    this.paperSize = PaperSize.mm80,
    this.textSize = 1,
  });

  PrinterConfig copyWith({
    String? receiptPrinterAddress,
    String? receiptPrinterName,
    ConnectionType? receiptConnectionType,
    String? kdsPrinterAddress,
    String? kdsPrinterName,
    ConnectionType? kdsConnectionType,
    bool? kdsEnabled,
    PaperSize? paperSize,
    int? textSize,
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
      paperSize: paperSize ?? this.paperSize,
      textSize: textSize ?? this.textSize,
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
    'paperSize': paperSize.value,
    'textSize': textSize,
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
      paperSize: json['paperSize'] == 58 ? PaperSize.mm58 : PaperSize.mm80,
      textSize: json['textSize'] ?? 1,
    );
  }
}

/// Printing service for thermal printers
class PrintingService {
  static final PrintingService _instance = PrintingService._internal();

  factory PrintingService() => _instance;

  PrintingService._internal();

  final FlutterThermalPrinter _thermalPrinter = FlutterThermalPrinter.instance;

  List<Printer> _availablePrinters = [];
  Printer? _connectedReceiptPrinter;
  Printer? _connectedKdsPrinter;
  PrinterConfig _config = const PrinterConfig();
  bool _isScanning = false;
  Ref? _ref; // Store ref for accessing providers

  // Stream controllers
  final _printersController = StreamController<List<Printer>>.broadcast();
  final _scanningController = StreamController<bool>.broadcast();
  final _configController = StreamController<PrinterConfig>.broadcast();

  // Getters
  List<Printer> get availablePrinters => _availablePrinters;

  Printer? get connectedReceiptPrinter => _connectedReceiptPrinter;

  Printer? get connectedKdsPrinter => _connectedKdsPrinter;

  PrinterConfig get config => _config;

  bool get isScanning => _isScanning;

  Stream<List<Printer>> get printersStream => _printersController.stream;

  Stream<bool> get scanningStream => _scanningController.stream;

  Stream<PrinterConfig> get configStream => _configController.stream;

  /// Initialize the printing service
  Future<void> initialize(SharedPreferences prefs, Ref ref) async {
    _ref = ref; // Store the ref

    // Load saved configuration
    await _loadConfig(prefs);

    // Listen to printer stream
    _thermalPrinter.devicesStream.listen((printerList) {
      _availablePrinters = printerList;
      _printersController.add(printerList);
    });
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
    final paperSizeValue = prefs.getInt('printer_paper_size') ?? 80;
    final textSizeValue = prefs.getInt('printer_text_size') ?? 1;

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
      paperSize: paperSizeValue == 58 ? PaperSize.mm58 : PaperSize.mm80,
      textSize: textSizeValue,
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
    await prefs.setInt('printer_paper_size', newConfig.paperSize.value);
    await prefs.setInt('printer_text_size', newConfig.textSize);

    _configController.add(_config);
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

  /// Connect to a printer for a specific purpose
  Future<bool> connectPrinter(Printer printer, PrinterPurpose purpose) async {
    try {
      debugPrint(
        'Attempting to connect to ${purpose.name} printer: ${printer.name} (${printer.address})',
      );

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
        await _thermalPrinter.disconnect(_connectedReceiptPrinter!);
        _connectedReceiptPrinter = null;
      } else if (purpose == PrinterPurpose.kds &&
          _connectedKdsPrinter != null) {
        await _thermalPrinter.disconnect(_connectedKdsPrinter!);
        _connectedKdsPrinter = null;
      }
    } catch (e) {
      debugPrint('Error disconnecting printer: $e');
    }
  }

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
      );
    } else {
      newConfig = PrinterConfig(
        receiptPrinterAddress: _config.receiptPrinterAddress,
        receiptPrinterName: _config.receiptPrinterName,
        receiptConnectionType: _config.receiptConnectionType,
        kdsEnabled: _config.kdsEnabled,
        paperSize: _config.paperSize,
        textSize: _config.textSize,
      );
    }

    await saveConfig(prefs, newConfig);
  }

  /// Toggle KDS printing
  Future<void> toggleKds(SharedPreferences prefs, bool enabled) async {
    final newConfig = _config.copyWith(kdsEnabled: enabled);
    await saveConfig(prefs, newConfig);
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

  /// Resolve text size based on config
  PosTextSize _resolveTextSize({bool isHeader = false}) {
    if (isHeader) {
      if (_config.textSize >= 2)
        return PosTextSize.size2; // Max size for comfortable header
      return PosTextSize.size2; // Default header size
    } else {
      if (_config.textSize == 2) return PosTextSize.size2;
      if (_config.textSize >= 3)
        return PosTextSize.size2; // size3 is too big for body usually
      return PosTextSize.size1; // Default
    }
  }

  /// Resolve header text size based on config
  PosTextSize _resolveHeaderSize() {
    if (_config.textSize >= 2) return PosTextSize.size3;
    return PosTextSize.size2;
  }

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
  Future<bool> _ensurePrinterConnected(PrinterPurpose purpose) async {
    final isReceipt = purpose == PrinterPurpose.receipt;
    final currentPrinter = isReceipt
        ? _connectedReceiptPrinter
        : _connectedKdsPrinter;
    final savedAddress = isReceipt
        ? _config.receiptPrinterAddress
        : _config.kdsPrinterAddress;

    // If printer already connected, we're good
    if (currentPrinter != null) {
      debugPrint('${purpose.name} printer already connected');
      return true;
    }

    // Check if we have saved printer config
    if (savedAddress == null) {
      debugPrint('No saved ${purpose.name} printer configuration found');
      return false;
    }

    debugPrint(
      '${purpose.name} printer not connected, attempting to reconnect to saved printer: $savedAddress',
    );

    // Step 1: Try to find printer in current available printers list
    Printer? printer = _findPrinterByAddress(savedAddress);

    if (printer != null) {
      debugPrint(
        'Found saved ${purpose.name} printer in available list, attempting connection',
      );
      final connected = await connectPrinter(printer, purpose);
      if (connected) {
        debugPrint('Successfully connected to ${purpose.name} printer');
        return true;
      }
      debugPrint('Failed to connect to ${purpose.name} printer found in list');
    }

    // Step 2: Printer not in list or connection failed - try rescanning
    debugPrint(
      'Printer not found in available list or connection failed, rescanning...',
    );

    try {
      await startScan();

      // Wait a bit longer for scan to complete and populate list
      await Future.delayed(const Duration(seconds: 4));

      // Try to find printer again after scan
      printer = _findPrinterByAddress(savedAddress);

      if (printer != null) {
        debugPrint(
          'Found ${purpose.name} printer after rescan, attempting connection',
        );
        final connected = await connectPrinter(printer, purpose);
        if (connected) {
          debugPrint(
            'Successfully connected to ${purpose.name} printer after rescan',
          );
          return true;
        }
        debugPrint('Failed to connect to ${purpose.name} printer after rescan');
      } else {
        debugPrint('${purpose.name} printer still not found after rescan');
      }
    } catch (e) {
      debugPrint('Error during rescan and reconnect: $e');
    }

    debugPrint('Unable to establish ${purpose.name} printer connection');
    return false;
  }

  /// Translation helper with clear key-based fallback
  String _translate(String key, {String? fallback}) {
    final l10n = _ref?.read(localizationProvider);

    if (l10n == null) {
      // If no localizer, return formatted key or provided fallback
      return fallback ?? key.replaceAll('_', ' ');
    }

    return l10n.translate(key);
  }

  /// Helper for static text that might not need translation but should be consistent
  String _text(String key, {String? fallback}) {
    // Use the same pattern for all static text to maintain consistency
    return _translate(key, fallback: fallback);
  }

  /// Load business logo from SharedPreferences and decode it as an Image for thermal printing
  img.Image? _loadBusinessLogo() {
    try {
      if (_ref == null) return null;
      final prefs = _ref!.read(sharedPreferencesProvider);
      final base64Logo = prefs.getString('business_logo');
      if (base64Logo == null || base64Logo.isEmpty) return null;

      final logoBytes = base64Decode(base64Logo);
      final decoded = img.decodeImage(Uint8List.fromList(logoBytes));
      if (decoded == null) {
        debugPrint('Failed to decode business logo image');
        return null;
      }

      // Resize to fit receipt width (max ~384px for 58mm, ~576px for 80mm)
      final maxWidth = _config.paperSize == PaperSize.mm58 ? 384 : 576;
      if (decoded.width > maxWidth) {
        return img.copyResize(decoded, width: maxWidth);
      }
      return decoded;
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

  /// Get appropriate code table for thermal printer based on current language
  /// Returns the code table name for ESC/POS printers
  String _getCodeTableForLanguage() {
    try {
      final language = _ref?.read(languageProvider) ?? 'en';

      switch (language) {
        case 'ar':
          // Arabic - use CP864 (Arabic code page)
          return 'CP864';
        case 'fr':
          // French - use CP1252 (Western European)
          return 'CP1252';
        case 'en':
        default:
          // English and default - use CP437 (standard) or CP1252
          return 'CP1252';
      }
    } catch (e) {
      debugPrint('Error determining code table, using default CP1252: $e');
      return 'CP1252'; // Fallback to safe default
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
          storeName,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveHeaderSize(),
            width: _resolveHeaderSize(),
          ),
        );
      }

      if (storeAddress != null) {
        bytes += generator.text(
          storeAddress,
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }

      if (storePhone != null) {
        bytes += generator.text(
          '${_text('tel', fallback: 'Tel')}: $storePhone',
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }

      bytes += generator.hr();

      // Order info
      bytes += generator.text(
        '${_translate("order")} #${order.orderCode ?? "N/A"}',
        styles: PosStyles(
          align: PosAlign.left,
          bold: true,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_text('date', fallback: 'Date')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      if (cashierName != null) {
        bytes += generator.text(
          '${_translate("cashier")}: $cashierName',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (order.tableName != null) {
        bytes += generator.text(
          '${_translate("table")}: ${order.tableName}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (order.customerName != null) {
        bytes += generator.text(
          '${_text('customer', fallback: 'Customer')}: ${order.customerName}',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }
      bytes += generator.text(
        '${_text('type', fallback: 'Type')}: ${_getOrderTypeText(order.type)}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_text('persons', fallback: 'Persons')}: ${order.numberOfPersons}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );

      bytes += generator.hr();

      // Items
      for (final item in order.items) {
        bytes += generator.row([
          PosColumn(
            text: '${item.quantity}x ${item.displayName}',
            width: 8,
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        // Components
        for (final comp in item.components) {
          bytes += generator.text(
            '  + ${comp.name} x${comp.quantity}',
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          );
        }

        // Note
        if (item.note != null && item.note!.isNotEmpty) {
          bytes += generator.text(
            '  ${_text('note', fallback: 'Note')}: ${item.note}',
            styles: PosStyles(
              align: PosAlign.left,
              fontType: PosFontType.fontB,
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          );
        }
      }

      bytes += generator.hr();

      // Totals
      bytes += generator.row([
        PosColumn(
          text: '${_text('subtotal', fallback: 'Subtotal')}:',
          width: 8,
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text:
            '-${CurrencyFormatter.formatWithCurrency(order.totalDiscount, currencySymbol)}',
            width: 4,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

      bytes += generator.hr();

      bytes += generator.row([
        PosColumn(
          text: '${_text('total', fallback: 'TOTAL')}:',
          width: 6,
          styles: PosStyles(
            bold: true,
            height: _resolveHeaderSize(),
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
            height: _resolveHeaderSize(),
            width: _resolveHeaderSize(),
          ),
        ),
      ]);

      bytes += generator.emptyLines(1);
      bytes += generator.text(
        _text('thank_you_message', fallback: 'Thank you for your purchase!'),
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.barcode(
          Barcode.code128(order.orderCode!.codeUnits),
          height: 80,
          align: PosAlign.center,
        );
      }

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      debugPrint('Attempting to print receipt. Bytes length: ${bytes.length}');

      await _thermalPrinter.printData(
        _connectedReceiptPrinter!,
        bytes,
        longData: true,
      );

      debugPrint('Receipt printed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing receipt: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Print KDS ticket (kitchen order)
  Future<bool> printKdsTicket({
    required CurrentOrder order,
    required String? cashierName,
  }) async {
    if (!_config.kdsEnabled) {
      debugPrint('KDS printing is disabled in config');
      return true; // KDS disabled, consider success
    }

    // Try to ensure printer is connected
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.kds);
    if (!printerReady) {
      debugPrint('Could not establish KDS printer connection');
      return false;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Set code table based on current language (supports Arabic, French, English)
      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      // Large order number
      bytes += generator.text(
        '${_text('order', fallback: 'ORDER')} #${order.orderCode ?? "N/A"}',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveHeaderSize(), // Using resolveHeaderSize
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
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_text('type', fallback: 'Type')}: ${_getOrderTypeText(order.type, uppercase: true)}',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );

      if (order.tableName != null) {
        bytes += generator.text(
          '${_text('table', fallback: 'TABLE')}: ${order.tableName}',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveHeaderSize(), // Table name is important
            width: _resolveHeaderSize(),
          ),
        );
      }

      bytes += generator.text(
        '${_text('persons', fallback: 'Persons')}: ${order.numberOfPersons}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );

      if (order.customerName != null) {
        bytes += generator.text(
          '${_text('customer', fallback: 'Customer')}: ${order.customerName}',
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }

      bytes += generator.hr(ch: '=');

      // Items - large and clear for kitchen
      for (final item in order.items) {
        bytes += generator.text(
          '${item.quantity}x ${item.displayName}',
          styles: PosStyles(
            align: PosAlign.left,
            bold: true,
            height: _resolveHeaderSize(), // Items are main content for KDS
            width: _resolveHeaderSize(),
          ),
        );

        // Components
        for (final comp in item.components) {
          bytes += generator.text(
            '   + ${comp.name} x${comp.quantity}',
            styles: PosStyles(
              align: PosAlign.left,
              bold: true,
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          );
        }

        // Note - highlighted for kitchen
        if (item.note != null && item.note!.isNotEmpty) {
          bytes += generator.text(
            '   *** ${item.note} ***',
            styles: PosStyles(
              align: PosAlign.left,
              bold: true,
              height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.barcode(
          Barcode.code128(order.orderCode!.codeUnits),
          height: 80,
          align: PosAlign.center,
        );
      }

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      debugPrint(
        'Attempting to print KDS ticket. Bytes length: ${bytes.length}',
      );

      await _thermalPrinter.printData(
        _connectedKdsPrinter!,
        bytes,
        longData: true,
      );

      debugPrint('KDS ticket printed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing KDS ticket: $e');
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
  }) async {
    // Try to ensure printer is connected
    final printerReady = await _ensurePrinterConnected(PrinterPurpose.receipt);
    if (!printerReady) {
      debugPrint('Could not establish receipt printer connection for ticket');
      return false;
    }

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
          storeName,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveHeaderSize(),
            width: _resolveHeaderSize(),
          ),
        );
      }

      bytes += generator.text(
        _text('payment_receipt', fallback: 'PAYMENT RECEIPT'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.hr();

      // Ticket info
      bytes += generator.text(
        '${_text('ticket', fallback: 'Ticket')} #$ticketNumber',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );

      // Add order code if available
      if (orderCode != null && orderCode.isNotEmpty) {
        bytes += generator.text(
          '${_text('order', fallback: 'Order')}: $orderCode',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }

      bytes += generator.text(
        '${_text('date', fallback: 'Date')}: ${_formatDateTime(createdAt)}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      if (cashierName != null) {
        bytes += generator.text(
          '${_translate("cashier")}: $cashierName',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }
      bytes += generator.text(
        '${_text('payment', fallback: 'Payment')}: $paymentMethod',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );

      bytes += generator.hr();

      // Items
      for (final item in items) {
        final name = item['name'] ?? 'Unknown';
        final qty = item['quantity'] ?? 1;
        final price = item['price'] ?? 0.0;

        bytes += generator.row([
          PosColumn(
            text: '${qty}x $name',
            width: 8,
            styles: PosStyles(
              align: PosAlign.left,
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        // Add components if available
        final components = item['components'] as List<dynamic>?;
        if (components != null && components.isNotEmpty) {
          for (final comp in components) {
            final compName = comp['name'] ?? '';
            final compQty = comp['quantity'] ?? 1;
            final compPrice = comp['price'] ?? 0.0;

            if (compPrice > 0) {
              bytes += generator.text(
                '  + ${compQty}x $compName (+${CurrencyFormatter.formatWithCurrency(compPrice * compQty, currencySymbol)})',
                styles: PosStyles(
                  align: PosAlign.left,
                  fontType: PosFontType.fontB,
                  height: _resolveTextSize(),
                  width: _resolveTextSize(),
                ),
              );
            } else {
              bytes += generator.text(
                '  + ${compQty}x $compName',
                styles: PosStyles(
                  align: PosAlign.left,
                  fontType: PosFontType.fontB,
                  height: _resolveTextSize(),
                  width: _resolveTextSize(),
                ),
              );
            }
          }
        }
      }

      bytes += generator.hr();

      // Total
      bytes += generator.row([
        PosColumn(
          text: '${_text('paid', fallback: 'PAID')}:',
          width: 6,
          styles: PosStyles(
            bold: true,
            height: _resolveHeaderSize(),
            width: _resolveHeaderSize(),
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(amount, currencySymbol),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: _resolveHeaderSize(),
            width: _resolveHeaderSize(),
          ),
        ),
      ]);

      bytes += generator.emptyLines(1);
      bytes += generator.text(
        _text('thank_you', fallback: 'Thank you!'),
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.barcode(
          Barcode.code128(orderCode.codeUnits),
          height: 80,
          align: PosAlign.center,
        );
      }

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      debugPrint(
        'Attempting to print ticket receipt. Bytes length: ${bytes.length}',
      );

      await _thermalPrinter.printData(
        _connectedReceiptPrinter!,
        bytes,
        longData: true,
      );

      debugPrint('Ticket receipt printed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing ticket receipt: $e');
      debugPrint('Stack trace: $stackTrace');
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
        l10n?.translate('daily_summary_report') ?? 'DAILY SUMMARY REPORT',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextSize(),
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
        '${l10n?.translate('date_range') ?? 'Date Range'}:',
        styles: PosStyles(
          align: PosAlign.left,
          bold: true,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_formatDate(report.startDate)} - ${_formatDate(report.endDate)}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${l10n?.translate('number_of_sessions') ?? 'Sessions'}: ${report.totalSessions}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextSize(),
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
          '${l10n?.translate('session') ?? 'Session'} #${session.sessionCode}',
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
        bytes += generator.text(
          separator,
          styles: const PosStyles(align: PosAlign.center),
        );

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('cashier') ?? 'Cashier',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: session.cashierName ?? '#${session.cashierId}',
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('starting_balance') ?? 'Start Balance',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('total_orders') ?? 'Total Orders',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: '${session.totalOrders}',
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('expected_from_orders') ?? 'Expected Orders',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('total_tickets') ?? 'Total Tickets',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: '${session.totalTickets}',
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.row([
          PosColumn(
            text:
                l10n?.translate('expected_from_tickets') ?? 'Expected Tickets',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.emptyLines(1);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('unpaid_orders') ?? 'Unpaid Orders',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: '${session.unpaidOrders}',
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('unpaid_amount') ?? 'Unpaid Amount',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.emptyLines(1);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('paid_by_cash') ?? 'Cash',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('paid_by_card') ?? 'Card',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('paid_by_phone') ?? 'Phone',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('paid_by_other') ?? 'Other',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

        bytes += generator.emptyLines(1);

        bytes += generator.row([
          PosColumn(
            text: l10n?.translate('status') ?? 'Status',
            width: 6,
            styles: PosStyles(
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: session.status.toUpperCase(),
            width: 6,
            styles: PosStyles(
              align: PosAlign.right,
              bold: true,
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);

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
        l10n?.translate('summary') ?? 'SUMMARY',
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
          text: l10n?.translate('total_orders') ?? 'Total Orders',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: '${report.totalOrders}',
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: l10n?.translate('expected_from_orders') ?? 'Expected Orders',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: l10n?.translate('total_tickets') ?? 'Total Tickets',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: '${report.totalTickets}',
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            bold: true,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: l10n?.translate('expected_from_tickets') ?? 'Expected Tickets',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.emptyLines(1);

      bytes += generator.row([
        PosColumn(
          text: l10n?.translate('unpaid_orders') ?? 'Unpaid Orders',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: '${report.totalUnpaidOrders}',
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: l10n?.translate('unpaid_amount') ?? 'Unpaid Amount',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
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
          text: l10n?.translate('paid_by_cash') ?? 'Cash',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: l10n?.translate('paid_by_card') ?? 'Card',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: l10n?.translate('paid_by_phone') ?? 'Phone',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: l10n?.translate('paid_by_other') ?? 'Other',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
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
          text: l10n?.translate('total_paid') ?? 'TOTAL PAID',
          width: 6,
          styles: PosStyles(
            bold: true,
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.row([
        PosColumn(
          text: l10n?.translate('total_starting_balance') ?? 'Start Balance',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
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
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.text(
        doubleSeparator,
        styles: const PosStyles(align: PosAlign.center),
      );

      // Footer
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        '${l10n?.translate('printed_at') ?? 'Printed'}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      debugPrint(
        'Attempting to print daily summary report. Bytes length: ${bytes.length}',
      );

      await _thermalPrinter.printData(
        _connectedReceiptPrinter!,
        bytes,
        longData: true,
      );

      debugPrint('Daily summary report printed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing daily summary report: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Dispose streams
  void dispose() {
    _printersController.close();
    _scanningController.close();
    _configController.close();
  }
}
