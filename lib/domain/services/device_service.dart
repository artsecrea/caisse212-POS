import '../../data/database/app_database.dart' show KDS, Kiosk, Station;

/// The LAN devices — KDS screens and kiosks — and the kitchen stations, as
/// the devices screen lists and edits them. An interface because, linked to
/// a hub, the hub holds them: standalone, this till does (`DeviceRepository`).
abstract interface class DeviceService {
  /// The KDS screens, as they change.
  Stream<List<KDS>> watchKdsList();

  /// The kiosks, as they change.
  Stream<List<Kiosk>> watchKiosks();

  /// The kitchen stations, as they change.
  Stream<List<Station>> watchStations();

  Future<int> addDevice({
    required String name,
    required String type,
    String? ip,
    int? port,
    String? location,
    String? description,
    bool isActive = true,
    int? stationId,
  });

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
  });

  Future<void> deleteDevice(int id, String type);

  Future<Station?> getStationById(int id);
}
