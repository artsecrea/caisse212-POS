// filepath: /home/artecrea/StudioProjects/posecrea/lib/presentation/widgets/printers_management_screen.dart
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
import 'package:uuid/uuid.dart';
import '../../providers/database_providers.dart';
import '../../providers/device_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/printing_service.dart';
import 'logo_editor_dialog.dart';
import '../../utils/app_localizations.dart';
import '../../utils/escpos_parser.dart';
import './adaptive_text_field.dart';
import 'settings_lock_dialog.dart';

class PrintersManagementScreen extends ConsumerStatefulWidget {
  const PrintersManagementScreen({super.key});

  @override
  ConsumerState<PrintersManagementScreen> createState() => _PrintersManagementScreenState();
}

class _PrintersManagementScreenState extends ConsumerState<PrintersManagementScreen> {
  List<Printer> _printers = [];
  bool _isScanning = false;
  PrinterConfig _config = const PrinterConfig();
  final TextEditingController _businessNameController = TextEditingController();
  // The rest of the letterhead. Read all over the printing code
  // (`business_address`, `business_phone`) but, until now, written by nothing —
  // so every ticket header printed the shop name alone. `business_ice` is the
  // Moroccan tax id the X / Z report carries.
  final TextEditingController _businessAddressController = TextEditingController();
  final TextEditingController _businessPhoneController = TextEditingController();
  final TextEditingController _businessIceController = TextEditingController();
  final TextEditingController _ticketHeaderController = TextEditingController();
  final TextEditingController _ticketFooterController = TextEditingController();
  Uint8List? _logoBytes;

  // Local mirrors of the printing service's per-station routing state.
  // Refreshed from the singleton after every save so the UI re-renders.
  List<NamedPrinter> _printerPool = [];
  // stationId -> printer ids. More than one id = the same station ticket is
  // printed on each of them.
  Map<int, List<String>> _stationAssignments = {};
  // What each station's ticket SHOWS — see [StationTicketRule].
  Map<int, StationTicketRule> _stationRules = {};
  bool _openingDrawer = false;

  /// Null while the gate is still being answered, true once it has been
  /// passed. The screen renders nothing until then — printer addresses, the
  /// business identity and the ticket text would otherwise be readable behind
  /// the pin prompt, which defeats the prompt.
  bool? _unlocked;

  @override
  void initState() {
    super.initState();
    // Gate first, load second. `/printers` is a named route, so the menu item
    // is not the only way in — the print-options dialog pushes it directly,
    // and anything else that learns the route name would too. Guarding here
    // covers every entrance at once.
    WidgetsBinding.instance.addPostFrameCallback((_) => _gate());
  }

  Future<void> _gate() async {
    final ok = await SettingsLockDialog.unlockPrinters(context, ref);
    if (!mounted) return;
    if (!ok) {
      // Bounce rather than show a locked shell: the caller pushed this route
      // and the user declined, so the natural place to be is where they were.
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _unlocked = true);
    _initializePrinting();
    _loadBusinessInfo();
    _loadTicketSettings();
    _loadStationRouting();
  }

  /// Deep copy — the service hands out unmodifiable inner lists.
  static Map<int, List<String>> _copyAssignments(Map<int, List<String>> src) =>
      {for (final e in src.entries) e.key: List<String>.of(e.value)};

  void _loadStationRouting() {
    final service = ref.read(printingServiceProvider);
    _stationRules = Map.of(service.stationRules);
    _printerPool = List.of(service.printerPool);
    _stationAssignments = _copyAssignments(service.stationAssignments);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessAddressController.dispose();
    _businessPhoneController.dispose();
    _businessIceController.dispose();
    _ticketHeaderController.dispose();
    _ticketFooterController.dispose();
    super.dispose();
  }

  void _loadBusinessInfo() {
    final prefs = ref.read(sharedPreferencesProvider);
    final savedName = prefs.getString('business_name') ?? '';
    _businessNameController.text = savedName;
    _businessAddressController.text = prefs.getString('business_address') ?? '';
    _businessPhoneController.text = prefs.getString('business_phone') ?? '';
    _businessIceController.text = prefs.getString('business_ice') ?? '';

    final base64Logo = prefs.getString('business_logo');
    if (base64Logo != null && base64Logo.isNotEmpty) {
      try {
        _logoBytes = base64Decode(base64Logo);
      } catch (e) {
        debugPrint('Error decoding saved logo: $e');
      }
    }
  }

  void _loadTicketSettings() {
    final settings = ref.read(settingsProvider);
    _ticketHeaderController.text = settings.ticketHeader;
    _ticketFooterController.text = settings.ticketFooter;
  }

  Future<void> _saveBusinessName(String name) async =>
      _saveIdentityField('business_name', name);

  /// Empty clears the key rather than storing '', because every reader treats
  /// null as "no such line" and an empty string as a line with nothing on it —
  /// which prints a blank row in the letterhead.
  Future<void> _saveIdentityField(String key, String value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  /// One letterhead row: type it, tap save (or press enter).
  Widget _identityField({
    required TextEditingController controller,
    required String prefsKey,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    final l10n = AppLocalizations.of(context)!;
    void save() {
      _saveIdentityField(prefsKey, controller.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('success')),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          icon: const Icon(Icons.save),
          tooltip: l10n.translate('save'),
          onPressed: save,
        ),
      ),
      style: const TextStyle(fontSize: 17),
      onSubmitted: (_) => save(),
    );
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
        // A crop belongs to the image it was drawn on. Carrying it over to
        // a newly picked logo would cut a corner off a picture nobody has
        // looked at yet.
        _updateConfig(_config.copyWith(
          logoCropLeft: 0.0,
          logoCropTop: 0.0,
          logoCropRight: 1.0,
          logoCropBottom: 1.0,
        ));
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

  /// Crop, size and position the printed logo.
  ///
  /// The picked bytes are left alone: the dialog returns a box in fractions
  /// of the source, which the printer applies when it rasterises. That is
  /// what lets the operator open this again and widen a crop they went too
  /// far with.
  Future<void> _editLogo() async {
    final bytes = _logoBytes;
    if (bytes == null) return;
    final result = await showDialog<LogoEditResult>(
      context: context,
      builder: (_) => LogoEditorDialog(imageBytes: bytes, config: _config),
    );
    if (result == null) return;
    _updateConfig(_config.copyWith(
      logoCropLeft: result.cropLeft,
      logoCropTop: result.cropTop,
      logoCropRight: result.cropRight,
      logoCropBottom: result.cropBottom,
      logoWidthPercent: result.widthPercent,
      logoAlign: result.align,
    ));
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

  /// Persist an updated [PrinterConfig] built via copyWith.
  Future<void> _updateConfig(PrinterConfig newConfig) async {
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await printingService.saveConfig(prefs, newConfig);
  }

  PrintRule _ruleForOutput(PrintOutput output) {
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

  PrinterConfig _configWithRule(PrintOutput output, PrintRule rule) {
    switch (output) {
      case PrintOutput.orderTicket:
        return _config.copyWith(orderTicketRule: rule);
      case PrintOutput.customerReceipt:
        return _config.copyWith(customerReceiptRule: rule);
      case PrintOutput.storeCopy:
        return _config.copyWith(storeCopyRule: rule);
      case PrintOutput.kds:
        return _config.copyWith(kdsRule: rule);
    }
  }

  Future<void> _testPrint(PrinterPurpose purpose) async {
    final l10n = AppLocalizations.of(context)!;
    final printingService = ref.read(printingServiceProvider);
    final success = await printingService.printTestPage(purpose);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? l10n.translate('test_print_success')
              : l10n.translate('test_print_failed')),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Test-print to a specific per-station pool printer.
  Future<void> _testPoolPrinter(NamedPrinter p) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await ref.read(printingServiceProvider).testPoolPrinter(p);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${p.label}: ${ok ? l10n.translate('test_print_success') : l10n.translate('test_print_failed')}'),
          backgroundColor: ok ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Compact, consistent section header: a small colored icon + bold title,
  /// with an optional one-line hint underneath explaining what the section
  /// does. Replaces the old bulky `Icon(32) + 20sp title` rows so the page
  /// reads as a structured settings page rather than a stack of big blocks.
  Widget _cardHeader(IconData icon, String title, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 22, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint,
              style: TextStyle(
                  fontSize: 13, height: 1.3, color: cs.onSurfaceVariant)),
        ],
      ],
    );
  }

  /// Small uppercase group label to cluster related cards visually.
  Widget _groupLabel(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: cs.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Nothing at all until the gate is answered — see [_unlocked].
    if (_unlocked != true) {
      return const Scaffold(body: SizedBox.shrink());
    }

    // Desktop layout: cap the content width and center it (horizontal padding
    // grows with the window) instead of stretching full-bleed like a phone.
    // `wide` gates the side-by-side printer cards.
    final screenW = MediaQuery.of(context).size.width;
    const maxContentWidth = 1160.0;
    final sidePad = ((screenW - maxContentWidth) / 2).clamp(20.0, 400.0);
    final wide = screenW >= 1000;

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
        padding: EdgeInsets.fromLTRB(sidePad, 20, sidePad, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _groupLabel(l10n.translate('grp_printers')),
            // Receipt + KDS printers — side by side on wide (desktop) screens.
            _printerSectionsLayout(context, l10n, wide),

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
                        Expanded(
                          child: _cardHeader(
                              Icons.search, l10n.translate('scan_for_printers'),
                              hint: l10n.translate('scan_hint')),
                        ),
                        if (_isScanning)
                          const SizedBox(
                            width: 24,
                            height: 24,
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showManualNetworkPrinterDialog,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                        icon: const Icon(Icons.add_link, size: 24),
                        label: Text(l10n.translate('add_network_printer_manually')),
                      ),
                    ),
                  ],
                ),
              ),
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
                        Expanded(
                          child: _cardHeader(
                              Icons.print, l10n.translate('available_printers'),
                              hint: l10n.translate('available_printers_hint')),
                        ),
                        Text(
                          '${_printers.length} ${l10n.translate('found')}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16),
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
                              Icon(Icons.print_disabled, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(height: 16),
                              Text(
                                l10n.translate('no_printers_found'),
                                style: const TextStyle(fontSize: 18),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.translate('click_start_scan'),
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15),
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
                                            color: _config.kdsEnabled ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                          title: Text(
                                            l10n.translate('set_as_kds_printer'),
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: _config.kdsEnabled ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          onTap: _config.kdsEnabled
                                              ? () {
                                                  Navigator.pop(context);
                                                  _setPrinter(printer, PrinterPurpose.kds);
                                                }
                                              : null,
                                        ),
                                        const Divider(height: 8),
                                        if (isReceiptPrinter)
                                          ListTile(
                                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                            leading: const Icon(Icons.print, size: 32, color: Colors.blue),
                                            title: Text(
                                              '${l10n.translate('test_print')} (${l10n.translate('receipt_printer')})',
                                              style: const TextStyle(fontSize: 18, color: Colors.blue),
                                            ),
                                            onTap: () {
                                              Navigator.pop(context);
                                              _testPrint(PrinterPurpose.receipt);
                                            },
                                          ),
                                        if (isKdsPrinter)
                                          ListTile(
                                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                            leading: const Icon(Icons.print, size: 32, color: Colors.blue),
                                            title: Text(
                                              '${l10n.translate('test_print')} (${l10n.translate('kds_printer')})',
                                              style: const TextStyle(fontSize: 18, color: Colors.blue),
                                            ),
                                            onTap: () {
                                              Navigator.pop(context);
                                              _testPrint(PrinterPurpose.kds);
                                            },
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

            const SizedBox(height: 24),

            // Station printer routing — pool + per-station assignments
            _buildStationPrintersCard(l10n),

            const SizedBox(height: 24),

            _groupLabel(l10n.translate('grp_receipt')),
            // Business Info
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardHeader(Icons.store, l10n.translate('business_info'),
                        hint: l10n.translate('business_info_hint')),
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
                    const SizedBox(height: 16),
                    _identityField(
                      controller: _businessAddressController,
                      prefsKey: 'business_address',
                      label: l10n.translate('business_address'),
                      icon: Icons.place_outlined,
                    ),
                    const SizedBox(height: 16),
                    _identityField(
                      controller: _businessPhoneController,
                      prefsKey: 'business_phone',
                      label: l10n.translate('business_phone'),
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    _identityField(
                      controller: _businessIceController,
                      prefsKey: 'business_ice',
                      label: l10n.translate('business_ice'),
                      icon: Icons.badge_outlined,
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
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 2),
                          ),
                          child: _logoBytes != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    _logoBytes!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.broken_image,
                                      size: 48,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Icon(Icons.image_not_supported, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                                onPressed: _editLogo,
                                icon: const Icon(Icons.crop),
                                label: Text(l10n.translate('edit_logo')),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 14),
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

            // Ticket Header & Footer
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardHeader(
                        Icons.receipt_long, l10n.translate('ticket_settings'),
                        hint: l10n.translate('ticket_settings_hint')),
                    const SizedBox(height: 20),
                    // Ticket Header
                    Text(
                      l10n.translate('ticket_header'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.translate('ticket_header_subtitle'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ticketHeaderController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: l10n.translate('ticket_header_hint'),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.article),
                      ),
                      style: const TextStyle(fontSize: 17),
                      onChanged: (value) {
                        ref.read(settingsProvider.notifier).setTicketHeader(value);
                      },
                    ),
                    const SizedBox(height: 20),
                    // Ticket Footer
                    Text(
                      l10n.translate('ticket_footer'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.translate('ticket_footer_subtitle'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ticketFooterController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: l10n.translate('ticket_footer_hint'),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.notes),
                      ),
                      style: const TextStyle(fontSize: 17),
                      onChanged: (value) {
                        ref.read(settingsProvider.notifier).setTicketFooter(value);
                      },
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
                    _cardHeader(Icons.settings, l10n.translate('printer_settings'),
                        hint: l10n.translate('printer_settings_hint')),
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
                          color: _config.printingEnabled ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      subtitle: Text(
                        l10n.translate('print_kitchen_tickets_automatically'),
                        style: TextStyle(
                          fontSize: 15,
                          color: _config.printingEnabled ? null : Theme.of(context).colorScheme.onSurfaceVariant,
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
                          color: _config.printingEnabled ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      subtitle: Text(
                        _config.paperSize == PaperSize.mm58 ? '58mm' : '80mm',
                        style: TextStyle(
                          fontSize: 15,
                          color: _config.printingEnabled ? null : Theme.of(context).colorScheme.onSurfaceVariant,
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
                          ButtonSegment(value: 'es', label: Text(l10n.translate('spanish'))),
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

            // Auto-print & copies
            _buildAutoPrintCard(l10n),

            const SizedBox(height: 24),

            // Per-output print rules
            _buildPrintRulesCard(l10n),

            const SizedBox(height: 24),

            // Cash drawer
            _buildCashDrawerCard(l10n),

            const SizedBox(height: 24),

            // Kitchen
            _groupLabel(l10n.translate('grp_kitchen')),
            _buildKitchenCard(l10n),

            const SizedBox(height: 24),

            // Per-ticket field visibility (customer / store / KDS)
            _buildTicketFieldsCard(l10n),

          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildAutoPrintCard(AppLocalizations l10n) {
    final copies = _config.customerCopies < 1 ? 1 : _config.customerCopies;
    return _sectionCard(
      icon: Icons.print,
      title: l10n.translate('auto_print_settings'),
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('auto_print_on_payment'),
              style: const TextStyle(fontSize: 18)),
          subtitle: Text(l10n.translate('auto_print_on_payment_subtitle'),
              style: const TextStyle(fontSize: 14)),
          value: _config.autoPrintOnPayment,
          onChanged: (v) => _updateConfig(_config.copyWith(autoPrintOnPayment: v)),
        ),
        const Divider(height: 24),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('customer_copies'),
              style: const TextStyle(fontSize: 18)),
          subtitle: Text(l10n.translate('customer_copies_subtitle'),
              style: const TextStyle(fontSize: 14)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: copies > 1
                    ? () => _updateConfig(
                        _config.copyWith(customerCopies: copies - 1))
                    : null,
              ),
              Text('$copies',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: copies < 5
                    ? () => _updateConfig(
                        _config.copyWith(customerCopies: copies + 1))
                    : null,
              ),
            ],
          ),
        ),
        const Divider(height: 24),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('reprint_watermark'),
              style: const TextStyle(fontSize: 18)),
          subtitle: Text(l10n.translate('reprint_watermark_subtitle'),
              style: const TextStyle(fontSize: 14)),
          value: _config.reprintWatermark,
          onChanged: (v) => _updateConfig(_config.copyWith(reprintWatermark: v)),
        ),
      ],
    );
  }

  Widget _buildPrintRulesCard(AppLocalizations l10n) {
    return _sectionCard(
      icon: Icons.rule,
      title: l10n.translate('print_rules'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(l10n.translate('print_rules_subtitle'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
        ),
        const SizedBox(height: 8),
        _buildRuleEditor(l10n, PrintOutput.orderTicket,
            l10n.translate('order_ticket'), Icons.receipt),
        _buildRuleEditor(l10n, PrintOutput.customerReceipt,
            l10n.translate('customer_receipt'), Icons.receipt_long),
        _buildRuleEditor(l10n, PrintOutput.storeCopy,
            l10n.translate('store_copy_rule'), Icons.store),
        _buildRuleEditor(l10n, PrintOutput.kds,
            l10n.translate('kitchen_ticket'), Icons.restaurant),
      ],
    );
  }

  Widget _buildRuleEditor(
      AppLocalizations l10n, PrintOutput output, String title, IconData icon) {
    final rule = _ruleForOutput(output);
    const orderTypes = ['DINE_IN', 'TAKE_AWAY', 'DELIVERY'];
    String typeLabel(String t) {
      switch (t) {
        case 'DINE_IN':
          return l10n.translate('dine_in');
        case 'TAKE_AWAY':
          return l10n.translate('take_away');
        default:
          return l10n.translate('delivery');
      }
    }

    // Source-channel filter (POS / WAITER / KIOSK / EXTERNAL). Keep the list
    // synced with `kAllOrderSources` in printing_service.dart — adding a new
    // source there without listing it here would silently hide it from the
    // rule UI even though the rule engine still applies to it.
    const sources = ['POS', 'WAITER', 'KIOSK', 'EXTERNAL'];
    String sourceLabel(String s) {
      switch (s) {
        case 'POS':
          return l10n.translate('source_pos');
        case 'WAITER':
          return l10n.translate('source_waiter');
        case 'KIOSK':
          return l10n.translate('source_kiosk');
        default:
          return l10n.translate('source_external');
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            secondary: Icon(icon),
            title: Text(title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            value: rule.enabled,
            onChanged: (v) => _updateConfig(
                _configWithRule(output, rule.copyWith(enabled: v))),
          ),
          if (rule.enabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(l10n.translate('order_types'),
                    style: TextStyle(
                        fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: orderTypes.map((t) {
                  final selected = rule.orderTypes.contains(t);
                  return FilterChip(
                    label: Text(typeLabel(t)),
                    selected: selected,
                    onSelected: (sel) {
                      final next = Set<String>.from(rule.orderTypes);
                      if (sel) {
                        next.add(t);
                      } else {
                        next.remove(t);
                      }
                      _updateConfig(_configWithRule(
                          output, rule.copyWith(orderTypes: next)));
                    },
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(l10n.translate('order_sources'),
                    style: TextStyle(
                        fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: sources.map((s) {
                  final selected = rule.sources.contains(s);
                  return FilterChip(
                    label: Text(sourceLabel(s)),
                    selected: selected,
                    onSelected: (sel) {
                      final next = Set<String>.from(rule.sources);
                      if (sel) {
                        next.add(s);
                      } else {
                        next.remove(s);
                      }
                      _updateConfig(_configWithRule(
                          output, rule.copyWith(sources: next)));
                    },
                  );
                }).toList(),
              ),
            ),
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              title: Text(l10n.translate('require_table'),
                  style: const TextStyle(fontSize: 15)),
              value: rule.requireTable,
              onChanged: (v) => _updateConfig(
                  _configWithRule(output, rule.copyWith(requireTable: v))),
            ),
          ],
        ],
      ),
    );
  }

  /// Kick the drawer open right now.
  ///
  /// Deliberately independent of the auto-open switch above it: that one is
  /// about what happens when a payment lands, this is the cashier needing the
  /// drawer open between sales. The drawer is often out of sight under the
  /// counter, so both outcomes get a message — a silent failure would just be
  /// pressed again.
  Future<void> _openDrawerNow() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _openingDrawer = true);
    final ok = await ref.read(printingServiceProvider).kickCashDrawer();
    if (!mounted) return;
    setState(() => _openingDrawer = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok
            ? l10n.translate('drawer_opened')
            : l10n.translate('drawer_open_failed')),
        backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
      ));
  }

  Widget _buildCashDrawerCard(AppLocalizations l10n) {
    return _sectionCard(
      icon: Icons.point_of_sale,
      title: l10n.translate('cash_drawer_settings'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.translate('open_drawer_now'),
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(l10n.translate('open_drawer_now_subtitle'),
                        style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _openingDrawer ? null : _openDrawerNow,
                icon: _openingDrawer
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.point_of_sale),
                label: Text(l10n.translate('open_drawer_now_action')),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 24),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('open_cash_drawer'),
              style: const TextStyle(fontSize: 18)),
          subtitle: Text(l10n.translate('open_cash_drawer_subtitle'),
              style: const TextStyle(fontSize: 14)),
          value: _config.cashDrawerKick,
          onChanged: (v) => _updateConfig(_config.copyWith(cashDrawerKick: v)),
        ),
        const Divider(height: 24),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('cash_payments_only'),
              style: TextStyle(
                  fontSize: 16,
                  color: _config.cashDrawerKick ? null : Theme.of(context).colorScheme.onSurfaceVariant)),
          value: _config.cashDrawerCashOnly,
          onChanged: _config.cashDrawerKick
              ? (v) => _updateConfig(_config.copyWith(cashDrawerCashOnly: v))
              : null,
        ),
      ],
    );
  }

  /// Immutably set one ticket-field toggle and persist the config.
  void _setTicketField(String type, String field, bool value) {
    final map = <String, Map<String, bool>>{
      for (final e in _config.ticketFields.entries)
        e.key: Map<String, bool>.from(e.value),
    };
    (map[type] ??= <String, bool>{})[field] = value;
    _updateConfig(_config.copyWith(ticketFields: map));
  }

  /// Pin one ticket field to a text size, or drop it back to the global size.
  ///
  /// Tier 0 removes the entry rather than storing a zero, so "follows the
  /// global size" stays the absence of a choice — a config that has never been
  /// touched and one that was set back to Default are the same thing.
  void _setTicketFieldSize(String type, String field, int tier) {
    final map = <String, Map<String, int>>{
      for (final e in _config.ticketFieldSizes.entries)
        e.key: Map<String, int>.from(e.value),
    };
    final inner = map[type] ??= <String, int>{};
    if (tier <= 0) {
      inner.remove(field);
    } else {
      inner[field] = tier;
    }
    _updateConfig(_config.copyWith(ticketFieldSizes: map));
  }

  /// Persist a new row order for one band, leaving the other bands alone.
  ///
  /// Stored flattened, every band in print order, because that is the shape
  /// [PrinterConfig.orderedFields] reads back.
  void _setTicketFieldOrder(String type, String zone, List<String> order) {
    final flat = <String>[
      for (final z in PrinterConfig.fieldZones)
        ...(z == zone ? order : _config.orderedFields(type, z)),
    ];
    final map = <String, List<String>>{
      for (final e in _config.ticketFieldOrder.entries)
        e.key: List<String>.from(e.value),
    };
    map[type] = flat;
    _updateConfig(_config.copyWith(ticketFieldOrder: map));
  }

  /// What each band is called in the settings UI. Matching the labels to
  /// the rules printed on the ticket is what makes it obvious why a row
  /// cannot be dragged out of its band.
  static const _ticketZoneLabels = {
    'header': 'Letterhead',
    'info': 'Order info',
    'note': 'Order note',
    'totals': 'Totals',
    'trailer': 'Barcode',
  };

  static const _ticketFieldLabels = {
    'storeName': 'Store name',
    'storeAddress': 'Store address',
    'storePhone': 'Store phone',
    'stationName': 'Station name',
    'orderCode': 'Order code',
    'date': 'Date / time',
    'time': 'Time',
    'cashier': 'Cashier',
    'waiter': 'Waiter',
    'orderType': 'Order type',
    'table': 'Table',
    'persons': 'Persons',
    'customerName': 'Customer name',
    'customerPhone': 'Customer phone',
    'deliveryAddress': 'Delivery address',
    'paymentMethod': 'Payment method',
    'items': 'Product lines',
    'subtotal': 'Subtotal',
    'discount': 'Discount',
    'tva': 'VAT / TVA amount',
    'total': 'Total',
    'amountGiven': 'Cash given by customer',
    'change': 'Change returned',
    'orderNote': 'Order note',
    'barcode': 'Barcode',
  };

  // The extras only print when a tender was actually keyed, which is worth
  // saying next to the switch — otherwise "I turned it on and nothing
  // changed" on a card payment reads as a bug.
  static const _ticketFieldHints = {
    'waiter': 'Only prints when a waiter is attached to the order',
    'tva': 'Prints the VAT already included in the total',
    'amountGiven': 'Only when the cashier keyed the amount received',
    'change': 'Only when the cashier keyed the amount received',
    'items': 'Product name, quantity, price and any components',
  };

  /// The size picker that sits at the end of every ticket-content row.
  Widget _fieldSizePicker(String type, String field, {required bool enabled}) {
    final theme = Theme.of(context);
    return Container(
      width: 124,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: DropdownButton<int>(
        value: _config.fieldSize(type, field),
        isDense: true,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        style: TextStyle(
          fontSize: 14,
          color: enabled ? theme.colorScheme.onSurface : theme.disabledColor,
        ),
        items: [
          const DropdownMenuItem(value: 0, child: Text('Default')),
          for (final e in PrinterConfig.textTiers.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged:
            enabled ? (v) => _setTicketFieldSize(type, field, v ?? 0) : null,
      ),
    );
  }

  /// One row: the switch (when the field can be turned off), its label, and
  /// its size. Structural parts of the ticket — the store name, the product
  /// lines, the total — get the size input without a switch, because a receipt
  /// with no total is not a receipt.
  Widget _ticketFieldRow(String type, String field,
      {required bool toggleable, int? dragIndex}) {
    final on = !toggleable ||
        (_config.ticketFields[type]?[field] ??
            PrinterConfig.fieldDefaultOn(field, type));
    final hint = _ticketFieldHints[field];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          if (dragIndex != null) ...[
            ReorderableDragStartListener(
              index: dragIndex,
              child: Icon(Icons.drag_handle, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 56,
            child: toggleable
                ? Switch(
                    value: on,
                    onChanged: (v) => _setTicketField(type, field, v),
                  )
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_ticketFieldLabels[field] ?? field,
                    style: TextStyle(
                        fontSize: 16,
                        color: on ? null : Theme.of(context).disabledColor)),
                if (hint != null)
                  Text(hint,
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _fieldSizePicker(type, field, enabled: on),
        ],
      ),
    );
  }

  /// One band of a ticket: its label, then its rows, draggable into any
  /// order within the band.
  ///
  /// Bands, rather than one list per ticket, because the ticket itself has
  /// bands: the letterhead is above the header rule, the totals are below
  /// the items. A row dragged out of its band would not print in a new
  /// place, so it cannot leave.
  List<Widget> _ticketZoneSection(String type, String zone) {
    final fields = _config.orderedFields(type, zone);
    if (fields.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          (_ticketZoneLabels[zone] ?? zone).toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: fields.length,
        onReorder: (oldIndex, newIndex) {
          final next = List<String>.from(fields);
          if (newIndex > oldIndex) newIndex--;
          next.insert(newIndex, next.removeAt(oldIndex));
          _setTicketFieldOrder(type, zone, next);
        },
        itemBuilder: (context, index) => KeyedSubtree(
          key: ValueKey('$type.$zone.${fields[index]}'),
          child: _ticketFieldRow(type, fields[index],
              toggleable: true, dragIndex: fields.length > 1 ? index : null),
        ),
      ),
    ];
  }

  Widget _buildTicketFieldsCard(AppLocalizations l10n) {
    const sectionTitles = {
      'order': 'Order ticket',
      'customer': 'Customer receipt',
      'store': 'Store copy',
      'kds': 'Kitchen (KDS) ticket',
    };
    return _sectionCard(
      icon: Icons.receipt_long,
      title: l10n.translate('ticket_content'),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(l10n.translate('ticket_content_subtitle'),
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        for (final type in const ['order', 'customer', 'store', 'kds'])
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(sectionTitles[type]!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              for (final zone in PrinterConfig.fieldZones)
                ..._ticketZoneSection(type, zone),
              const Divider(height: 16, indent: 16, endIndent: 16),
              for (final field in PrinterConfig.sizeOnlyCatalog[type]!)
                _ticketFieldRow(type, field, toggleable: false),
            ],
          ),
      ],
    );
  }

  Widget _buildKitchenCard(AppLocalizations l10n) {
    // Whole-order mode overrides every station control below it, so those are
    // greyed rather than removed — the operator can see what they turned off.
    final simple = _config.kdsFullOrderMode;
    return _sectionCard(
      icon: Icons.restaurant_menu,
      title: l10n.translate('kitchen_settings'),
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('kds_full_order'),
              style: const TextStyle(fontSize: 18)),
          subtitle: Text(l10n.translate('kds_full_order_subtitle'),
              style: const TextStyle(fontSize: 14)),
          value: simple,
          onChanged: (v) =>
              _updateConfig(_config.copyWith(kdsFullOrderMode: v)),
        ),
        if (simple)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.translate('kds_copies'),
                          style: const TextStyle(fontSize: 17)),
                      const SizedBox(height: 4),
                      Text(l10n.translate('kds_copies_subtitle'),
                          style: TextStyle(
                              fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // A stepper rather than a text field: the number is one digit
                // and the cashier is standing up.
                IconButton.filledTonal(
                  iconSize: 26,
                  onPressed: _config.kdsCopies > 1
                      ? () => _updateConfig(_config.copyWith(
                          kdsCopies: _config.kdsCopies - 1))
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${_config.kdsCopies}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton.filledTonal(
                  iconSize: 26,
                  onPressed: _config.kdsCopies < 9
                      ? () => _updateConfig(_config.copyWith(
                          kdsCopies: _config.kdsCopies + 1))
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        const Divider(height: 24),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('print_linked_components'),
              style: const TextStyle(fontSize: 18)),
          subtitle: Text(l10n.translate('print_linked_components_subtitle'),
              style: const TextStyle(fontSize: 14)),
          value: _config.printLinkedComponents,
          onChanged: (v) =>
              _updateConfig(_config.copyWith(printLinkedComponents: v)),
        ),
        if (_config.printLinkedComponents)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.translate('linked_component_label'),
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                SegmentedButton<LinkedComponentLabel>(
                  segments: [
                    ButtonSegment(
                      value: LinkedComponentLabel.component,
                      label: Text(l10n.translate('label_component_name')),
                      icon: const Icon(Icons.tune),
                    ),
                    ButtonSegment(
                      value: LinkedComponentLabel.product,
                      label: Text(l10n.translate('label_product_name')),
                      icon: const Icon(Icons.inventory_2_outlined),
                    ),
                  ],
                  selected: {_config.linkedComponentLabel},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => _updateConfig(
                    _config.copyWith(linkedComponentLabel: selection.first),
                  ),
                ),
                const SizedBox(height: 6),
                Text(l10n.translate('linked_component_label_hint'),
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        const Divider(height: 24),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('split_by_station'),
              style: TextStyle(
                  fontSize: 18, color: simple ? Theme.of(context).colorScheme.onSurfaceVariant : null)),
          subtitle: Text(l10n.translate('split_by_station_subtitle'),
              style: const TextStyle(fontSize: 14)),
          value: _config.splitKdsByStation,
          onChanged: simple
              ? null
              : (v) => _updateConfig(_config.copyWith(splitKdsByStation: v)),
        ),
        // Consolidated-job toggle. Only meaningful when split-by-station
        // is on (otherwise everything is already one job).
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('consolidate_kds_job'),
              style: TextStyle(
                  fontSize: 18,
                  color: _config.splitKdsByStation ? null : Theme.of(context).colorScheme.onSurfaceVariant)),
          subtitle: Text(
              l10n.translate('consolidate_kds_job_subtitle'),
              style: TextStyle(
                  fontSize: 14,
                  color: _config.splitKdsByStation ? null : Theme.of(context).colorScheme.onSurfaceVariant)),
          value: _config.consolidateKdsJob,
          onChanged: _config.splitKdsByStation
              ? (v) => _updateConfig(_config.copyWith(consolidateKdsJob: v))
              : null,
        ),
        // Whether products with no station assignment print on the KDS.
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('print_unassigned_kds'),
              style: const TextStyle(fontSize: 18)),
          subtitle: Text(l10n.translate('print_unassigned_kds_subtitle'),
              style: const TextStyle(fontSize: 14)),
          value: _config.printKdsUnassigned,
          onChanged: (v) =>
              _updateConfig(_config.copyWith(printKdsUnassigned: v)),
        ),
        const Divider(height: 24),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('default_print_mode'),
              style: const TextStyle(fontSize: 18)),
          trailing: SegmentedButton<KdsPrintMode>(
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              textStyle: const TextStyle(fontSize: 14),
            ),
            segments: [
              ButtonSegment(
                  value: KdsPrintMode.full,
                  label: Text(l10n.translate('full_order'))),
              ButtonSegment(
                  value: KdsPrintMode.modificationsOnly,
                  label: Text(l10n.translate('new_items_only'))),
            ],
            selected: {_config.defaultKdsMode},
            onSelectionChanged: (values) =>
                _updateConfig(_config.copyWith(defaultKdsMode: values.first)),
          ),
        ),

        // ── Courier code (Glovo / Kooul) ─────────────────────────────────
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(Icons.qr_code_2,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(l10n.translate('courier_code_group'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Text(
            l10n.translate('courier_code_group_subtitle'),
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('courier_code_mode'),
              style: const TextStyle(fontSize: 18)),
          trailing: SegmentedButton<CourierCodeMode>(
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              textStyle: const TextStyle(fontSize: 14),
            ),
            segments: [
              ButtonSegment(
                  value: CourierCodeMode.sameTicket,
                  label: Text(l10n.translate('courier_mode_same'))),
              ButtonSegment(
                  value: CourierCodeMode.separateTicket,
                  label: Text(l10n.translate('courier_mode_separate'))),
              ButtonSegment(
                  value: CourierCodeMode.off,
                  label: Text(l10n.translate('off'))),
            ],
            selected: {_config.courierCodeMode},
            onSelectionChanged: (values) =>
                _updateConfig(_config.copyWith(courierCodeMode: values.first)),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(l10n.translate('courier_code_symbology'),
              style: const TextStyle(fontSize: 18)),
          // Pointless while nothing is printed — grey it out rather than hide
          // it, so the option does not appear to vanish.
          enabled: _config.courierCodeMode != CourierCodeMode.off,
          trailing: SegmentedButton<CourierCodeSymbology>(
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              textStyle: const TextStyle(fontSize: 14),
            ),
            segments: const [
              ButtonSegment(
                  value: CourierCodeSymbology.qr, label: Text('QR')),
              ButtonSegment(
                  value: CourierCodeSymbology.code128,
                  label: Text('Code128')),
              ButtonSegment(
                  value: CourierCodeSymbology.text, label: Text('Texte')),
            ],
            selected: {_config.courierCodeSymbology},
            onSelectionChanged: _config.courierCodeMode == CourierCodeMode.off
                ? null
                : (values) => _updateConfig(
                    _config.copyWith(courierCodeSymbology: values.first)),
          ),
        ),
      ],
    );
  }

  /// Receipt + KDS printer cards: stacked on narrow screens, side by side on
  /// wide (desktop) ones so the horizontal space isn't wasted.
  Widget _printerSectionsLayout(
      BuildContext context, AppLocalizations l10n, bool wide) {
    final receipt = _buildPrinterSection(
      context: context,
      title: l10n.translate('receipt_printer'),
      subtitle: l10n.translate('for_customer_receipts'),
      icon: Icons.receipt_long,
      purpose: PrinterPurpose.receipt,
      configuredName: _config.receiptPrinterName,
      configuredType: _config.receiptConnectionType,
    );
    final kds = _buildPrinterSection(
      context: context,
      title: l10n.translate('kds_printer'),
      subtitle: l10n.translate('for_kitchen_display_tickets'),
      icon: Icons.restaurant,
      purpose: PrinterPurpose.kds,
      configuredName: _config.kdsPrinterName,
      configuredType: _config.kdsConnectionType,
      enabled: _config.kdsEnabled,
    );
    if (!wide) {
      return Column(
        children: [receipt, const SizedBox(height: 20), kds],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: receipt),
        const SizedBox(width: 20),
        Expanded(child: kds),
      ],
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
      color: enabled ? null : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 32, color: enabled ? null : Theme.of(context).colorScheme.onSurfaceVariant),
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
                          color: enabled ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!enabled)
                  Chip(
                    label: Text(l10n.translate('disabled')),
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    labelStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 15),
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
                            style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                      icon: const Icon(Icons.code, color: Colors.deepPurple),
                      iconSize: 32,
                      padding: const EdgeInsets.all(12),
                      onPressed: enabled ? () => _showRawEscPosDialog(purpose) : null,
                      tooltip: l10n.translate('send_raw_escpos'),
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
                    Icon(Icons.print_disabled, color: Theme.of(context).colorScheme.outline, size: 32),
                    const SizedBox(width: 12),
                    Text(
                      l10n.translate('no_printer_configured'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 17),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Manual network printer entry ──────────────────────────────────────────

  Future<void> _showManualNetworkPrinterDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: l10n.translate('network_printer'));
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '9100');
    PrinterPurpose target = PrinterPurpose.receipt;
    String? errorMessage;
    bool testing = false;
    bool saving = false;

    final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            String? validate() {
              if (!ipRegex.hasMatch(ipCtrl.text.trim())) {
                return l10n.translate('invalid_ip');
              }
              final port = int.tryParse(portCtrl.text.trim());
              if (port == null || port <= 0 || port > 65535) {
                return l10n.translate('port');
              }
              return null;
            }

            String fullAddress() =>
                '${ipCtrl.text.trim()}:${portCtrl.text.trim()}';

            Future<void> doTest() async {
              final v = validate();
              if (v != null) {
                setLocal(() => errorMessage = v);
                return;
              }
              setLocal(() {
                testing = true;
                errorMessage = null;
              });
              final ok = await ref
                  .read(printingServiceProvider)
                  .testNetworkReachable(fullAddress());
              setLocal(() => testing = false);
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                backgroundColor: ok ? Colors.green : Colors.red,
                content: Text(ok
                    ? l10n.translate('connection_ok')
                    : l10n.translate('connection_failed')),
              ));
            }

            Future<void> doSave() async {
              final v = validate();
              if (v != null) {
                setLocal(() => errorMessage = v);
                return;
              }
              setLocal(() => saving = true);
              final manual = Printer(
                name: nameCtrl.text.trim().isEmpty
                    ? l10n.translate('network_printer')
                    : nameCtrl.text.trim(),
                address: fullAddress(),
                connectionType: ConnectionType.NETWORK,
                isConnected: false,
              );
              await _setPrinter(manual, target);
              if (ctx.mounted) Navigator.of(ctx).pop();
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.add_link, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.translate('add_network_printer_manually')),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdaptiveKeyboardTextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.translate('network_printer'),
                          prefixIcon: const Icon(Icons.label_outline),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AdaptiveKeyboardTextField(
                        controller: ipCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.translate('ip_address'),
                          prefixIcon: const Icon(Icons.lan_outlined),
                          hintText: '192.168.1.50',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      AdaptiveKeyboardTextField(
                        controller: portCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.translate('port'),
                          prefixIcon: const Icon(Icons.numbers),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(l10n.translate('assign_to'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      RadioListTile<PrinterPurpose>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.translate('receipt_printer')),
                        value: PrinterPurpose.receipt,
                        groupValue: target,
                        onChanged: (v) =>
                            setLocal(() => target = v ?? target),
                      ),
                      RadioListTile<PrinterPurpose>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.translate('kds_printer')),
                        value: PrinterPurpose.kds,
                        groupValue: target,
                        onChanged: (v) =>
                            setLocal(() => target = v ?? target),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(errorMessage!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: (saving || testing)
                      ? null
                      : () => Navigator.of(ctx).pop(),
                  child: Text(l10n.translate('cancel')),
                ),
                OutlinedButton.icon(
                  onPressed: (saving || testing) ? null : doTest,
                  icon: testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: Text(l10n.translate('test_connection')),
                ),
                ElevatedButton(
                  onPressed: (saving || testing) ? null : doSave,
                  child: Text(l10n.translate('save')),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    ipCtrl.dispose();
    portCtrl.dispose();
  }

  // ── Raw ESC/POS dialog ────────────────────────────────────────────────────

  static const Map<String, String> _kEscPosQuickCommands = {
    'cmd_init': '1B 40',
    'cmd_cut': '1D 56 41 03',
    'cmd_drawer_kick': '1B 70 00 19 FA',
    'cmd_feed_lines': '1B 64 03',
    'cmd_beep': '1B 42 03 03',
  };

  Future<void> _showRawEscPosDialog(PrinterPurpose purpose) async {
    final l10n = AppLocalizations.of(context)!;
    final inputCtrl = TextEditingController();
    bool sending = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> doSend() async {
              final bytes = parseEscPosInput(inputCtrl.text);
              if (bytes.isEmpty) return;
              setLocal(() => sending = true);
              final ok = await ref
                  .read(printingServiceProvider)
                  .sendRawBytes(purpose, bytes);
              setLocal(() => sending = false);
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                backgroundColor: ok ? Colors.green : Colors.red,
                content: Text(ok
                    ? l10n.translate('raw_escpos_sent')
                    : l10n.translate('raw_escpos_send_failed')),
              ));
              if (ok && ctx.mounted) Navigator.of(ctx).pop();
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.code, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.translate('send_raw_escpos'))),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.translate('raw_escpos_hint'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _kEscPosQuickCommands.entries
                          .map((e) => ActionChip(
                                label: Text(l10n.translate(e.key)),
                                onPressed: () => setLocal(() {
                                  inputCtrl.text = e.value;
                                  inputCtrl.selection =
                                      TextSelection.collapsed(
                                          offset: e.value.length);
                                }),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    AdaptiveKeyboardTextField(
                      controller: inputCtrl,
                      maxLines: 5,
                      minLines: 5,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '1B 40 …',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      sending ? null : () => Navigator.of(ctx).pop(),
                  child: Text(l10n.translate('cancel')),
                ),
                ElevatedButton.icon(
                  onPressed: sending ? null : doSend,
                  icon: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(l10n.translate('send_raw_escpos')),
                ),
              ],
            );
          },
        );
      },
    );

    inputCtrl.dispose();
  }

  // ── Station printer routing ────────────────────────────────────────────────

  Future<void> _persistPool(List<NamedPrinter> updated) async {
    final service = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await service.savePrinterPool(prefs, updated);
    if (!mounted) return;
    setState(() {
      _printerPool = List.of(service.printerPool);
      // savePrinterPool may have pruned stale assignments — re-read so the
      // pickers stay in sync.
      _stationAssignments = _copyAssignments(service.stationAssignments);
    });
  }

  Future<void> _persistAssignments(Map<int, List<String>> updated) async {
    final service = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await service.saveStationAssignments(prefs, updated);
    if (!mounted) return;
    setState(() {
      _stationAssignments = _copyAssignments(service.stationAssignments);
    });
  }

  Future<void> _openPrinterDialog({NamedPrinter? existing}) async {
    final result = await showDialog<NamedPrinter>(
      context: context,
      builder: (ctx) => _NamedPrinterDialog(existing: existing),
    );
    if (result == null) return;
    final updated = List<NamedPrinter>.from(_printerPool);
    final idx = updated.indexWhere((x) => x.id == result.id);
    if (idx >= 0) {
      updated[idx] = result;
    } else {
      updated.add(result);
    }
    await _persistPool(updated);
  }

  Future<void> _confirmAndDeletePoolPrinter(NamedPrinter p) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('delete')),
        content: Text('${l10n.translate('delete')}? ${p.label}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.translate('delete')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _persistPool(_printerPool.where((x) => x.id != p.id).toList());
    }
  }

  Widget _buildStationPrintersCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final stationsAsync = ref.watch(stationListProvider);

    return _sectionCard(
      icon: Icons.alt_route,
      title: l10n.translate('station_printers'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            l10n.translate('station_printers_subtitle'),
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 15,
            ),
          ),
        ),
        if (!_config.splitKdsByStation) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.translate('split_disabled_warning'),
                    style: TextStyle(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        // ── Pool ──
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.translate('printer_pool'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add),
              label: Text(l10n.translate('add_printer')),
              onPressed: () => _openPrinterDialog(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_printerPool.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Text(
              '—',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          ..._printerPool.map((p) => _buildPoolRow(p, l10n, theme)),
        const Divider(height: 32),
        // ── Assignments ──
        Text(
          l10n.translate('assign_printers_to_stations'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.translate('station_printers_hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        stationsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error: $e'),
          data: (stations) {
            if ((stations as List).isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Text(
                  '—',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            }
            return Column(
              children: [
                for (final station in stations)
                  _buildAssignmentRow(station, l10n, theme),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPoolRow(NamedPrinter p, AppLocalizations l10n, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Icon(
            p.connectionType == ConnectionType.NETWORK
                ? Icons.lan_outlined
                : Icons.usb,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.connectionType.name} · ${p.address}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: l10n.translate('test_print'),
            onPressed: () => _testPoolPrinter(p),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.translate('edit'),
            onPressed: () => _openPrinterDialog(existing: p),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.translate('delete'),
            onPressed: () => _confirmAndDeletePoolPrinter(p),
          ),
        ],
      ),
    );
  }

  // Drift `Station` row is dynamic-typed here to avoid pulling in the
  // app_database import — `id` and `name` are the only fields we touch.
  Widget _buildAssignmentRow(
    dynamic station,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final int stationId = station.id as int;
    final String stationName = station.name as String;
    final selected = _stationAssignments[stationId] ?? const <String>[];
    final silenced = selected.contains(kNoPrinterAssignment);
    // A pool printer can be deleted while an assignment still names it, so
    // only the ids that still resolve are worth showing.
    final labels = <String>[
      for (final id in selected)
        for (final p in _printerPool)
          if (p.id == id) (p.label.isNotEmpty ? p.label : p.address),
    ];

    final String summary;
    final IconData icon;
    final Color? color;
    if (silenced) {
      summary = l10n.translate('no_printer_kds_only');
      icon = Icons.print_disabled;
      color = Colors.redAccent;
    } else if (labels.isEmpty) {
      summary = l10n.translate('use_default_kds_printer');
      icon = Icons.print_outlined;
      color = theme.colorScheme.onSurfaceVariant;
    } else {
      // More than one printer = the same station ticket on each of them.
      summary = labels.join('  +  ');
      icon = labels.length > 1 ? Icons.layers_outlined : Icons.print_outlined;
      color = theme.colorScheme.primary;
    }

    final rule = _stationRules[stationId] ?? const StationTicketRule();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              stationName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openStationPrinterPicker(stationId, stationName),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color),
                      ),
                    ),
                    if (labels.length > 1)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 4),
                        child: Text(
                          '\u00d7${labels.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
          // What this station's ticket shows. Hidden for a silenced station —
          // it prints nothing at all, so there is nothing to scope.
          if (!silenced)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<StationTicketScope>(
                    value: rule.scope,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    style: theme.textTheme.bodySmall,
                    items: [
                      for (final s in StationTicketScope.values)
                        DropdownMenuItem(
                          value: s,
                          child: Text(l10n.translate(_scopeKey(s))),
                        ),
                    ],
                    onChanged: (v) => _setStationRule(
                        stationId, StationTicketRule(
                            scope: v ?? rule.scope, private: rule.private)),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _setStationRule(
                        stationId,
                        StationTicketRule(
                            scope: rule.scope, private: !rule.private)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            rule.private
                                ? Icons.lock_outline
                                : Icons.lock_open_outlined,
                            size: 15,
                            color: rule.private
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.translate('station_private'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: rule.private
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: rule.private
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Label key for a scope, kept out of the widget so the three strings sit
  /// together and cannot drift from the enum.
  String _scopeKey(StationTicketScope scope) {
    switch (scope) {
      case StationTicketScope.ownItems:
        return 'scope_own_items';
      case StationTicketScope.wholeOrderWhenUsed:
        return 'scope_whole_when_used';
      case StationTicketScope.wholeOrderAlways:
        return 'scope_whole_always';
    }
  }

  Future<void> _setStationRule(int stationId, StationTicketRule rule) async {
    final updated = Map<int, StationTicketRule>.of(_stationRules);
    updated[stationId] = rule;
    await ref
        .read(printingServiceProvider)
        .saveStationRules(ref.read(sharedPreferencesProvider), updated);
    if (!mounted) return;
    setState(() => _stationRules =
        Map.of(ref.read(printingServiceProvider).stationRules));
  }

  /// Multi-select printer picker for one station: the default KDS printer,
  /// "don't print at all", or any number of pool printers — every printer
  /// ticked gets its own copy of this station's ticket. The two exclusive
  /// options clear the checkboxes, and ticking a printer clears them.
  Future<void> _openStationPrinterPicker(
    int stationId,
    String stationName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    var current = List<String>.of(_stationAssignments[stationId] ?? const []);

    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final silenced = current.contains(kNoPrinterAssignment);
          final chosen =
              current.where((id) => id != kNoPrinterAssignment).toList();
          return AlertDialog(
            title: Text('$stationName \u2014 ${l10n.translate('printers')}'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: Icon(chosen.isEmpty && !silenced
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
                    title: Text(l10n.translate('use_default_kds_printer')),
                    onTap: () => setLocal(() => current = []),
                  ),
                  ListTile(
                    leading: Icon(
                      silenced
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: silenced ? Colors.redAccent : null,
                    ),
                    title: Text(l10n.translate('no_printer_kds_only')),
                    onTap: () =>
                        setLocal(() => current = [kNoPrinterAssignment]),
                  ),
                  const Divider(),
                  if (_printerPool.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.translate('no_printers_found'),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final p in _printerPool)
                    CheckboxListTile(
                      value: chosen.contains(p.id),
                      title: Text(p.label.isNotEmpty ? p.label : p.address),
                      subtitle: Text(
                          '${p.connectionType.name} \u00b7 ${p.address}'),
                      onChanged: (v) => setLocal(() {
                        // Rebuilt from `chosen`, which already excludes the
                        // sentinel — ticking a printer un-silences the station.
                        final next = List<String>.of(chosen);
                        if (v == true) {
                          if (!next.contains(p.id)) next.add(p.id);
                        } else {
                          next.remove(p.id);
                        }
                        current = next;
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.translate('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, current),
                child: Text(l10n.translate('save')),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return; // cancelled
    final updated = _copyAssignments(_stationAssignments);
    if (result.isEmpty) {
      updated.remove(stationId);
    } else {
      updated[stationId] = result;
    }
    await _persistAssignments(updated);
  }
}

/// Picker that reuses the same scan-stream + discovered-printer list that the
/// enclosing [PrintersManagementScreen] uses (via
/// [PrintingService.printersStream] / [PrintingService.availablePrinters] /
/// [PrintingService.startScan]), plus a manual-network fallback. Returns the
/// chosen [NamedPrinter] via `Navigator.pop`, or `null` on cancel.
class _NamedPrinterDialog extends ConsumerStatefulWidget {
  final NamedPrinter? existing;
  const _NamedPrinterDialog({this.existing});

  @override
  ConsumerState<_NamedPrinterDialog> createState() =>
      _NamedPrinterDialogState();
}

class _NamedPrinterDialogState extends ConsumerState<_NamedPrinterDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _nameCtrl;
  late ConnectionType _manualType;
  final _formKey = GlobalKey<FormState>();

  List<Printer> _discovered = const [];
  bool _isScanning = false;
  Printer? _selectedDiscovered;
  bool _manualMode = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    _addressCtrl = TextEditingController(text: e?.address ?? '');
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _manualType = e?.connectionType ?? ConnectionType.NETWORK;
    _manualMode = e != null;

    final service = ref.read(printingServiceProvider);
    _discovered = service.availablePrinters;
    _isScanning = service.isScanning;
    service.printersStream.listen((list) {
      if (mounted) setState(() => _discovered = list);
    });
    service.scanningStream.listen((s) {
      if (mounted) setState(() => _isScanning = s);
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    await ref.read(printingServiceProvider).startScan();
  }

  Future<void> _stopScan() async {
    await ref.read(printingServiceProvider).stopScan();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? l10n.translate('add_printer')
            : l10n.translate('edit'),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _labelCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.translate('printer_label'),
                    prefixIcon: const Icon(Icons.label_outline),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                if (!_manualMode) ...[
                  _buildScanControls(l10n),
                  const SizedBox(height: 8),
                  _buildDiscoveredList(l10n, theme),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _manualMode = true;
                      _selectedDiscovered = null;
                    }),
                    icon: const Icon(Icons.add_link),
                    label: Text(l10n.translate('add_network_printer_manually')),
                  ),
                ] else
                  _buildManualForm(l10n),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('cancel')),
        ),
        FilledButton(
          onPressed: _canSave() ? _onSave : null,
          child: Text(l10n.translate('save')),
        ),
      ],
    );
  }

  Widget _buildScanControls(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isScanning ? null : _startScan,
            icon: _isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_isScanning
                ? l10n.translate('scanning')
                : l10n.translate('start_scan')),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _isScanning ? _stopScan : null,
          icon: const Icon(Icons.stop),
          label: Text(l10n.translate('stop_scan')),
        ),
      ],
    );
  }

  Widget _buildDiscoveredList(AppLocalizations l10n, ThemeData theme) {
    if (_discovered.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Text(
          _isScanning
              ? l10n.translate('scanning')
              : l10n.translate('no_printers_found'),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _discovered.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final p = _discovered[i];
          final selected = _selectedDiscovered != null &&
              _selectedDiscovered!.address == p.address;
          return ListTile(
            dense: true,
            leading: Icon(
              p.connectionType == ConnectionType.NETWORK
                  ? Icons.lan_outlined
                  : Icons.usb,
              color: selected ? theme.colorScheme.primary : null,
            ),
            title: Text(p.name ?? '—'),
            subtitle: Text(
              '${p.connectionType?.name ?? '?'} · ${p.address ?? '—'}',
            ),
            trailing: selected
                ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                : null,
            onTap: () => setState(() => _selectedDiscovered = p),
          );
        },
      ),
    );
  }

  Widget _buildManualForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.existing == null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _manualMode = false),
              icon: const Icon(Icons.arrow_back),
              label: Text(l10n.translate('scan_for_printers')),
            ),
          ),
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: l10n.translate('network_printer'),
            prefixIcon: const Icon(Icons.label_outline),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addressCtrl,
          decoration: InputDecoration(
            labelText: l10n.translate('ip_address'),
            prefixIcon: const Icon(Icons.lan_outlined),
            hintText: '192.168.1.50:9100',
            border: const OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ConnectionType>(
          value: _manualType,
          decoration: const InputDecoration(
            labelText: 'Connection type',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final t in ConnectionType.values)
              DropdownMenuItem(value: t, child: Text(t.name)),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _manualType = v);
          },
        ),
      ],
    );
  }

  bool _canSave() {
    if (_labelCtrl.text.trim().isEmpty) return false;
    if (_manualMode) return _addressCtrl.text.trim().isNotEmpty;
    return _selectedDiscovered != null;
  }

  void _onSave() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final id = widget.existing?.id ?? const Uuid().v4();
    final NamedPrinter result;
    if (_manualMode) {
      result = NamedPrinter(
        id: id,
        label: _labelCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        connectionType: _manualType,
      );
    } else {
      final p = _selectedDiscovered!;
      result = NamedPrinter(
        id: id,
        label: _labelCtrl.text.trim(),
        address: p.address ?? '',
        name: p.name ?? '',
        connectionType: p.connectionType ?? ConnectionType.NETWORK,
      );
    }
    Navigator.of(context).pop(result);
  }
}
