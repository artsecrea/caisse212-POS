// filepath: /home/artecrea/StudioProjects/posecrea/lib/services/printing_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/order_models.dart';

/// Enum for printer purpose
enum PrinterPurpose {
  receipt,  // For customer receipts
  kds,      // For kitchen display/tickets
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

  const PrinterConfig({
    this.receiptPrinterAddress,
    this.receiptPrinterName,
    this.receiptConnectionType,
    this.kdsPrinterAddress,
    this.kdsPrinterName,
    this.kdsConnectionType,
    this.kdsEnabled = true,
    this.paperSize = PaperSize.mm80,
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
  }) {
    return PrinterConfig(
      receiptPrinterAddress: receiptPrinterAddress ?? this.receiptPrinterAddress,
      receiptPrinterName: receiptPrinterName ?? this.receiptPrinterName,
      receiptConnectionType: receiptConnectionType ?? this.receiptConnectionType,
      kdsPrinterAddress: kdsPrinterAddress ?? this.kdsPrinterAddress,
      kdsPrinterName: kdsPrinterName ?? this.kdsPrinterName,
      kdsConnectionType: kdsConnectionType ?? this.kdsConnectionType,
      kdsEnabled: kdsEnabled ?? this.kdsEnabled,
      paperSize: paperSize ?? this.paperSize,
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
  Future<void> initialize(SharedPreferences prefs) async {
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

    _config = PrinterConfig(
      receiptPrinterAddress: receiptAddress,
      receiptPrinterName: receiptName,
      receiptConnectionType: receiptType != null ? ConnectionType.values[receiptType] : null,
      kdsPrinterAddress: kdsAddress,
      kdsPrinterName: kdsName,
      kdsConnectionType: kdsType != null ? ConnectionType.values[kdsType] : null,
      kdsEnabled: kdsEnabled,
      paperSize: paperSizeValue == 58 ? PaperSize.mm58 : PaperSize.mm80,
    );
    _configController.add(_config);
  }

  /// Save configuration to SharedPreferences
  Future<void> saveConfig(SharedPreferences prefs, PrinterConfig newConfig) async {
    _config = newConfig;

    if (newConfig.receiptPrinterAddress != null) {
      await prefs.setString('printer_receipt_address', newConfig.receiptPrinterAddress!);
    } else {
      await prefs.remove('printer_receipt_address');
    }

    if (newConfig.receiptPrinterName != null) {
      await prefs.setString('printer_receipt_name', newConfig.receiptPrinterName!);
    } else {
      await prefs.remove('printer_receipt_name');
    }

    if (newConfig.receiptConnectionType != null) {
      await prefs.setInt('printer_receipt_type', newConfig.receiptConnectionType!.index);
    } else {
      await prefs.remove('printer_receipt_type');
    }

    if (newConfig.kdsPrinterAddress != null) {
      await prefs.setString('printer_kds_address', newConfig.kdsPrinterAddress!);
    } else {
      await prefs.remove('printer_kds_address');
    }

    if (newConfig.kdsPrinterName != null) {
      await prefs.setString('printer_kds_name', newConfig.kdsPrinterName!);
    } else {
      await prefs.remove('printer_kds_name');
    }

    if (newConfig.kdsConnectionType != null) {
      await prefs.setInt('printer_kds_type', newConfig.kdsConnectionType!.index);
    } else {
      await prefs.remove('printer_kds_type');
    }

    await prefs.setBool('printer_kds_enabled', newConfig.kdsEnabled);
    await prefs.setInt('printer_paper_size', newConfig.paperSize.value);

    _configController.add(_config);
  }

  /// Start scanning for printers
  Future<void> startScan() async {
    if (_isScanning) return;

    _isScanning = true;
    _scanningController.add(true);

    try {
      await _thermalPrinter.getPrinters(
        connectionTypes: [
          ConnectionType.USB,
          ConnectionType.NETWORK,
        ],
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
      await _thermalPrinter.connect(printer);

      if (purpose == PrinterPurpose.receipt) {
        _connectedReceiptPrinter = printer;
      } else {
        _connectedKdsPrinter = printer;
      }

      return true;
    } catch (e) {
      debugPrint('Error connecting to printer: $e');
      return false;
    }
  }

  /// Disconnect a printer
  Future<void> disconnectPrinter(PrinterPurpose purpose) async {
    try {
      if (purpose == PrinterPurpose.receipt && _connectedReceiptPrinter != null) {
        await _thermalPrinter.disconnect(_connectedReceiptPrinter!);
        _connectedReceiptPrinter = null;
      } else if (purpose == PrinterPurpose.kds && _connectedKdsPrinter != null) {
        await _thermalPrinter.disconnect(_connectedKdsPrinter!);
        _connectedKdsPrinter = null;
      }
    } catch (e) {
      debugPrint('Error disconnecting printer: $e');
    }
  }

  /// Set printer for a purpose (saves to config)
  Future<void> setPrinter(SharedPreferences prefs, Printer printer, PrinterPurpose purpose) async {
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
  Future<void> clearPrinter(SharedPreferences prefs, PrinterPurpose purpose) async {
    await disconnectPrinter(purpose);

    PrinterConfig newConfig;
    if (purpose == PrinterPurpose.receipt) {
      newConfig = PrinterConfig(
        kdsPrinterAddress: _config.kdsPrinterAddress,
        kdsPrinterName: _config.kdsPrinterName,
        kdsConnectionType: _config.kdsConnectionType,
        kdsEnabled: _config.kdsEnabled,
        paperSize: _config.paperSize,
      );
    } else {
      newConfig = PrinterConfig(
        receiptPrinterAddress: _config.receiptPrinterAddress,
        receiptPrinterName: _config.receiptPrinterName,
        receiptConnectionType: _config.receiptConnectionType,
        kdsEnabled: _config.kdsEnabled,
        paperSize: _config.paperSize,
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

  /// Print order receipt
  Future<bool> printOrderReceipt({
    required CurrentOrder order,
    required String? cashierName,
    String? storeName,
    String? storeAddress,
    String? storePhone,
  }) async {
    if (_connectedReceiptPrinter == null) {
      // Try to find and connect to saved printer
      final savedPrinter = _findPrinterByAddress(_config.receiptPrinterAddress);
      if (savedPrinter != null) {
        await connectPrinter(savedPrinter, PrinterPurpose.receipt);
      } else {
        return false;
      }
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Header
      if (storeName != null) {
        bytes += generator.text(
          storeName,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        );
      }

      if (storeAddress != null) {
        bytes += generator.text(storeAddress, styles: const PosStyles(align: PosAlign.center));
      }

      if (storePhone != null) {
        bytes += generator.text('Tel: $storePhone', styles: const PosStyles(align: PosAlign.center));
      }

      bytes += generator.hr();

      // Order info
      bytes += generator.text('Order #${order.orderId ?? "N/A"}',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('Date: ${_formatDateTime(DateTime.now())}',
          styles: const PosStyles(align: PosAlign.left));
      if (cashierName != null) {
        bytes += generator.text('Cashier: $cashierName',
            styles: const PosStyles(align: PosAlign.left));
      }
      if (order.tableName != null) {
        bytes += generator.text('Table: ${order.tableName}',
            styles: const PosStyles(align: PosAlign.left));
      }
      if (order.customerName != null) {
        bytes += generator.text('Customer: ${order.customerName}',
            styles: const PosStyles(align: PosAlign.left));
      }
      bytes += generator.text('Type: ${order.type == "DINE_IN" ? "Dine In" : "Take Away"}',
          styles: const PosStyles(align: PosAlign.left));
      bytes += generator.text('Persons: ${order.numberOfPersons}',
          styles: const PosStyles(align: PosAlign.left));

      bytes += generator.hr();

      // Items
      for (final item in order.items) {
        bytes += generator.row([
          PosColumn(
            text: '${item.quantity}x ${item.productName}',
            width: 8,
            styles: const PosStyles(align: PosAlign.left),
          ),
          PosColumn(
            text: '\$${item.totalPrice.toStringAsFixed(2)}',
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);

        // Components
        for (final comp in item.components) {
          bytes += generator.text('  + ${comp.name} x${comp.quantity}',
              styles: const PosStyles(align: PosAlign.left));
        }

        // Note
        if (item.note != null && item.note!.isNotEmpty) {
          bytes += generator.text('  Note: ${item.note}',
              styles: const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB));
        }
      }

      bytes += generator.hr();

      // Totals
      bytes += generator.row([
        PosColumn(text: 'Subtotal:', width: 8),
        PosColumn(
          text: '\$${order.subtotal.toStringAsFixed(2)}',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

      if (order.totalDiscount > 0) {
        bytes += generator.row([
          PosColumn(text: 'Discount:', width: 8),
          PosColumn(
            text: '-\$${order.totalDiscount.toStringAsFixed(2)}',
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      if (order.tax > 0) {
        bytes += generator.row([
          PosColumn(text: 'Tax:', width: 8),
          PosColumn(
            text: '\$${order.tax.toStringAsFixed(2)}',
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      bytes += generator.hr();

      bytes += generator.row([
        PosColumn(
          text: 'TOTAL:',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        ),
        PosColumn(
          text: '\$${order.total.toStringAsFixed(2)}',
          width: 6,
          styles: const PosStyles(
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
          ),
        ),
      ]);

      bytes += generator.emptyLines(1);
      bytes += generator.text('Thank you for your purchase!',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      await _thermalPrinter.printData(
        _connectedReceiptPrinter!,
        bytes,
        longData: true,
      );

      return true;
    } catch (e) {
      debugPrint('Error printing receipt: $e');
      return false;
    }
  }

  /// Print KDS ticket (kitchen order)
  Future<bool> printKdsTicket({
    required CurrentOrder order,
    required String? cashierName,
  }) async {
    if (!_config.kdsEnabled) return true; // KDS disabled, consider success

    if (_connectedKdsPrinter == null) {
      // Try to find and connect to saved printer
      final savedPrinter = _findPrinterByAddress(_config.kdsPrinterAddress);
      if (savedPrinter != null) {
        await connectPrinter(savedPrinter, PrinterPurpose.kds);
      } else {
        return false;
      }
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Large order number
      bytes += generator.text(
        'ORDER #${order.orderId ?? "N/A"}',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );

      bytes += generator.emptyLines(1);

      // Order info
      bytes += generator.text('Time: ${_formatTime(DateTime.now())}',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('Type: ${order.type == "DINE_IN" ? "DINE IN" : "TAKE AWAY"}',
          styles: const PosStyles(align: PosAlign.center, bold: true));

      if (order.tableName != null) {
        bytes += generator.text(
          'TABLE: ${order.tableName}',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
          ),
        );
      }

      bytes += generator.text('Persons: ${order.numberOfPersons}',
          styles: const PosStyles(align: PosAlign.center));

      if (order.customerName != null) {
        bytes += generator.text('Customer: ${order.customerName}',
            styles: const PosStyles(align: PosAlign.center));
      }

      bytes += generator.hr(ch: '=');

      // Items - large and clear for kitchen
      for (final item in order.items) {
        bytes += generator.text(
          '${item.quantity}x ${item.productName}',
          styles: const PosStyles(
            align: PosAlign.left,
            bold: true,
            height: PosTextSize.size2,
          ),
        );

        // Components
        for (final comp in item.components) {
          bytes += generator.text(
            '   + ${comp.name} x${comp.quantity}',
            styles: const PosStyles(align: PosAlign.left, bold: true),
          );
        }

        // Note - highlighted for kitchen
        if (item.note != null && item.note!.isNotEmpty) {
          bytes += generator.text(
            '   *** ${item.note} ***',
            styles: const PosStyles(align: PosAlign.left, bold: true),
          );
        }

        bytes += generator.emptyLines(1);
      }

      bytes += generator.hr(ch: '=');
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      await _thermalPrinter.printData(
        _connectedKdsPrinter!,
        bytes,
        longData: true,
      );

      return true;
    } catch (e) {
      debugPrint('Error printing KDS ticket: $e');
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
    String? cashierName,
    String? storeName,
  }) async {
    if (_connectedReceiptPrinter == null) {
      final savedPrinter = _findPrinterByAddress(_config.receiptPrinterAddress);
      if (savedPrinter != null) {
        await connectPrinter(savedPrinter, PrinterPurpose.receipt);
      } else {
        return false;
      }
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_config.paperSize, profile);
      List<int> bytes = [];

      // Header
      if (storeName != null) {
        bytes += generator.text(
          storeName,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
          ),
        );
      }

      bytes += generator.text('PAYMENT RECEIPT',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.hr();

      // Ticket info
      bytes += generator.text('Ticket #$ticketNumber',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('Date: ${_formatDateTime(createdAt)}',
          styles: const PosStyles(align: PosAlign.left));
      if (cashierName != null) {
        bytes += generator.text('Cashier: $cashierName',
            styles: const PosStyles(align: PosAlign.left));
      }
      bytes += generator.text('Payment: $paymentMethod',
          styles: const PosStyles(align: PosAlign.left));

      bytes += generator.hr();

      // Items
      for (final item in items) {
        final name = item['name'] ?? 'Unknown';
        final qty = item['quantity'] ?? 1;
        final price = item['price'] ?? 0.0;

        bytes += generator.row([
          PosColumn(text: '${qty}x $name', width: 8),
          PosColumn(
            text: '\$${(price as num).toStringAsFixed(2)}',
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }

      bytes += generator.hr();

      // Total
      bytes += generator.row([
        PosColumn(
          text: 'PAID:',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        ),
        PosColumn(
          text: '\$${amount.toStringAsFixed(2)}',
          width: 6,
          styles: const PosStyles(
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
          ),
        ),
      ]);

      bytes += generator.emptyLines(1);
      bytes += generator.text('Thank you!',
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      await _thermalPrinter.printData(
        _connectedReceiptPrinter!,
        bytes,
        longData: true,
      );

      return true;
    } catch (e) {
      debugPrint('Error printing ticket: $e');
      return false;
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

  /// Dispose streams
  void dispose() {
    _printersController.close();
    _scanningController.close();
    _configController.close();
  }
}
