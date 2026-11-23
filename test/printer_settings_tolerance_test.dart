import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

import 'package:caisse212/services/printing_service.dart';

/// A stored enum index that this build does not know used to throw while
/// loading, leave the printer config at its defaults, and let the next save
/// write those defaults over every printer setting on the till.
void main() {
  test('pool printer with an unknown connection type still loads', () {
    final p = NamedPrinter.fromJson({
      'id': 'a',
      'label': 'Bar',
      'address': '10.0.0.5',
      'name': 'Bar',
      'connectionType': 9,
    });
    expect(p.label, 'Bar');
    expect(p.connectionType, ConnectionType.BLE);
  });

  test('stored connection types keep their meaning', () {
    expect(ConnectionType.values,
        [ConnectionType.BLE, ConnectionType.USB, ConnectionType.NETWORK]);
  });

  test('printer config with out-of-range indexes keeps the rest', () {
    final c = PrinterConfig.fromJson({
      'receiptPrinterAddress': 'printer WD8260',
      'receiptConnectionType': 7,
      'kdsConnectionType': -1,
      'defaultKdsMode': 42,
      'kdsEnabled': false,
    });
    expect(c.receiptPrinterAddress, 'printer WD8260');
    expect(c.receiptConnectionType, isNull);
    expect(c.kdsConnectionType, isNull);
    expect(c.defaultKdsMode, KdsPrintMode.modificationsOnly);
    expect(c.kdsEnabled, isFalse);
  });
}
