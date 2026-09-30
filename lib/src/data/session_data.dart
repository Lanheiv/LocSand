import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/saved_peer.dart';
import 'package:locsand/src/helpers/peer_store.dart';
import 'package:locsand/src/session/chat_session.dart';
import 'package:locsand/src/session/file_session.dart';
import 'package:locsand/src/session/saved_peers_session.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

class SessionData extends ChangeNotifier
    with SavedPeersSession, ChatSession, FileSession {
  static final SessionData _instance = SessionData._();
  factory SessionData() => _instance;
  SessionData._();

  static const Duration _stalePeerAfter = Duration(seconds: 45);
  static const Duration _autoConnectBackoff = Duration(seconds: 15);
  static const Duration _declinedBackoff = Duration(minutes: 5);
  static const Duration _connectTimeout = Duration(seconds: 30);

  @override
  String? userId;
  @override
  String? userName;

  final Map<String, PeerData> peers = {};
  final Map<String, TcpPeerConnection> _connections = {};
  final Map<String, Future<TcpPeerConnection>> _pending = {};
  final Map<String, DateTime> _autoRetryAt = {};

  void Function(String deviceId, String name, void Function(bool accept) respond)?
      onIncomingRequest;

  Timer? _pruneTimer;

  void startPeerPruning() {
    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(seconds: 10), (_) => _prune());
  }

  void _prune() {
    final now = DateTime.now();
    final before = peers.length;
    peers.removeWhere((id, p) =>
        now.difference(p.lastSeen) > _stalePeerAfter && liveConnection(id) == null);
    if (peers.length != before) notifyListeners();
  }

  @override
  PeerData? getPeer(String deviceId) => peers[deviceId];

  List<PeerData> get allPeers => peers.values.toList();

  PeerData resolvePeer(SavedPeer s) =>
      peers[s.deviceId] ??
      PeerData(
        deviceId: s.deviceId,
        name: s.name,
        ip: s.lastKnownIp,
        port: s.lastKnownPort,
        lastSeen: s.savedAt,
      );

  @override
  TcpPeerConnection? liveConnection(String deviceId) {
    final conn = _connections[deviceId];
    return conn != null && conn.isConnected ? conn : null;
  }

  bool isConnected(String deviceId) => liveConnection(deviceId) != null;

  bool isPeerOnline(String deviceId) =>
      isConnected(deviceId) || peers.containsKey(deviceId);

  void addOrUpdatePeer(PeerData peer) {
    peers[peer.deviceId] = peer;
    notifyListeners();

    final id = peer.deviceId;
    final now = DateTime.now();
    if (isPeerSaved(id) &&
        !isConnected(id) &&
        now.isAfter(_autoRetryAt[id] ?? DateTime(0))) {
      _autoRetryAt[id] = now.add(_autoConnectBackoff);
      unawaited(connectToPeer(id).then<void>((_) {}, onError: (Object e) {
        _autoRetryAt[id] = DateTime.now().add(
          e is StateError ? _declinedBackoff : _autoConnectBackoff,
        );
      }));
    }
  }

  Future<TcpPeerConnection> connectToPeer(String deviceId) {
    final live = liveConnection(deviceId);
    if (live != null) return Future.value(live);
    return _pending[deviceId] ??= _dial(deviceId).whenComplete(() {
      _pending.remove(deviceId);
    });
  }

  Future<TcpPeerConnection> _dial(String deviceId) async {
    final peer = peers[deviceId];
    final saved = SavedPeersStore().get(deviceId);
    final ip = peer?.ip ?? saved?.lastKnownIp ?? '';
    final port = peer?.port ?? saved?.lastKnownPort ?? 0;
    if (ip.isEmpty || port == 0) throw StateError('Device not reachable');

    final response = Completer<bool>();
    late final TcpPeerConnection conn;
    conn = TcpPeerConnection(
      deviceId: deviceId,
      ip: ip,
      port: port,
      onMessage: (msg) {
        if (response.isCompleted) {
          handlePeerMessage(deviceId, msg);
        } else if (msg['type'] == 'accept' || msg['type'] == 'reject') {
          response.complete(msg['type'] == 'accept');
        }
      },
      onDisconnected: () {
        if (!response.isCompleted) response.complete(false);
        disconnectFromPeer(deviceId, closeSocket: false, ifCurrent: conn);
      },
    );

    await conn.connect();
    conn.send({'type': 'request', 'deviceId': userId, 'name': userName});

    final accepted = await response.future.timeout(
      _connectTimeout,
      onTimeout: () => false,
    );
    if (!accepted) {
      await conn.disconnect();
      throw StateError('Connection was declined or timed out');
    }

    registerIncomingConnection(deviceId, conn);
    return conn;
  }

  void registerIncomingConnection(String deviceId, TcpPeerConnection conn) {
    final old = _connections[deviceId];
    if (old != null && !identical(old, conn)) old.disconnect();
    _connections[deviceId] = conn;
    notifyListeners();
  }

  void disconnectFromPeer(
    String deviceId, {
    bool closeSocket = true,
    TcpPeerConnection? ifCurrent,
  }) {
    final current = _connections[deviceId];
    if (ifCurrent != null && !identical(current, ifCurrent)) return;
    _connections.remove(deviceId);
    if (closeSocket) current?.disconnect();
    failTransfersFor(deviceId);
    notifyListeners();
  }

  void handlePeerMessage(String deviceId, Map<String, dynamic> msg) {
    final type = msg['type'];
    switch (type) {
      case 'chat':
        receiveChatMessage(deviceId, msg['text'] as String? ?? '');
      case 'save':
        handleSaveRequest(deviceId, msg['name'] as String? ?? deviceId);
      default:
        if (type is String && type.startsWith('file_')) {
          handleFileMessage(deviceId, type, msg);
        }
    }
  }
}
