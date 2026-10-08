import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/saved_peer.dart';
import 'package:locsand/src/helpers/auth_protocol.dart';
import 'package:locsand/src/helpers/device_identity.dart';
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

  /// Upper bound for the nearby-peer list, so a UDP flood with random ids
  /// cannot grow memory or the UI without limit.
  static const int _maxNearbyPeers = 256;

  /// Set when the network core could not start (port busy, key error, ...).
  /// The UI shows it so the user does not just see an empty list.
  String? startupError;

  void reportStartupError(String message) {
    startupError = message;
    notifyListeners();
  }

  @override
  String? userId;
  @override
  String? userName;

  final Map<String, PeerData> peers = {};
  final Map<String, TcpPeerConnection> _connections = {};
  final Map<String, Future<TcpPeerConnection>> _pending = {};
  final Map<String, DateTime> _autoRetryAt = {};
  final Map<String, DateTime> _autoWaitSince = {};
  bool _away = false;

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
    final id = peer.deviceId;
    final old = peers[id];
    if (old == null && peers.length >= _maxNearbyPeers && !isPeerSaved(id)) return;

    peers[id] = peer;
    // Refreshing lastSeen every few seconds must not rebuild the whole UI.
    if (old == null ||
        old.name != peer.name ||
        old.ip != peer.ip ||
        old.port != peer.port) {
      notifyListeners();
    }

    final now = DateTime.now();
    if (isConnected(id)) _autoWaitSince.remove(id);

    // Avoid both devices dialing each other at the same moment (they would
    // close each other's sockets). The device with the smaller id dials
    // first; the other one only dials if that did not work after a while.
    var myTurn = true;
    if (isPeerSaved(id) && !isConnected(id)) {
      final iAmFirst = (userId ?? '').compareTo(id) < 0;
      if (!iAmFirst) {
        final since = _autoWaitSince.putIfAbsent(id, () => now);
        myTurn = now.difference(since) >= const Duration(seconds: 8);
      }
    }

    if (myTurn &&
        isPeerSaved(id) &&
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

    final identity = await DeviceIdentity.load();
    final challenge = Completer<Map<String, dynamic>>();
    final response = Completer<bool>();
    var authenticated = false;
    late final TcpPeerConnection conn;
    conn = TcpPeerConnection(
      deviceId: deviceId,
      ip: ip,
      port: port,
      onMessage: (msg) {
        final type = msg['type'];
        if (!authenticated) {
          if (type == 'challenge' && !challenge.isCompleted) challenge.complete(msg);
          return;
        }
        if (response.isCompleted) {
          handlePeerMessage(deviceId, msg);
        } else if (type == 'accept' || type == 'reject') {
          response.complete(type == 'accept');
        }
      },
      onDisconnected: () {
        if (!challenge.isCompleted) challenge.complete(const {});
        if (!response.isCompleted) response.complete(false);
        disconnectFromPeer(deviceId, closeSocket: false, ifCurrent: conn);
      },
    );

    try {
      await conn.connect();

      final clientNonce = newNonce();
      conn.send({
        'type': 'hello',
        'deviceId': identity.deviceId,
        'name': userName,
        'pub': identity.publicKeyPem,
        'nonce': clientNonce,
      });

      final ch = await challenge.future.timeout(
        _connectTimeout,
        onTimeout: () => const <String, dynamic>{},
      );

      // The id we dialed is the hash of the public key we expect. A device
      // that does not hold the matching private key cannot produce a valid
      // signature, no matter what its UDP announcement claimed.
      final peerPub = ch['pub'];
      final serverNonce = ch['nonce'];
      final sigB64 = ch['sig'];
      final certDer = conn.serverCertDer;
      Uint8List? signature;
      try {
        if (sigB64 is String && sigB64.length <= 1024) signature = base64Decode(sigB64);
      } catch (_) {}

      final verified = peerPub is String &&
          peerPub.length <= 1024 &&
          serverNonce is String &&
          serverNonce.length >= 16 &&
          serverNonce.length <= 64 &&
          certDer != null &&
          signature != null &&
          deviceIdFromPublicKey(peerPub) == deviceId &&
          DeviceIdentity.verify(
            peerPub,
            authTranscript(
              role: 'server',
              clientId: identity.deviceId,
              serverId: deviceId,
              clientNonce: clientNonce,
              serverNonce: serverNonce,
              serverCertDer: certDer,
            ),
            signature,
          );
      if (!verified) {
        throw StateError(
          'Could not verify the identity of this device. It may be offline, '
          'running an old version, or another device is pretending to be it.',
        );
      }

      authenticated = true;
      conn.send({
        'type': 'request',
        'sig': base64Encode(identity.sign(authTranscript(
          role: 'client',
          clientId: identity.deviceId,
          serverId: deviceId,
          clientNonce: clientNonce,
          serverNonce: serverNonce as String,
          serverCertDer: certDer!,
        ))),
      });

      final accepted = await response.future.timeout(
        _connectTimeout,
        onTimeout: () => false,
      );
      if (!accepted) {
        throw StateError('Connection was declined or timed out');
      }
    } catch (_) {
      await conn.disconnect();
      rethrow;
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
    _autoWaitSince.remove(deviceId);
    if (closeSocket) current?.disconnect();
    failTransfersFor(deviceId);
    notifyListeners();
  }

  /// App goes to the background (file picker, other app, ...).
  void awayAll() {
    if (_away) return;
    _away = true;
    for (final c in _connections.values) {
      c.markAway();
    }
  }

  /// App is back in the foreground.
  void backAll() {
    _away = false;
    for (final c in _connections.values) {
      c.markBack();
    }
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