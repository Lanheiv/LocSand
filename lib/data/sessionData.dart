import 'package:locsand/data/peerData.dart';

class SessionData {
  static final SessionData _instance = SessionData._internal();
  factory SessionData() => _instance;
  SessionData._internal();

  String? userId;
  String? userName;
  String? userIp;
  DateTime? userOnlineTime;

  final Map<String, PeerData> peers = {};

  void clear() {
    userId = null;
    userName = null;
    userIp = null;
    userOnlineTime = null;
    peers.clear();
  }

  void addOrUpdatePeer(PeerData peer) {
    peers[peer.deviceId] = peer;
    userOnlineTime = DateTime.now();
  }

  PeerData? getPeer(String deviceId) => peers[deviceId];
  List<PeerData> get allPeers => peers.values.toList();
}