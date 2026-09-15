// data/session_data.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

class SessionData extends ChangeNotifier {
  static final SessionData _instance = SessionData._internal();
  factory SessionData() => _instance;
  SessionData._internal();

  String? userId;
  String? userName;
  String? userIp;
  DateTime? userOnlineTime;

  final Map<String, PeerData> peers = {};
  final Map<String, TcpPeerConnection> _tcpConnections = {};

  void Function(String deviceId, String name, void Function(bool accept) respond)?
      onIncomingRequest;

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
    notifyListeners();
  }

  void addOrUpdatePeer(PeerData peer) {
    peers[peer.deviceId] = peer;
    userOnlineTime = DateTime.now();
    notifyListeners();
  }

  PeerData? getPeer(String deviceId) => peers[deviceId];
  List<PeerData> get allPeers => peers.values.toList();

  TcpPeerConnection? getTcpConnection(String deviceId) => _tcpConnections[deviceId];

  Future<TcpPeerConnection> connectToPeer(
    String deviceId, {
    Function(Map<String, dynamic>)? onMessage,
    Function(Object)? onError,
    Function()? onDisconnected,
  }) async {
    var existing = _tcpConnections[deviceId];
    if (existing != null && existing.isConnected) {
      return existing;
    }

    final peer = getPeer(deviceId);
    if (peer == null) {
      throw StateError("Peer $deviceId not found");
    }

    final response = Completer<bool>();

    final conn = TcpPeerConnection(
      deviceId: deviceId,
      ip: peer.ip,
      port: peer.port,
      onMessage: (msg) {
        final type = msg['type'];
        if (!response.isCompleted && (type == 'accept' || type == 'reject')) {
          response.complete(type == 'accept');
          return;
        }
        onMessage?.call(msg);
      },
      onError: onError,
      onDisconnected: () {
        if (!response.isCompleted) response.complete(false);
        _tcpConnections.remove(deviceId);
        onDisconnected?.call();
        notifyListeners();
      },
    );

    await conn.connect();

    conn.send({'type': 'request', 'deviceId': userId, 'name': userName});

    final accepted = await response.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => false,
    );

    if (!accepted) {
      await conn.disconnect();
      throw StateError("Connection request was declined or timed out");
    }

    _tcpConnections[deviceId] = conn;
    notifyListeners();
    return conn;
  }

  void registerIncomingConnection(String deviceId, TcpPeerConnection conn) {
    final existing = _tcpConnections[deviceId];
    if (existing != null && existing != conn) {
      existing.disconnect();
    }
    _tcpConnections[deviceId] = conn;
    notifyListeners();
  }

  void disconnectFromPeer(String deviceId, {bool closeSocket = true}) {
    final conn = _tcpConnections.remove(deviceId);
    if (closeSocket) {
      conn?.disconnect();
    }
    notifyListeners();
  }
}