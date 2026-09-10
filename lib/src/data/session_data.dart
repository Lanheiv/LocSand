// data/session_data.dart
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

class SessionData {
  static final SessionData _instance = SessionData._internal();
  factory SessionData() => _instance;
  SessionData._internal();

  String? userId;
  String? userName;
  String? userIp;
  DateTime? userOnlineTime;

  final Map<String, PeerData> peers = {};

  // One TCP connection per deviceId (only when user connects)
  final Map<String, TcpPeerConnection> _tcpConnections = {};

  void clear() {
    userId = null;
    userName = null;
    userIp = null;
    userOnlineTime = null;
    peers.clear();

    for (final conn in _tcpConnections.values) {
      conn.disconnect();
    }
    _tcpConnections.clear();
  }

  void addOrUpdatePeer(PeerData peer) {
    peers[peer.deviceId] = peer;
    userOnlineTime = DateTime.now();
  }

  PeerData? getPeer(String deviceId) => peers[deviceId];
  List<PeerData> get allPeers => peers.values.toList();

  TcpPeerConnection? getTcpConnection(String deviceId) =>
      _tcpConnections[deviceId];

  /// Create TCP connection only when user chooses to connect.
  Future<TcpPeerConnection> connectToPeer(
    String deviceId, {
    Function(Map<String, dynamic>)? onMessage,
    Function(Object)? onError,
    Function()? onDisconnected,
  }) async {
    // If already connected, reuse
    var conn = _tcpConnections[deviceId];
    if (conn != null && conn.isConnected) {
      return conn;
    }

    final peer = getPeer(deviceId);
    if (peer == null) {
      throw StateError("Peer $deviceId not found");
    }

    conn = TcpPeerConnection(
      deviceId: deviceId,
      ip: peer.ip,
      port: peer.port,
      onMessage: onMessage,
      onError: onError,
      onDisconnected: () {
        onDisconnected?.call();
        _tcpConnections.remove(deviceId);
      },
    );

    await conn.connect();
    _tcpConnections[deviceId] = conn;
    return conn;
  }

  void disconnectFromPeer(String deviceId) {
    final conn = _tcpConnections.remove(deviceId);
    conn?.disconnect();
  }
}