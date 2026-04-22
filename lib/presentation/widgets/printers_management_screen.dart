// filepath: /home/artecrea/StudioProjects/posecrea/lib/presentation/widgets/printers_management_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../../providers/database_providers.dart';
import '../../services/printing_service.dart';
import '../../utils/app_localizations.dart';

class PrintersManagementScreen extends ConsumerStatefulWidget {
  const PrintersManagementScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PrintersManagementScreen> createState() => _PrintersManagementScreenState();
}

class _PrintersManagementScreenState extends ConsumerState<PrintersManagementScreen> {
  List<Printer> _printers = [];
  bool _isScanning = false;
  PrinterConfig _config = const PrinterConfig();
  final TextEditingController _businessNameController = TextEditingController();
  Uint8List? _logoBytes;

  @override
  void initState() {
    super.initState();
    _initializePrinting();
    _loadBusinessInfo();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    super.dispose();
  }

  void _loadBusinessInfo() {
    final prefs = ref.read(sharedPreferencesProvider);
    final savedName = prefs.getString('business_name') ?? '';
    _businessNameController.text = savedName;

    final base64Logo = prefs.getString('business_logo');
    if (base64Logo != null && base64Logo.isNotEmpty) {
      try {
        _logoBytes = base64Decode(base64Logo);
      } catch (e) {
        debugPrint('Error decoding saved logo: $e');
      }
    }
  }

  Future<void> _saveBusinessName(String name) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (name.isEmpty) {
      await prefs.remove('business_name');
    } else {
      await prefs.setString('business_name', name);
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      Uint8List? bytes;

      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes != null) {
        final prefs = ref.read(sharedPreferencesProvider);
        final base64Logo = base64Encode(bytes);
        await prefs.setString('business_logo', base64Logo);
        if (mounted) {
          setState(() {
            _logoBytes = bytes;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.translate('success')),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _clearLogo() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove('business_logo');
    if (mounted) {
      setState(() {
        _logoBytes = null;
      });
    }
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
    final l10n = AppLocalizations.of(context)!;

    await printingService.setPrinter(prefs, printer, purpose);

    if (mounted) {
      final printerType = purpose == PrinterPurpose.receipt
        ? l10n.translate('receipt_printer')
        : l10n.translate('kds_printer');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$printerType: ${printer.name}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _clearPrinter(PrinterPurpose purpose) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final l10n = AppLocalizations.of(context)!;

    await printingService.clearPrinter(prefs, purpose);

    if (mounted) {
      final printerType = purpose == PrinterPurpose.receipt
        ? l10n.translate('receipt_printer')
        : l10n.translate('kds_printer');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.translate('remove')}: $printerType'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _toggleKds(bool enabled) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await printingService.toggleKds(prefs, enabled);
  }

  Future<void> _togglePrinting(bool enabled) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await printingService.togglePrinting(prefs, enabled);
  }

  Future<void> _setPaperSize(PaperSize size) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await printingService.setPaperSize(prefs, size);
  }

  Future<void> _setTextSize(int size) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await printingService.setTextSize(prefs, size);
  }

  Future<void> _setPrintingLanguage(String language) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await printingService.setPrintingLanguage(prefs, language);
  }

  Future<void> _testPrint(PrinterPurpose purpose) async {
    final l10n = AppLocalizations.of(context)!;
    final printerType = purpose == PrinterPurpose.receipt
      ? l10n.translate('receipt_printer')
      : l10n.translate('kds_printer');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${l10n.translate('test_print')}: $printerType'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('printer_management')),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
            iconSize: 32,
            onPressed: _isScanning ? _stopScan : _startScan,
            tooltip: _isScanning ? l10n.translate('stop_scan') : l10n.translate('scan_for_printers'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Business Info
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.store, size: 32),
                        const SizedBox(width: 16),
                        Text(
                          l10n.translate('business_info'),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Business Name
                    TextField(
                      controller: _businessNameController,
                      decoration: InputDecoration(
                        labelText: l10n.translate('business_name'),
                        hintText: l10n.translate('enter_business_name'),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.business),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.save),
                          tooltip: l10n.translate('save'),
                          onPressed: () {
                            _saveBusinessName(_businessNameController.text.trim());
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.translate('success')),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ),
                      style: const TextStyle(fontSize: 17),
                      onSubmitted: (value) => _saveBusinessName(value.trim()),
                    ),
                    const SizedBox(height: 20),
                    // Business Logo
                    Text(
                      l10n.translate('business_logo'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo preview
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!, width: 2),
                          ),
                          child: _logoBytes != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    _logoBytes!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
                                ),
                        ),
                        const SizedBox(width: 20),
                        // Logo actions
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _pickLogo,
                              icon: const Icon(Icons.upload_file),
                              label: Text(l10n.translate('select_logo')),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_logoBytes != null)
                              OutlinedButton.icon(
                                onPressed: _clearLogo,
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                label: Text(
                                  l10n.translate('remove_logo'),
                                  style: const TextStyle(color: Colors.red),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  textStyle: const TextStyle(fontSize: 16),
                                  side: const BorderSide(color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Scan controls
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.search, size: 32),
                        const SizedBox(width: 16),
                        Text(
                          l10n.translate('scan_for_printers'),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (_isScanning)
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isScanning ? null : _startScan,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                              textStyle: const TextStyle(fontSize: 18),
                            ),
                            icon: const Icon(Icons.search, size: 28),
                            label: Text(_isScanning ? l10n.translate('scanning') : l10n.translate('start_scan')),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isScanning ? _stopScan : null,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                              textStyle: const TextStyle(fontSize: 18),
                            ),
                            icon: const Icon(Icons.stop, size: 28),
                            label: Text(l10n.translate('stop_scan')),
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
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.settings, size: 32),
                        const SizedBox(width: 16),
                        Text(
                          l10n.translate('printer_settings'),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Master Printing Toggle
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      title: Text(
                        l10n.translate('enable_printing'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        l10n.translate('enable_printing_subtitle'),
                        style: const TextStyle(fontSize: 15),
                      ),
                      value: _config.printingEnabled,
                      onChanged: _togglePrinting,
                      activeTrackColor: Colors.green.withValues(alpha: 0.5),
                      inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                    ),
                    const Divider(height: 32),
                    // KDS Toggle
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      title: Text(
                        l10n.translate('enable_kds_printing'),
                        style: TextStyle(
                          fontSize: 18,
                          color: _config.printingEnabled ? null : Colors.grey,
                        ),
                      ),
                      subtitle: Text(
                        l10n.translate('print_kitchen_tickets_automatically'),
                        style: TextStyle(
                          fontSize: 15,
                          color: _config.printingEnabled ? null : Colors.grey,
                        ),
                      ),
                      value: _config.kdsEnabled,
                      onChanged: _config.printingEnabled ? _toggleKds : null,
                    ),
                    const Divider(height: 32),
                    // Paper Size
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      title: Text(
                        l10n.translate('paper_size'),
                        style: TextStyle(
                          fontSize: 18,
                          color: _config.printingEnabled ? null : Colors.grey,
                        ),
                      ),
                      subtitle: Text(
                        _config.paperSize == PaperSize.mm58 ? '58mm' : '80mm',
                        style: TextStyle(
                          fontSize: 15,
                          color: _config.printingEnabled ? null : Colors.grey,
                        ),
                      ),
                      trailing: SegmentedButton<PaperSize>(
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                        segments: const [
                          ButtonSegment(value: PaperSize.mm58, label: Text('58mm')),
                          ButtonSegment(value: PaperSize.mm80, label: Text('80mm')),
                        ],
                        selected: {_config.paperSize},
                        onSelectionChanged: _config.printingEnabled
                            ? (values) => _setPaperSize(values.first)
                            : null,
                      ),
                    ),
                    const Divider(height: 32),
                    // Text Size
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      title: Text(
                        l10n.translate('text_size'),
                        style: const TextStyle(fontSize: 18),
                      ),
                      subtitle: Text(
                        _config.textSize == 1
                          ? l10n.translate('normal')
                          : (_config.textSize == 2
                            ? l10n.translate('large')
                            : l10n.translate('extra_large')),
                        style: const TextStyle(fontSize: 15),
                      ),
                      trailing: SegmentedButton<int>(
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                        segments: [
                          ButtonSegment(value: 1, label: Text(l10n.translate('normal'))),
                          ButtonSegment(value: 2, label: Text(l10n.translate('large'))),
                          ButtonSegment(value: 3, label: Text(l10n.translate('extra'))),
                        ],
                        selected: {_config.textSize},
                        onSelectionChanged: (values) => _setTextSize(values.first),
                      ),
                    ),
                    const Divider(height: 32),
                    // Printing Language
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      title: Text(
                        l10n.translate('printing_language'),
                        style: const TextStyle(fontSize: 18),
                      ),
                      subtitle: Text(
                        l10n.translate('printing_language_subtitle'),
                        style: const TextStyle(fontSize: 15),
                      ),
                      trailing: SegmentedButton<String>(
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                        segments: [
                          ButtonSegment(value: 'en', label: Text(l10n.translate('english'))),
                          ButtonSegment(value: 'fr', label: Text(l10n.translate('french'))),
                        ],
                        selected: {_config.printingLanguage},
                        onSelectionChanged: (values) => _setPrintingLanguage(values.first),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Receipt Printer
            _buildPrinterSection(
              context: context,
              title: l10n.translate('receipt_printer'),
              subtitle: l10n.translate('for_customer_receipts'),
              icon: Icons.receipt_long,
              purpose: PrinterPurpose.receipt,
              configuredName: _config.receiptPrinterName,
              configuredType: _config.receiptConnectionType,
            ),

            const SizedBox(height: 20),

            // KDS Printer
            _buildPrinterSection(
              context: context,
              title: l10n.translate('kds_printer'),
              subtitle: l10n.translate('for_kitchen_display_tickets'),
              icon: Icons.restaurant,
              purpose: PrinterPurpose.kds,
              configuredName: _config.kdsPrinterName,
              configuredType: _config.kdsConnectionType,
              enabled: _config.kdsEnabled,
            ),

            const SizedBox(height: 24),

            // Available Printers
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.print, size: 32),
                        const SizedBox(width: 16),
                        Text(
                          l10n.translate('available_printers'),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          '${_printers.length} ${l10n.translate('found')}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_printers.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              const Icon(Icons.print_disabled, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                l10n.translate('no_printers_found'),
                                style: const TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.translate('click_start_scan'),
                                style: TextStyle(color: Colors.grey, fontSize: 15),
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
                        separatorBuilder: (_, __) => const Divider(height: 24),
                        itemBuilder: (context, index) {
                          final printer = _printers[index];
                          final isReceiptPrinter = printer.address == _config.receiptPrinterAddress;
                          final isKdsPrinter = printer.address == _config.kdsPrinterAddress;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            leading: Icon(
                              printer.connectionType == ConnectionType.USB
                                  ? Icons.usb
                                  : Icons.wifi,
                              size: 36,
                              color: (isReceiptPrinter || isKdsPrinter)
                                  ? Colors.green
                                  : null,
                            ),
                            title: Text(
                              printer.name ?? l10n.translate('unknown_printer'),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  '${l10n.translate('type')}: ${printer.connectionType?.name ?? l10n.translate('unknown')}',
                                  style: const TextStyle(fontSize: 15),
                                ),
                                if (isReceiptPrinter)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '✓ ${l10n.translate('receipt_printer')}',
                                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                  ),
                                if (isKdsPrinter)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '✓ ${l10n.translate('kds_printer')}',
                                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.more_vert, size: 28),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (context) => Container(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                          leading: const Icon(Icons.receipt_long, size: 32),
                                          title: Text(
                                            l10n.translate('set_as_receipt_printer'),
                                            style: const TextStyle(fontSize: 18),
                                          ),
                                          onTap: () {
                                            Navigator.pop(context);
                                            _setPrinter(printer, PrinterPurpose.receipt);
                                          },
                                        ),
                                        ListTile(
                                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                          enabled: _config.kdsEnabled,
                                          leading: Icon(
                                            Icons.restaurant,
                                            size: 32,
                                            color: _config.kdsEnabled ? null : Colors.grey,
                                          ),
                                          title: Text(
                                            l10n.translate('set_as_kds_printer'),
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: _config.kdsEnabled ? null : Colors.grey,
                                            ),
                                          ),
                                          onTap: _config.kdsEnabled
                                              ? () {
                                                  Navigator.pop(context);
                                                  _setPrinter(printer, PrinterPurpose.kds);
                                                }
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required PrinterPurpose purpose,
    required String? configuredName,
    required ConnectionType? configuredType,
    bool enabled = true,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isConfigured = configuredName != null;

    return Card(
      elevation: 3,
      color: enabled ? null : Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 32, color: enabled ? null : Colors.grey),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: enabled ? null : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 15,
                          color: enabled ? Colors.grey[600] : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!enabled)
                  Chip(
                    label: Text(l10n.translate('disabled')),
                    backgroundColor: Colors.grey,
                    labelStyle: const TextStyle(color: Colors.white, fontSize: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (isConfigured)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 2),
                ),
                child: Row(
                  children: [
                    Icon(
                      configuredType == ConnectionType.USB ? Icons.usb : Icons.wifi,
                      color: Colors.green,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            configuredName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            configuredType?.name ?? l10n.translate('unknown'),
                            style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.print, color: Colors.blue),
                      iconSize: 32,
                      padding: const EdgeInsets.all(12),
                      onPressed: enabled ? () => _testPrint(purpose) : null,
                      tooltip: l10n.translate('test_print'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      iconSize: 32,
                      padding: const EdgeInsets.all(12),
                      onPressed: enabled ? () => _clearPrinter(purpose) : null,
                      tooltip: l10n.translate('remove'),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.print_disabled, color: Colors.grey[400], size: 32),
                    const SizedBox(width: 12),
                    Text(
                      l10n.translate('no_printer_configured'),
                      style: TextStyle(color: Colors.grey[600], fontSize: 17),
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
