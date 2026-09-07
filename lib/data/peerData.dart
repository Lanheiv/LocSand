class PeerInfo {
  final String deviceId;
  final String name;
  final String ip;
  final int port;
  final DateTime lastSeen;

  PeerInfo({
    required this.deviceId,
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });
}