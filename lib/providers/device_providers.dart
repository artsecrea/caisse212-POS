import 'package:flutter_riverpod/flutter_riverpod.dart';
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

// Station with KDS info
class StationWithKDS {
  final Station station;
  final KDS? kds;

  StationWithKDS({required this.station, this.kds});
}

final stationWithKdsProvider = StreamProvider.family<StationWithKDS?, int>((ref, stationId) async* {
  final database = ref.watch(databaseProvider);

  await for (final station in (database.select(database.stations)
    ..where((tbl) => tbl.id.equals(stationId))
    ..watch()).watchSingleOrNull()) {

    if (station == null) {
      yield null;
      continue;
    }

    if (station.kdsId == null) {
      yield StationWithKDS(station: station);
      continue;
    }

    final kds = await (database.select(database.kDSs)
      ..where((tbl) => tbl.id.equals(station.kdsId!)))
        .getSingleOrNull();

    yield StationWithKDS(station: station, kds: kds);
  }
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
        String? kdsName;
        if (station.kdsId != null) {
          final kds = await (database.select(database.kDSs)
            ..where((tbl) => tbl.id.equals(station.kdsId!)))
              .getSingleOrNull();
          kdsName = kds?.name;
        }

        socketStations.add(SocketStationModel(
          id: station.id,
          name: station.name,
          description: station.description,
          kdsId: station.kdsId,
          kdsName: kdsName,
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

