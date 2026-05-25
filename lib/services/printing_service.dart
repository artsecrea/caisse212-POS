// filepath: /home/artecrea/StudioProjects/posecrea/lib/services/printing_service.dart
import 'dart:async';
import 'dart:convert';
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
    'paperSize': paperSize.value,
    'textSize': textSize,
    'printingLanguage': printingLanguage,
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
      paperSize: json['paperSize'] == 58 ? PaperSize.mm58 : PaperSize.mm80,
      textSize: json['textSize'] ?? 1,
      printingLanguage: json['printingLanguage'] ?? 'en',
    );
  }
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

  /// Stream of printing status messages (null = idle, non-null = status text shown in overlay)
  Stream<String?> get printingStatusStream => _printingStatusController.stream;

  /// Initialize the printing service
  Future<void> initialize(SharedPreferences prefs, Ref ref) async {
    _ref = ref; // Store the ref

    // Load saved configuration
    await _loadConfig(prefs);

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
      paperSize: paperSizeValue == 58 ? PaperSize.mm58 : PaperSize.mm80,
      textSize: textSizeValue,
      printingLanguage: printingLanguage,
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
    await prefs.setInt('printer_paper_size', newConfig.paperSize.value);
    await prefs.setInt('printer_text_size', newConfig.textSize);
    await prefs.setString('printer_language', newConfig.printingLanguage);

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
    final currentPrinter = isReceipt ? _connectedReceiptPrinter : _connectedKdsPrinter;
    final savedAddress = isReceipt ? _config.receiptPrinterAddress : _config.kdsPrinterAddress;

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
    return printL10n.translate(key);
  }

  /// Helper for static text that might not need translation but should be consistent
  String _text(String key, {String? fallback}) {
    return _translate(key, fallback: fallback);
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

      // Custom ticket header
      if (_ref != null) {
        try {
          final settings = _ref!.read(settingsProvider);
          if (settings.ticketHeader.isNotEmpty) {
            bytes += generator.text(
              settings.ticketHeader,
              styles: PosStyles(
                align: PosAlign.center,
                height: _resolveTextSize(),
                width: _resolveTextSize(),
              ),
            );
          }
        } catch (e) {
          debugPrint('Error reading ticket header from settings: $e');
        }
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
      if (order.customerPhone != null && order.customerPhone!.isNotEmpty) {
        bytes += generator.text(
          '${_text('phone', fallback: 'Phone')}: ${order.customerPhone}',
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
                height: _resolveTextSize(),
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

      await _thermalPrinter.printData(
        _connectedReceiptPrinter!,
        bytes,
        longData: true,
      );

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
    KdsPrintMode mode = KdsPrintMode.modificationsOnly,
    List<int> stationIds = const [],
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

    _isPrintingInProgress = true;
    _printingStatusController.add(_translate('printing_kds', fallback: 'Printing KDS tickets...'));

    try {
      // Get database to fetch product station information
      if (_ref == null) {
        debugPrint('Warning: _ref is null, cannot group by stations');
        // Fall back to single ticket printing
        final itemsToPrint = _filterItemsByMode(order.items, mode);
        if (itemsToPrint.isEmpty) {
          debugPrint('No items to print for mode: $mode');
          _isPrintingInProgress = false;
          _printingStatusController.add(null);
          return true;
        }
        return await _printKdsTicketForStation(
          order: order,
          stationName: _text('general', fallback: 'General'),
          items: itemsToPrint,
          cashierName: cashierName,
          mode: mode,
        );
      }
      
      final database = _ref!.read(databaseProvider);
      
      // Filter items based on print mode
      final itemsToPrint = _filterItemsByMode(order.items, mode);
      
      if (itemsToPrint.isEmpty) {
        debugPrint('No items to print for mode: $mode');
        _isPrintingInProgress = false;
        _printingStatusController.add(null);
        return true; // Nothing to print is success
      }
      
      // Group items by station
      final Map<String, List<OrderItem>> itemsByStation = {};
      final List<OrderItem> itemsWithoutStation = [];
      
      final bool filterByStation = stationIds.isNotEmpty;

      for (final item in itemsToPrint) {
        // Fetch product to get station info
        final product = await (database.select(database.products)
          ..where((tbl) => tbl.id.equals(item.productId)))
          .getSingleOrNull();

        if (product?.stationId != null) {
          // Skip if station filter active and this station not selected
          if (filterByStation && !stationIds.contains(product!.stationId)) continue;

          // Fetch station name
          final station = await (database.select(database.stations)
            ..where((tbl) => tbl.id.equals(product!.stationId!)))
            .getSingleOrNull();

          final stationName = station?.name ?? 'Station ${product!.stationId}';
          itemsByStation.putIfAbsent(stationName, () => []).add(item);
        } else {
          // Items without station only go to General when no specific filter is active
          if (!filterByStation) itemsWithoutStation.add(item);
        }
      }

      // If there are items without station, add them to a default station
      if (itemsWithoutStation.isNotEmpty) {
        itemsByStation.putIfAbsent(_text('general', fallback: 'General'), () => []).addAll(itemsWithoutStation);
      }
      
      // Print one ticket per station
      bool allSuccessful = true;
      int stationCount = 0;
      
      for (final stationEntry in itemsByStation.entries) {
        stationCount++;
        final stationName = stationEntry.key;
        final stationItems = stationEntry.value;
        
        debugPrint('Printing KDS ticket $stationCount/${itemsByStation.length} for station: $stationName (mode: $mode)');
        
        final success = await _printKdsTicketForStation(
          order: order,
          stationName: stationName,
          items: stationItems,
          cashierName: cashierName,
          mode: mode,
        );
        
        if (!success) {
          allSuccessful = false;
          debugPrint('Failed to print ticket for station: $stationName');
        } else {
          // Mark items as printed in database
          await _markItemsAsPrinted(database, stationItems);
        }
        
        // Small delay between prints to avoid printer buffer issues
        if (stationCount < itemsByStation.length) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      debugPrint('KDS tickets printed: ${allSuccessful ? 'all successful' : 'some failed'}');
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
        // Return only items that haven't been printed yet (kdsPrintedAt is null)
        return items.where((item) => item.kdsPrintedAt == null).toList();
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
            ));
          debugPrint('Marked item ${item.id} as printed at $now');
        } catch (e) {
          debugPrint('Error marking item ${item.id} as printed: $e');
        }
      }
    }
  }

  /// Print a single KDS ticket for a specific station
  Future<bool> _printKdsTicketForStation({
    required CurrentOrder order,
    required String stationName,
    required List<OrderItem> items,
    required String? cashierName,
    KdsPrintMode mode = KdsPrintMode.modificationsOnly,
  }) async {
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Set code table based on current language (supports Arabic, French, English)
      bytes += generator.setGlobalCodeTable(_getCodeTableForLanguage());

      // STATION NAME - Very prominent at the top
      bytes += generator.text(
        '*** ${stationName.toUpperCase()} ***',
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
        '${_text('order', fallback: 'ORDER')} #${order.orderCode ?? "N/A"}',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveHeaderSize(),
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
            height: _resolveHeaderSize(),
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
      if (order.customerPhone != null && order.customerPhone!.isNotEmpty) {
        bytes += generator.text(
          '${_text('phone', fallback: 'Phone')}: ${order.customerPhone}',
          styles: PosStyles(
            align: PosAlign.center,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }

      bytes += generator.hr(ch: '=');

      // Items - large and clear for kitchen (only items for this station)
      for (final item in items) {
        bytes += generator.text(
          '${item.quantity}x ${item.displayName}',
          styles: PosStyles(
            align: PosAlign.left,
            bold: true,
            height: _resolveHeaderSize(),
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
          Barcode.code128(order.orderCode!.split('')),
          height: 80,
          align: PosAlign.center,
        );
      }

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      debugPrint(
        'Attempting to print KDS ticket for $stationName. Bytes length: ${bytes.length}',
      );

      await _thermalPrinter.printData(
        _connectedKdsPrinter!,
        bytes,
        longData: true,
      );

      debugPrint('KDS ticket for $stationName printed successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error printing KDS ticket for $stationName: $e');
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
    String? customerName,
    String? customerPhone,
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

      // Custom ticket header
      if (_ref != null) {
        try {
          final settings = _ref!.read(settingsProvider);
          if (settings.ticketHeader.isNotEmpty) {
            bytes += generator.text(
              settings.ticketHeader,
              styles: PosStyles(
                align: PosAlign.center,
                height: _resolveTextSize(),
                width: _resolveTextSize(),
              ),
            );
          }
        } catch (e) {
          debugPrint('Error reading ticket header from settings: $e');
        }
      }

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
      if (customerName != null) {
        bytes += generator.text(
          '${_text('customer', fallback: 'Customer')}: $customerName',
          styles: PosStyles(
            align: PosAlign.left,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        );
      }
      if (customerPhone != null && customerPhone.isNotEmpty) {
        bytes += generator.text(
          '${_text('phone', fallback: 'Phone')}: $customerPhone',
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
                height: _resolveTextSize(),
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

      await _thermalPrinter.printData(
        _connectedReceiptPrinter!,
        bytes,
        longData: true,
      );

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
        '${printL10n.translate('date_range')}:',
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
        '${printL10n.translate('number_of_sessions')}: ${report.totalSessions}',
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
          '${printL10n.translate('session')} #${session.sessionCode}',
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
            text: printL10n.translate('cashier'),
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
            text: printL10n.translate('starting_balance'),
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
            text: printL10n.translate('total_orders'),
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
            text: printL10n.translate('expected_from_orders'),
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
            text: printL10n.translate('total_tickets'),
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
                printL10n.translate('expected_from_tickets'),
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
            text: printL10n.translate('unpaid_orders'),
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
            text: printL10n.translate('unpaid_amount'),
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
            text: printL10n.translate('paid_by_cash'),
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
            text: printL10n.translate('paid_by_card'),
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
            text: printL10n.translate('paid_by_phone'),
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
            text: printL10n.translate('paid_by_other'),
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
            text: printL10n.translate('status'),
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
          text: printL10n.translate('expected_from_orders'),
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
          text: printL10n.translate('total_tickets'),
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
          text: printL10n.translate('expected_from_tickets'),
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
          text: printL10n.translate('unpaid_orders'),
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
          text: printL10n.translate('unpaid_amount'),
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
          text: printL10n.translate('paid_by_cash'),
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
          text: printL10n.translate('paid_by_card'),
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
          text: printL10n.translate('paid_by_phone'),
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
          text: printL10n.translate('paid_by_other'),
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
          text: printL10n.translate('total_paid'),
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
          text: printL10n.translate('total_starting_balance'),
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
        '${printL10n.translate('printed_at')}: ${_formatDateTime(DateTime.now())}',
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
            height: _resolveHeaderSize(),
            width: _resolveHeaderSize(),
          ),
        );
      }

      bytes += generator.text(
        _translate('daily_orders_report', fallback: 'Daily Orders Report'),
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );

      bytes += generator.hr();

      bytes += generator.text(
        '${_text('date', fallback: 'Date')}: ${_formatDate(reportDate)}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_text('user', fallback: 'User')}: $userName ($userCode)',
        styles: PosStyles(
          align: PosAlign.left,
          bold: true,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        '${_text('total_orders', fallback: 'Orders')}: ${orders.length}',
        styles: PosStyles(
          align: PosAlign.left,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );

      bytes += generator.hr();

      bytes += generator.row([
        PosColumn(
          text: _text('order', fallback: 'Order'),
          width: 4,
          styles: PosStyles(
            bold: true,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: _text('amount', fallback: 'Amount'),
          width: 5,
          styles: PosStyles(
            bold: true,
            align: PosAlign.right,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: _text('status', fallback: 'Status'),
          width: 3,
          styles: PosStyles(
            bold: true,
            align: PosAlign.right,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

      bytes += generator.hr();

      for (final order in orders) {
        bytes += generator.row([
          PosColumn(
            text: order.orderCode,
            width: 4,
            styles: PosStyles(
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
          PosColumn(
            text: CurrencyFormatter.formatWithCurrency(order.amount, currencySymbol),
            width: 5,
            styles: PosStyles(
              align: PosAlign.right,
              height: _resolveTextSize(),
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
              height: _resolveTextSize(),
              width: _resolveTextSize(),
            ),
          ),
        ]);
      }

      bytes += generator.hr();

      final paidOrders = orders.where((o) => o.isPaid).toList();
      final unpaidOrders = orders.where((o) => !o.isPaid).toList();
      final totalPaid = paidOrders.fold(0.0, (sum, o) => sum + o.amount);
      final totalUnpaid = unpaidOrders.fold(0.0, (sum, o) => sum + o.amount);

      bytes += generator.row([
        PosColumn(
          text: '${_text('paid', fallback: 'Paid')} (${paidOrders.length}):',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(totalPaid, currencySymbol),
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
          text: '${_text('unpaid', fallback: 'Unpaid')} (${unpaidOrders.length}):',
          width: 6,
          styles: PosStyles(
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
        PosColumn(
          text: CurrencyFormatter.formatWithCurrency(totalUnpaid, currencySymbol),
          width: 6,
          styles: PosStyles(
            align: PosAlign.right,
            height: _resolveTextSize(),
            width: _resolveTextSize(),
          ),
        ),
      ]);

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
          text: CurrencyFormatter.formatWithCurrency(totalPaid + totalUnpaid, currencySymbol),
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
        '${_text('printed_at', fallback: 'Printed')}: ${_formatDateTime(DateTime.now())}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );

      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      await _thermalPrinter.printData(
        _connectedReceiptPrinter!,
        bytes,
        longData: true,
      );

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
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.hr();
      bytes += generator.text(
        _formatDateTime(DateTime.now()),
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.text(
        'Paper: ${_config.paperSize == PaperSize.mm58 ? "58mm" : "80mm"}  '
        'Text: ${_config.textSize == 1 ? "Normal" : _config.textSize == 2 ? "Large" : "XL"}',
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.hr();
      bytes += generator.text(
        'Printer OK',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      final printer = purpose == PrinterPurpose.receipt
          ? _connectedReceiptPrinter!
          : _connectedKdsPrinter!;
      await _thermalPrinter.printData(printer, bytes, longData: true);

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
