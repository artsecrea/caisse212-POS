import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import '../domain/models/socket_models.dart';
import 'database_providers.dart';

// KDS Providers
final kdsListProvider = StreamProvider<List<KDS>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.kDSs)..watch()).watch();
});

final activeKdsListProvider = StreamProvider<List<KDS>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.kDSs)
    ..where((tbl) => tbl.isActive.equals(true))
    ..watch()).watch();
});

final kdsProvider = StreamProvider.family<KDS?, int>((ref, kdsId) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.kDSs)
    ..where((tbl) => tbl.id.equals(kdsId))
    ..watch()).watchSingleOrNull();
});

// Kiosk Providers
final kioskListProvider = StreamProvider<List<Kiosk>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.kiosks)..watch()).watch();
});

final activeKioskListProvider = StreamProvider<List<Kiosk>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.kiosks)
    ..where((tbl) => tbl.isActive.equals(true))
    ..watch()).watch();
});

final kioskProvider = StreamProvider.family<Kiosk?, int>((ref, kioskId) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.kiosks)
    ..where((tbl) => tbl.id.equals(kioskId))
    ..watch()).watchSingleOrNull();
});

// Station Providers
final stationListProvider = StreamProvider<List<Station>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.stations)..watch()).watch();
});

final stationProvider = StreamProvider.family<Station?, int>((ref, stationId) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.stations)
    ..where((tbl) => tbl.id.equals(stationId))
    ..watch()).watchSingleOrNull();
});

// KDS with Station info
class KDSWithStation {
  final KDS kds;
  final Station? station;

  KDSWithStation({required this.kds, this.station});
}

final kdsWithStationProvider = StreamProvider.family<KDSWithStation?, int>((ref, kdsId) async* {
  final database = ref.watch(databaseProvider);

  await for (final kds in (database.select(database.kDSs)
    ..where((tbl) => tbl.id.equals(kdsId))
    ..watch()).watchSingleOrNull()) {

    if (kds == null) {
      yield null;
      continue;
    }

    if (kds.stationId == null) {
      yield KDSWithStation(kds: kds);
      continue;
    }

    final station = await (database.select(database.stations)
      ..where((tbl) => tbl.id.equals(kds.stationId!)))
        .getSingleOrNull();

    yield KDSWithStation(kds: kds, station: station);
  }
});

// Get all KDS devices for a specific station
final kdsListByStationProvider = StreamProvider.family<List<KDS>, int>((ref, stationId) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.kDSs)
    ..where((tbl) => tbl.stationId.equals(stationId))
    ..watch()).watch();
});

// Convert to Socket Models
final socketKdsListProvider = StreamProvider<List<SocketDeviceModel>>((ref) async* {
  final kdsListAsync = ref.watch(kdsListProvider);

  yield* kdsListAsync.when(
    data: (kdsList) async* {
      yield kdsList.map((kds) => SocketDeviceModel(
        id: kds.id,
        name: kds.name,
        description: kds.description,
        ip: kds.ip,
        port: kds.port,
        location: kds.location,
        isActive: kds.isActive,
        type: 'KDS',
      )).toList();
    },
    loading: () async* {
      yield <SocketDeviceModel>[];
    },
    error: (err, stack) async* {
      yield <SocketDeviceModel>[];
    },
  );
});

final socketKioskListProvider = StreamProvider<List<SocketDeviceModel>>((ref) async* {
  final kioskListAsync = ref.watch(kioskListProvider);

  yield* kioskListAsync.when(
    data: (kioskList) async* {
      yield kioskList.map((kiosk) => SocketDeviceModel(
        id: kiosk.id,
        name: kiosk.name,
        description: kiosk.description,
        ip: kiosk.ip,
        port: kiosk.port,
        location: kiosk.location,
        isActive: kiosk.isActive,
        type: 'KIOSK',
      )).toList();
    },
    loading: () async* {
      yield <SocketDeviceModel>[];
    },
    error: (err, stack) async* {
      yield <SocketDeviceModel>[];
    },
  );
});

final socketStationListProvider = StreamProvider<List<SocketStationModel>>((ref) async* {
  final database = ref.watch(databaseProvider);
  final stationsAsync = ref.watch(stationListProvider);

  yield* stationsAsync.when(
    data: (stations) async* {
      final socketStations = <SocketStationModel>[];

      for (final station in stations) {
        // Get all KDS devices assigned to this station
        final kdsList = await (database.select(database.kDSs)
          ..where((tbl) => tbl.stationId.equals(station.id)))
            .get();

        // Get the first active KDS for this station (if any)
        final activeKds = kdsList.where((kds) => kds.isActive).firstOrNull;

        socketStations.add(SocketStationModel(
          id: station.id,
          name: station.name,
          description: station.description,
          kdsId: activeKds?.id,
          kdsName: activeKds?.name,
        ));
      }

      yield socketStations;
    },
    loading: () async* {
      yield <SocketStationModel>[];
    },
    error: (err, stack) async* {
      yield <SocketStationModel>[];
    },
  );
});

// All devices combined
final allSocketDevicesProvider = StreamProvider<List<SocketDeviceModel>>((ref) async* {
  final kdsList = ref.watch(socketKdsListProvider);
  final kioskList = ref.watch(socketKioskListProvider);

  if (kdsList.hasValue && kioskList.hasValue) {
    yield [...kdsList.value!, ...kioskList.value!];
  }
});



// Provider to track connected devices

// Device Repository for CRUD operations
class DeviceRepository {
  final AppDatabase _database;

  DeviceRepository(this._database);

  // Add device
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
  Future<void> deleteDevice(int id, String type) async {
    if (type == 'KDS') {
      await (_database.delete(_database.kDSs)..where((tbl) => tbl.id.equals(id))).go();
    } else {
      await (_database.delete(_database.kiosks)..where((tbl) => tbl.id.equals(id))).go();
    }
  }

  Future<Station?> getStationById(int id) =>
      (_database.select(_database.stations)..where((tbl) => tbl.id.equals(id)))
          .getSingleOrNull();

  /// Ids are assigned locally (max + 1), as for KDS and kiosks in
  /// [addDevice]. An empty [description] is stored as null. Returns the new id.
  Future<int> addStation({required String name, String? description}) async {
    final maxId = await (_database.selectOnly(_database.stations)
      ..addColumns([_database.stations.id.max()]))
      .map((row) => row.read(_database.stations.id.max()))
      .getSingleOrNull();
    final newId = (maxId ?? 0) + 1;

    await _database.into(_database.stations).insert(
      StationsCompanion.insert(
        id: Value(newId),
        name: name,
        description: Value(description == null || description.isEmpty ? null : description),
      ),
    );
    return newId;
  }
}

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return DeviceRepository(database);
});

