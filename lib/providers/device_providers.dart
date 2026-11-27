import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import 'database_providers.dart';
import '../domain/services/device_service.dart';

// KDS Providers
final kdsListProvider = StreamProvider<List<KDS>>(
    (ref) => ref.watch(deviceServiceProvider).watchKdsList());

// Kiosk Providers
final kioskListProvider = StreamProvider<List<Kiosk>>(
    (ref) => ref.watch(deviceServiceProvider).watchKiosks());

// Station Providers
final stationListProvider = StreamProvider<List<Station>>(
    (ref) => ref.watch(deviceServiceProvider).watchStations());

/// The LAN devices — KDS screens, kiosks — and the kitchen stations, on
/// this till's database.
class DeviceRepository implements DeviceService {
  final AppDatabase _database;

  DeviceRepository(this._database);

  // Add device
  @override
  Future<int> addDevice({
    required String name,
    required String type,
    String? ip,
    int? port,
    String? location,
    String? description,
    bool isActive = true,
    int? stationId,
  }) async {
    if (type == 'KDS') {
      // Get next ID
      final maxId = await (_database.selectOnly(_database.kDSs)
        ..addColumns([_database.kDSs.id.max()]))
        .map((row) => row.read(_database.kDSs.id.max()))
        .getSingleOrNull();
      final newId = (maxId ?? 0) + 1;

      return await _database.into(_database.kDSs).insert(
        KDSsCompanion.insert(
          id: Value(newId),
          name: name,
          description: Value(description),
          stationId: Value(stationId),
          ip: Value(ip),
          port: Value(port),
          location: Value(location),
          isActive: Value(isActive),
        ),
      );
    } else {
      // Get next ID
      final maxId = await (_database.selectOnly(_database.kiosks)
        ..addColumns([_database.kiosks.id.max()]))
        .map((row) => row.read(_database.kiosks.id.max()))
        .getSingleOrNull();
      final newId = (maxId ?? 0) + 1;

      return await _database.into(_database.kiosks).insert(
        KiosksCompanion.insert(
          id: Value(newId),
          name: name,
          description: Value(description),
          ip: Value(ip),
          port: Value(port),
          location: Value(location),
          isActive: Value(isActive),
        ),
      );
    }
  }

  // Update device
  @override
  Future<void> updateDevice({
    required int id,
    required String type,
    required String name,
    String? ip,
    int? port,
    String? location,
    String? description,
    bool isActive = true,
    int? stationId,
  }) async {
    if (type == 'KDS') {
      await (_database.update(_database.kDSs)..where((tbl) => tbl.id.equals(id))).write(
        KDSsCompanion(
          name: Value(name),
          description: Value(description),
          stationId: Value(stationId),
          ip: Value(ip),
          port: Value(port),
          location: Value(location),
          isActive: Value(isActive),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await (_database.update(_database.kiosks)..where((tbl) => tbl.id.equals(id))).write(
        KiosksCompanion(
          name: Value(name),
          description: Value(description),
          ip: Value(ip),
          port: Value(port),
          location: Value(location),
          isActive: Value(isActive),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  // Delete device
  @override
  Future<void> deleteDevice(int id, String type) async {
    if (type == 'KDS') {
      await (_database.delete(_database.kDSs)..where((tbl) => tbl.id.equals(id))).go();
    } else {
      await (_database.delete(_database.kiosks)..where((tbl) => tbl.id.equals(id))).go();
    }
  }

  @override
  Future<Station?> getStationById(int id) =>
      (_database.select(_database.stations)..where((tbl) => tbl.id.equals(id)))
          .getSingleOrNull();

  /// The KDS screens, as they change.
  @override
  Stream<List<KDS>> watchKdsList() =>
      (_database.select(_database.kDSs)..watch()).watch();

  /// The kiosks, as they change.
  @override
  Stream<List<Kiosk>> watchKiosks() =>
      (_database.select(_database.kiosks)..watch()).watch();

  /// The kitchen stations, as they change.
  @override
  Stream<List<Station>> watchStations() =>
      (_database.select(_database.stations)..watch()).watch();
}

/// The devices for the screens. A hub-linked till overrides this one
/// provider; nothing else changes.
final deviceServiceProvider = Provider<DeviceService>((ref) {
  final database = ref.watch(databaseProvider);
  return DeviceRepository(database);
});
