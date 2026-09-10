class PeerData {
  final String deviceId;
  final String name;
  final String ip;
  final int port;
  final DateTime lastSeen;

  PeerData({
    required this.deviceId,
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });
}