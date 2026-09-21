import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/chat_message.dart';
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

  // deviceId -> list of chat messages exchanged with that peer
  final Map<String, List<ChatMessage>> chatMessages = {};

  void Function(String deviceId, String name, void Function(bool accept) respond)?
      onIncomingRequest;

  Timer? _pruneTimer;

  void startPeerPruning({
    Duration interval = const Duration(seconds: 15),
    Duration staleAfter = const Duration(seconds: 90),
  }) {
    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(interval, (_) => _prunePeers(staleAfter));
  }

  void stopPeerPruning() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
  }

  void _prunePeers(Duration staleAfter) {
    final now = DateTime.now();
    final staleIds = peers.entries
        .where((e) =>
            now.difference(e.value.lastSeen) > staleAfter &&
            !(_tcpConnections[e.key]?.isConnected ?? false))
        .map((e) => e.key)
        .toList();

    if (staleIds.isEmpty) return;

    for (final id in staleIds) {
      peers.remove(id);
    }
    notifyListeners();
  }

  void clear() {
    userId = null;
    userName = null;
    userIp = null;
    userOnlineTime = null;
    peers.clear();
    chatMessages.clear();

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
        if (type == 'chat') {
          receiveChatMessage(deviceId, msg['text'] as String? ?? '');
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

  List<ChatMessage> getChatMessages(String deviceId) => chatMessages[deviceId] ?? [];

  void receiveChatMessage(String deviceId, String text) {
    chatMessages.putIfAbsent(deviceId, () => []).add(
          ChatMessage(text: text, fromMe: false, time: DateTime.now()),
        );
    notifyListeners();
  }

  void sendChatMessage(String deviceId, String text) {
    final conn = _tcpConnections[deviceId];
    if (conn == null || !conn.isConnected) {
      throw StateError("Not connected to $deviceId");
    }
    conn.send({'type': 'chat', 'text': text});
    chatMessages.putIfAbsent(deviceId, () => []).add(
          ChatMessage(text: text, fromMe: true, time: DateTime.now()),
        );
    notifyListeners();
  }
}