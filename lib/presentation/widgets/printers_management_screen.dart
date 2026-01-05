// filepath: /home/artecrea/StudioProjects/posecrea/lib/presentation/widgets/printers_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../../providers/database_providers.dart';
import '../../services/printing_service.dart';

class PrintersManagementScreen extends ConsumerStatefulWidget {
  const PrintersManagementScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PrintersManagementScreen> createState() => _PrintersManagementScreenState();
}

class _PrintersManagementScreenState extends ConsumerState<PrintersManagementScreen> {
  List<Printer> _printers = [];
  bool _isScanning = false;
  PrinterConfig _config = const PrinterConfig();

  @override
  void initState() {
    super.initState();
    _initializePrinting();
  }

  void _initializePrinting() {
    final printingService = ref.read(printingServiceProvider);

    // Listen to printers stream
    printingService.printersStream.listen((printers) {
      if (mounted) {
        setState(() {
          _printers = printers;
        });
      }
    });

    // Listen to scanning state
    printingService.scanningStream.listen((scanning) {
      if (mounted) {
        setState(() {
          _isScanning = scanning;
        });
      }
    });

    // Listen to config changes
    printingService.configStream.listen((config) {
      if (mounted) {
        setState(() {
          _config = config;
        });
      }
    });

    // Get initial values
    _printers = printingService.availablePrinters;
    _isScanning = printingService.isScanning;
    _config = printingService.config;
  }

  Future<void> _startScan() async {
    final printingService = ref.read(printingServiceProvider);
    await printingService.startScan();
  }

  Future<void> _stopScan() async {
    final printingService = ref.read(printingServiceProvider);
    await printingService.stopScan();
  }

  Future<void> _setPrinter(Printer printer, PrinterPurpose purpose) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);

    await printingService.setPrinter(prefs, printer, purpose);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${purpose == PrinterPurpose.receipt ? "Receipt" : "KDS"} printer set: ${printer.name}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _clearPrinter(PrinterPurpose purpose) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);

    await printingService.clearPrinter(prefs, purpose);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${purpose == PrinterPurpose.receipt ? "Receipt" : "KDS"} printer cleared'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _toggleKds(bool enabled) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await printingService.toggleKds(prefs, enabled);
  }

  Future<void> _setPaperSize(PaperSize size) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await printingService.setPaperSize(prefs, size);
  }

  Future<void> _testPrint(PrinterPurpose purpose) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Test print sent to ${purpose == PrinterPurpose.receipt ? "receipt" : "KDS"} printer'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Management'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
            onPressed: _isScanning ? _stopScan : _startScan,
            tooltip: _isScanning ? 'Stop Scan' : 'Scan for Printers',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scan controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.search, size: 24),
                        const SizedBox(width: 12),
                        const Text(
                          'Scan for Printers',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (_isScanning)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isScanning ? null : _startScan,
                            icon: const Icon(Icons.search),
                            label: Text(_isScanning ? 'Scanning...' : 'Start Scan'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isScanning ? _stopScan : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop Scan'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.settings, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'Printer Settings',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // KDS Toggle
                    SwitchListTile(
                      title: const Text('Enable KDS Printing'),
                      subtitle: const Text('Print kitchen tickets automatically'),
                      value: _config.kdsEnabled,
                      onChanged: _toggleKds,
                    ),
                    const Divider(),
                    // Paper Size
                    ListTile(
                      title: const Text('Paper Size'),
                      subtitle: Text(_config.paperSize == PaperSize.mm58 ? '58mm' : '80mm'),
                      trailing: SegmentedButton<PaperSize>(
                        segments: const [
                          ButtonSegment(value: PaperSize.mm58, label: Text('58mm')),
                          ButtonSegment(value: PaperSize.mm80, label: Text('80mm')),
                        ],
                        selected: {_config.paperSize},
                        onSelectionChanged: (values) => _setPaperSize(values.first),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Receipt Printer
            _buildPrinterSection(
              title: 'Receipt Printer',
              subtitle: 'For customer receipts and payment confirmations',
              icon: Icons.receipt_long,
              purpose: PrinterPurpose.receipt,
              configuredName: _config.receiptPrinterName,
              configuredType: _config.receiptConnectionType,
            ),

            const SizedBox(height: 16),

            // KDS Printer
            _buildPrinterSection(
              title: 'KDS Printer',
              subtitle: 'For kitchen display tickets',
              icon: Icons.restaurant,
              purpose: PrinterPurpose.kds,
              configuredName: _config.kdsPrinterName,
              configuredType: _config.kdsConnectionType,
              enabled: _config.kdsEnabled,
            ),

            const SizedBox(height: 24),

            // Available Printers
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.print, size: 24),
                        const SizedBox(width: 12),
                        const Text(
                          'Available Printers',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          '${_printers.length} found',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_printers.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.print_disabled, size: 48, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('No printers found'),
                              Text(
                                'Click "Start Scan" to search for printers',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _printers.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final printer = _printers[index];
                          final isReceiptPrinter = printer.address == _config.receiptPrinterAddress;
                          final isKdsPrinter = printer.address == _config.kdsPrinterAddress;

                          return ListTile(
                            leading: Icon(
                              printer.connectionType == ConnectionType.USB
                                  ? Icons.usb
                                  : Icons.wifi,
                              color: (isReceiptPrinter || isKdsPrinter)
                                  ? Colors.green
                                  : null,
                            ),
                            title: Text(printer.name ?? 'Unknown Printer'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Type: ${printer.connectionType?.name ?? "Unknown"}'),
                                if (isReceiptPrinter)
                                  const Text(
                                    '✓ Receipt Printer',
                                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                if (isKdsPrinter)
                                  const Text(
                                    '✓ KDS Printer',
                                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'receipt') {
                                  _setPrinter(printer, PrinterPurpose.receipt);
                                } else if (value == 'kds') {
                                  _setPrinter(printer, PrinterPurpose.kds);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'receipt',
                                  child: Row(
                                    children: [
                                      Icon(Icons.receipt_long),
                                      SizedBox(width: 8),
                                      Text('Set as Receipt Printer'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'kds',
                                  enabled: _config.kdsEnabled,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.restaurant),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Set as KDS Printer',
                                        style: TextStyle(
                                          color: _config.kdsEnabled ? null : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required PrinterPurpose purpose,
    required String? configuredName,
    required ConnectionType? configuredType,
    bool enabled = true,
  }) {
    final isConfigured = configuredName != null;

    return Card(
      color: enabled ? null : Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: enabled ? null : Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: enabled ? null : Colors.grey,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: enabled ? Colors.grey[600] : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!enabled)
                  const Chip(
                    label: Text('Disabled'),
                    backgroundColor: Colors.grey,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (isConfigured)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      configuredType == ConnectionType.USB ? Icons.usb : Icons.wifi,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            configuredName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            configuredType?.name ?? 'Unknown',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.print, color: Colors.blue),
                      onPressed: enabled ? () => _testPrint(purpose) : null,
                      tooltip: 'Test Print',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: enabled ? () => _clearPrinter(purpose) : null,
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.print_disabled, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Text(
                      'No printer configured',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
