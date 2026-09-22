import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/chat_message.dart';
import 'package:locsand/src/data/saved_peer.dart';
import 'package:locsand/src/helpers/peer_store.dart';
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

  // deviceId -> outbound connection we've dialed but not yet gotten an
  // accept/reject for. Lets an incoming request for the same peer (i.e.
  // both sides dialing each other at once) detect and resolve the clash.
  final Map<String, TcpPeerConnection> _pendingOutbound = {};

  // deviceId -> the in-flight connectToPeer() call for that peer, if any.
  // Lets a second caller (a manual tap racing an auto-reconnect retry, or
  // two rapid taps) share one attempt instead of opening a second socket.
  final Map<String, Future<TcpPeerConnection>> _connectFutures = {};

  // deviceId -> list of chat messages exchanged with that peer
  final Map<String, List<ChatMessage>> chatMessages = {};

  // deviceId -> persisted connection info. Populated from disk at startup
  // via loadSavedPeers() and kept in sync as saves happen.
  final Map<String, SavedPeer> savedPeers = {};
  final Map<String, Completer<bool>> _pendingSaveRequests = {};
  final Map<String, DateTime> _lastAutoConnectAttempt = {};

  void Function(String deviceId, String name, void Function(bool accept) respond)?
      onIncomingRequest;

  /// Fired when a connected peer asks to save the connection for later
  /// auto-reconnect. The UI should show a prompt and call respond().
  void Function(String deviceId, String name, void Function(bool accept) respond)?
      onSaveRequest;

  Timer? _pruneTimer;

  void startPeerPruning({
    Duration interval = const Duration(seconds: 15),
    Duration staleAfter = const Duration(seconds: 90),
  }) {
    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(interval, (_) {
      _prunePeers(staleAfter);
      // Piggyback on this timer to periodically retry saved peers that
      // aren't currently connected, in case they came back online at the
      // same IP (a fresh UDP broadcast handles the "different IP" case).
      for (final deviceId in savedPeers.keys.toList()) {
        _maybeAutoReconnectSaved(deviceId);
      }
    });
  }

  void stopPeerPruning() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
  }

  void _prunePeers(Duration staleAfter) {
    final now = DateTime.now();
    final staleIds = peers.entries
        .where((e) =>
            !savedPeers.containsKey(e.key) &&
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

    // Peer info changed (e.g. new IP after a DHCP lease change) — if this
    // is a saved connection and we're not already connected, try again.
    if (savedPeers.containsKey(peer.deviceId)) {
      _maybeAutoReconnectSaved(peer.deviceId);
    }
  }

  PeerData? getPeer(String deviceId) => peers[deviceId];
  List<PeerData> get allPeers => peers.values.toList();

  bool isPeerSaved(String deviceId) => savedPeers.containsKey(deviceId);
  List<SavedPeer> get allSavedPeers => savedPeers.values.toList();

  TcpPeerConnection? getTcpConnection(String deviceId) => _tcpConnections[deviceId];

  Future<TcpPeerConnection> connectToPeer(
    String deviceId, {
    Function(Map<String, dynamic>)? onMessage,
    Function(Object)? onError,
    Function()? onDisconnected,
  }) {
    final existing = _tcpConnections[deviceId];
    if (existing != null && existing.isConnected) {
      return Future.value(existing);
    }

    // Dedup: a manual tap and an auto-reconnect retry (or two rapid taps)
    // can both call this for the same peer at nearly the same time. Share
    // the one in-flight attempt instead of opening a second socket.
    final inFlight = _connectFutures[deviceId];
    if (inFlight != null) return inFlight;

    final future = _connectToPeerInternal(
      deviceId,
      onMessage: onMessage,
      onError: onError,
      onDisconnected: onDisconnected,
    );
    _connectFutures[deviceId] = future;
    unawaited(future.whenComplete(() => _connectFutures.remove(deviceId)));
    return future;
  }

  Future<TcpPeerConnection> _connectToPeerInternal(
    String deviceId, {
    Function(Map<String, dynamic>)? onMessage,
    Function(Object)? onError,
    Function()? onDisconnected,
  }) async {
    final peer = getPeer(deviceId);
    if (peer == null) {
      throw StateError("Peer $deviceId not found");
    }

    final response = Completer<bool>();

    late final TcpPeerConnection conn;

    conn = TcpPeerConnection(
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
        if (type == 'save_request') {
          final name = msg['name'] as String? ?? deviceId;
          handleIncomingSaveRequest(deviceId, name, conn);
          return;
        }
        if (type == 'save_response') {
          handleSaveResponse(deviceId, msg['accepted'] as bool? ?? false);
          return;
        }
        onMessage?.call(msg);
      },
      onError: onError,
      onDisconnected: () {
        if (!response.isCompleted) response.complete(false);
        // Only clear the map entry if it's still pointing at *this*
        // socket — a glare-losing connection can disconnect after a
        // different (winning) connection has already taken its place.
        if (_tcpConnections[deviceId] == conn) {
          _tcpConnections.remove(deviceId);
        }
        onDisconnected?.call();
        notifyListeners();
      },
    );

    // Tracked from the moment we start dialing until we know the outcome,
    // so an incoming request for the same peer arriving in the meantime
    // (both sides connecting at once) can find and resolve against it.
    _pendingOutbound[deviceId] = conn;
    try {
      // "Connection refused" right after a peer's app starts is common —
      // its TCP server may not have finished starting yet even though it
      // already answered UDP discovery. A couple of quick retries clears
      // that up without making the caller wait for the full 60s
      // background retry.
      await _connectWithRetry(conn);

      conn.send({'type': 'request', 'deviceId': userId, 'name': userName});

      final accepted = await response.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );

      if (!accepted) {
        await conn.disconnect();

        // We may have lost a glare race: the peer's own connection attempt
        // to us could have been accepted (and adopted into _tcpConnections)
        // while we were waiting on this dial. If so, we ARE connected from
        // the caller's point of view — just not via the socket we
        // personally opened — so report success instead of failure.
        final adopted = _tcpConnections[deviceId];
        if (adopted != null && adopted.isConnected) {
          return adopted;
        }

        throw StateError("Connection request was declined or timed out");
      }

      _tcpConnections[deviceId] = conn;
      notifyListeners();
      return conn;
    } finally {
      _pendingOutbound.remove(deviceId);
    }
  }

  /// Dials [conn], retrying a few times with a short, growing delay if the
  /// OS reports "connection refused" — usually just means the remote
  /// device's TCP server hasn't finished starting yet, not a real failure.
  /// Anything else (bad certificate, timeout, etc.) is not retried here,
  /// since retrying wouldn't help and — for a certificate mismatch —
  /// could mask something the user needs to see right away.
  Future<void> _connectWithRetry(
    TcpPeerConnection conn, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 400),
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await conn.connect();
        return;
      } on SocketException catch (e) {
        if (attempt == maxAttempts) rethrow;
        log("TCP connect attempt $attempt to ${conn.deviceId ?? conn.ip} "
            "refused ($e) — retrying...");
        await Future.delayed(initialDelay * attempt);
      }
    }
  }

  /// Whether we currently have an outbound dial in flight to [deviceId]
  /// (sent but not yet accepted/rejected). Used to detect connection
  /// glare — both sides trying to connect to each other at once.
  bool hasPendingOutboundTo(String deviceId) => _pendingOutbound.containsKey(deviceId);

  /// Cancels our own in-flight outbound dial to [deviceId] — e.g. because
  /// we lost a glare race and are accepting their incoming connection
  /// instead. Safe to call even if there's no pending dial.
  void abandonPendingOutbound(String deviceId) {
    _pendingOutbound.remove(deviceId)?.disconnect();
  }

  /// Deterministic glare tie-break for when both sides try to connect to
  /// each other at the same time (common right after two devices with a
  /// saved connection both start up, but can also happen with manual
  /// taps). Exactly one direction should win, or both ends end up with
  /// duplicate sockets that fight over which gets torn down.
  ///
  /// The side with the lexicographically smaller deviceId always wins as
  /// the initiator. Both sides compare the very same two IDs, so they
  /// independently agree on the outcome without needing to negotiate.
  bool shouldYieldTo(String otherDeviceId) {
    final myId = userId;
    if (myId == null) return false;
    return myId.compareTo(otherDeviceId) > 0;
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

  // ---------------------------------------------------------------------
  // Saved connections
  // ---------------------------------------------------------------------

  /// Loads previously saved connections from disk, makes them visible in
  /// [peers] (even before UDP rediscovers them) and kicks off a
  /// best-effort auto-reconnect to each one's last known address.
  ///
  /// Call once at startup, after the TCP server has started listening.
  Future<void> loadSavedPeers() async {
    await SavedPeersStore().ensureLoaded();
    savedPeers
      ..clear()
      ..addEntries(SavedPeersStore().all.map((p) => MapEntry(p.deviceId, p)));

    for (final saved in savedPeers.values) {
      peers.putIfAbsent(
        saved.deviceId,
        () => PeerData(
          deviceId: saved.deviceId,
          name: saved.name,
          ip: saved.lastKnownIp,
          port: saved.lastKnownPort,
          lastSeen: saved.savedAt,
        ),
      );
    }
    notifyListeners();

    for (final deviceId in savedPeers.keys) {
      _maybeAutoReconnectSaved(deviceId);
    }
  }

  /// Asks the currently-connected peer [deviceId] to save the connection.
  /// Returns whether they accepted. Persists locally on acceptance.
  Future<bool> requestSaveConnection(String deviceId) async {
    final conn = _tcpConnections[deviceId];
    if (conn == null || !conn.isConnected) {
      throw StateError("Not connected to $deviceId");
    }

    final completer = Completer<bool>();
    _pendingSaveRequests[deviceId] = completer;

    conn.send({'type': 'save_request', 'deviceId': userId, 'name': userName});

    bool accepted;
    try {
      accepted = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
    } finally {
      _pendingSaveRequests.remove(deviceId);
    }

    if (accepted) {
      await _persistSavedPeer(deviceId, ip: conn.ip, port: conn.port);
    }

    return accepted;
  }

  /// Removes a saved connection. It stays connected/discoverable as a
  /// normal peer, it just won't be remembered or auto-reconnected anymore.
  Future<void> forgetSavedPeer(String deviceId) async {
    savedPeers.remove(deviceId);
    await SavedPeersStore().remove(deviceId);
    notifyListeners();
  }

  /// Called (from either the client-connect or server-accept message
  /// handlers) when the remote side sends a 'save_request'. Surfaces
  /// [onSaveRequest] to the UI and replies over [conn] once the user
  /// responds.
  void handleIncomingSaveRequest(
    String deviceId,
    String name,
    TcpPeerConnection conn,
  ) {
    final handler = onSaveRequest;
    if (handler == null) {
      conn.send({'type': 'save_response', 'accepted': false});
      return;
    }

    handler(deviceId, name, (userSaidYes) {
      conn.send({'type': 'save_response', 'accepted': userSaidYes});
      if (userSaidYes) {
        unawaited(_persistSavedPeer(deviceId, name: name, ip: conn.ip, port: conn.port));
      }
    });
  }

  /// Called when the remote side replies to our own save_request.
  void handleSaveResponse(String deviceId, bool accepted) {
    final completer = _pendingSaveRequests[deviceId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(accepted);
    }
  }

  Future<void> _persistSavedPeer(
    String deviceId, {
    String? name,
    String? ip,
    int? port,
  }) async {
    final peer = getPeer(deviceId);
    final saved = SavedPeer(
      deviceId: deviceId,
      name: name ?? peer?.name ?? deviceId,
      lastKnownIp: ip ?? peer?.ip ?? '',
      lastKnownPort: port ?? peer?.port ?? 0,
      savedAt: DateTime.now(),
    );
    savedPeers[deviceId] = saved;
    await SavedPeersStore().save(saved);
    notifyListeners();
  }

  void _maybeAutoReconnectSaved(String deviceId) {
    final conn = _tcpConnections[deviceId];
    if (conn != null && conn.isConnected) return;

    final last = _lastAutoConnectAttempt[deviceId];
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _lastAutoConnectAttempt[deviceId] = DateTime.now();
    unawaited(_autoConnectSaved(deviceId));
  }

  Future<void> _autoConnectSaved(String deviceId) async {
    try {
      await connectToPeer(deviceId);
      log("Auto-connected to saved peer $deviceId");
    } catch (e) {
      log("Auto-connect to saved peer $deviceId failed: $e");
    }
  }
}