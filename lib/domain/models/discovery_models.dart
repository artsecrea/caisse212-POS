class DiscoveredDevice {
  final String id;
  final String name;
  final String ip;
  final String platform;
  final DateTime lastSeen;
  final int port;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.platform,
    required this.lastSeen,
    required this.port,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ip': ip,
    "port": port,
    'platform': platform,
    'lastSeen': lastSeen.toIso8601String(),
  };
}