import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/printing_service.dart';

/// One station, several printers.
///
/// A station's assignment is a LIST of pool printer ids — every printer in it
/// gets its own copy of that station's kitchen ticket. What's worth protecting
/// is that a one-printer kitchen behaves exactly as it did before the list,
/// that "unassigned" stays distinguishable from "print nowhere", and that
/// editing the printer pool can never silently re-route or un-silence a
/// station (the cashier would only find out from the kitchen).

NamedPrinter _printer(String id) => NamedPrinter(
      id: id,
      label: id.toUpperCase(),
      address: '10.0.0.$id',
      name: id,
      connectionType: ConnectionType.NETWORK,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late PrintingService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // The service is a singleton, so each test has to clear what the last one
    // left behind. Pool first: emptying it prunes assignments.
    service = PrintingService();
    await service.savePrinterPool(prefs, const []);
    await service.saveStationAssignments(prefs, const {});
  });

  group('assignment shape', () {
    test('three printers on one station survive a round trip', () async {
      await service.savePrinterPool(
          prefs, [_printer('1'), _printer('2'), _printer('3')]);
      await service.saveStationAssignments(prefs, {
        7: ['1', '2', '3'],
      });

      expect(service.stationAssignments[7], ['1', '2', '3']);
      expect(service.isStationSilenced(7), isFalse);
    });

    test('a single printer reads back exactly as one entry', () async {
      await service.savePrinterPool(prefs, [_printer('1')]);
      await service.saveStationAssignments(prefs, {
        7: ['1'],
      });

      expect(service.stationAssignments[7], ['1']);
    });

    test('unassigned is stored as absent, not as an empty list', () async {
      await service.saveStationAssignments(prefs, {7: const []});

      // An empty list would read as "assigned to nothing", which is the
      // silenced case. Absent means "fall back to the global KDS printer".
      expect(service.stationAssignments.containsKey(7), isFalse);
      expect(service.isStationSilenced(7), isFalse);
    });

    test('the sentinel silences the station', () async {
      await service.saveStationAssignments(prefs, {
        7: [kNoPrinterAssignment],
      });

      expect(service.isStationSilenced(7), isTrue);
    });

    test('persists as JSON lists, which the migrating reader expects',
        () async {
      await service.savePrinterPool(prefs, [_printer('1'), _printer('2')]);
      await service.saveStationAssignments(prefs, {
        7: ['1', '2'],
      });

      final raw = prefs.getString('station_printer_assignments_v1');
      expect(raw, contains('["1","2"]'));
    });
  });

  group('editing the printer pool', () {
    test('deleting one printer leaves the station its other two', () async {
      await service.savePrinterPool(
          prefs, [_printer('1'), _printer('2'), _printer('3')]);
      await service.saveStationAssignments(prefs, {
        7: ['1', '2', '3'],
      });

      await service.savePrinterPool(prefs, [_printer('1'), _printer('3')]);

      expect(service.stationAssignments[7], ['1', '3']);
    });

    test('a station left with no surviving printer falls back to default',
        () async {
      await service.savePrinterPool(prefs, [_printer('1')]);
      await service.saveStationAssignments(prefs, {
        7: ['1'],
      });

      await service.savePrinterPool(prefs, const []);

      expect(service.stationAssignments.containsKey(7), isFalse);
      expect(service.isStationSilenced(7), isFalse);
    });

    test('a silenced station stays silenced when the pool changes', () async {
      await service.saveStationAssignments(prefs, {
        7: [kNoPrinterAssignment],
      });

      // The sentinel is not a pool id, so pruning by pool membership used to
      // drop it — turning "never print this station" back into "print it on
      // the default KDS printer" the next time a printer was added.
      await service.savePrinterPool(prefs, [_printer('1')]);

      expect(service.isStationSilenced(7), isTrue);
    });
  });
}
