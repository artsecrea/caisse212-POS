// filepath: /home/artecrea/StudioProjects/posecrea/lib/services/barcode_scanner_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Service to handle barcode scanner input from USB/Wireless barcode scanners
/// These scanners act as keyboard input devices
class BarcodeScannerService {
  static final BarcodeScannerService _instance = BarcodeScannerService._internal();
  factory BarcodeScannerService() => _instance;
  BarcodeScannerService._internal();

  final _barcodeController = StreamController<String>.broadcast();
  Stream<String> get barcodeStream => _barcodeController.stream;

  final StringBuffer _buffer = StringBuffer();
  Timer? _debounceTimer;
  final Duration _scanTimeout = const Duration(milliseconds: 100);

  bool _isEnabled = false;
  FocusNode? _focusNode;

  /// Initialize the barcode scanner listener
  void initialize(FocusNode focusNode) {
    _focusNode = focusNode;
    _isEnabled = true;
    debugPrint('BarcodeScannerService: Initialized');
  }

  /// Handle raw keyboard events
  KeyEventResult handleKeyEvent(KeyEvent event) {
    if (!_isEnabled) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      final character = event.character;

      // Enter key indicates end of barcode scan
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        _processScan();
        return KeyEventResult.handled;
      }

      // Add character to buffer
      if (character != null && character.isNotEmpty) {
        _buffer.write(character);

        // Reset debounce timer
        _debounceTimer?.cancel();
        _debounceTimer = Timer(_scanTimeout, _processScan);

        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Process the scanned barcode
  void _processScan() {
    _debounceTimer?.cancel();

    if (_buffer.isNotEmpty) {
      final barcode = _buffer.toString().trim();
      _buffer.clear();

      if (barcode.isNotEmpty) {
        debugPrint('BarcodeScannerService: Scanned barcode: $barcode');
        _barcodeController.add(barcode);
      }
    }
  }

  /// Enable barcode scanning
  void enable() {
    _isEnabled = true;
    _focusNode?.requestFocus();
    debugPrint('BarcodeScannerService: Enabled');
  }

  /// Disable barcode scanning
  void disable() {
    _isEnabled = false;
    _buffer.clear();
    _debounceTimer?.cancel();
    debugPrint('BarcodeScannerService: Disabled');
  }

  /// Dispose resources
  void dispose() {
    _debounceTimer?.cancel();
    _barcodeController.close();
    _buffer.clear();
  }
}


