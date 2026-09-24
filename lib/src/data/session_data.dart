import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/chat_message.dart';
import 'package:locsand/src/data/saved_peer.dart';
import 'package:locsand/src/data/file_transfer.dart';
import 'package:locsand/src/helpers/peer_store.dart';
import 'package:locsand/src/helpers/chat_history_store.dart';
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

  /// Starts periodically removing peers whose last UDP broadcast is older
  /// than [staleAfter]. Without this, a peer that goes offline (closes the
  /// app, leaves the network) stays in the list forever, since `lastSeen`
  /// is only ever updated, never checked.
  ///
  /// A peer with a currently open TCP connection is never pruned just
  /// because its discovery broadcasts stopped — an active chat shouldn't
  /// be yanked out from under the user due to a missed UDP packet.
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

  // ---- Saved peers -------------------------------------------------
  //
  // "Discovered" peers (in `peers`, above) only exist while the device is
  // actually broadcasting on the network right now. Saving a peer keeps a
  // separate, persistent record of it (see SavedPeersStore) so it's still
  // listed after the app restarts, shows whether it's currently online,
  // and is auto-connected to / auto-accepted without a manual prompt once
  // both sides have saved each other.

  /// Loads the persisted saved-peers list. Call once during app startup,
  /// before relying on [isPeerSaved] elsewhere.
  Future<void> loadSavedPeers() async {
    await SavedPeersStore().ensureLoaded();
    notifyListeners();
  }

  List<SavedPeer> get allSavedPeers => SavedPeersStore().all;

  bool isPeerSaved(String deviceId) => SavedPeersStore().isSaved(deviceId);

  /// A saved (or discovered) peer is "online" if it's either currently
  /// broadcasting on the network or we have a live TCP connection to it.
  bool isPeerOnline(String deviceId) {
    final conn = _tcpConnections[deviceId];
    if (conn != null && conn.isConnected) return true;
    return peers.containsKey(deviceId);
  }

  /// Called when the user presses "Save" on a peer they're connected to.
  /// Saves the peer locally right away, and — if there's a live
  /// connection — asks the other side to save us back, so the pairing
  /// works both ways without either person having to press anything twice.
  Future<void> savePeer(String deviceId) async {
    final peer = peers[deviceId];
    final name = peer?.name ?? deviceId;

    await SavedPeersStore().save(
      deviceId,
      name,
      lastKnownIp: peer?.ip ?? '',
      lastKnownPort: peer?.port ?? 0,
    );

    final conn = _tcpConnections[deviceId];
    if (conn != null && conn.isConnected) {
      conn.send({'type': 'save', 'deviceId': userId, 'name': userName});
    }
    notifyListeners();
  }

  Future<void> forgetSavedPeer(String deviceId) async {
    await SavedPeersStore().remove(deviceId);
    notifyListeners();
  }

  /// Called when a `'save'` message arrives from a peer — they've saved
  /// us, so we save them back automatically. No confirmation dialog: this
  /// mirrors what the other side already knows the user just did on
  /// purpose (pressed Save while actively connected to them).
  ///
  /// Prefers the live connection's address (most current) and falls back
  /// to the discovered-peer entry if that's somehow unset.
  Future<void> markPeerSaved(String deviceId, String name) async {
    final conn = _tcpConnections[deviceId];
    final peer = peers[deviceId];
    await SavedPeersStore().save(
      deviceId,
      name,
      lastKnownIp: conn?.ip ?? peer?.ip ?? '',
      lastKnownPort: conn?.port ?? peer?.port ?? 0,
    );
    notifyListeners();
  }

  void clear() {
    userId = null;
    userName = null;
    userIp = null;
    userOnlineTime = null;
    peers.clear();
    chatMessages.clear();

    for (final sink in _incomingSinks.values) {
      sink.close();
    }
    _incomingSinks.clear();
    fileTransfers.clear();

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

    // A saved peer doesn't need the user to tap it manually — if we just
    // found it on the network and aren't already talking to it, connect
    // in the background. The server side skips the accept dialog for
    // saved peers too (see TcpPeerServer), so this completes silently.
    final existing = _tcpConnections[peer.deviceId];
    if (isPeerSaved(peer.deviceId) && (existing == null || !existing.isConnected)) {
      unawaited(_autoConnectSavedPeer(peer.deviceId));
    }
  }

  Future<void> _autoConnectSavedPeer(String deviceId) async {
    try {
      await connectToPeer(deviceId);
    } catch (e) {
      // Best-effort — the peer might reject us, be mid-handshake with a
      // stale cert, or simply not be ready yet. Discovery will retry on
      // the next broadcast.
    }
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
        handlePeerMessage(deviceId, msg);
        onMessage?.call(msg);
      },
      onError: onError,
      onDisconnected: () {
        if (!response.isCompleted) response.complete(false);
        _tcpConnections.remove(deviceId);
        _failInProgressTransfers(deviceId);
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

  /// Dispatches a message that arrived over an already-established
  /// connection (i.e. after the initial accept/reject handshake). Used by
  /// both the outbound (connectToPeer) and inbound (TcpPeerServer) message
  /// handlers so the chat/save/file-transfer protocol only needs to be
  /// implemented once.
  void handlePeerMessage(String deviceId, Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'chat':
        receiveChatMessage(deviceId, msg['text'] as String? ?? '');
        break;
      case 'save':
        markPeerSaved(deviceId, msg['name'] as String? ?? deviceId);
        break;
      case 'file_offer':
        _handleFileOffer(deviceId, msg);
        break;
      case 'file_accept':
        _handleFileAccept(deviceId, msg);
        break;
      case 'file_decline':
        _handleFileDecline(deviceId, msg);
        break;
      case 'file_chunk':
        _handleFileChunk(deviceId, msg);
        break;
      case 'file_complete':
        _handleFileComplete(deviceId, msg);
        break;
      default:
        break;
    }
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
    _failInProgressTransfers(deviceId);
    notifyListeners();
  }

  List<ChatMessage> getChatMessages(String deviceId) => chatMessages[deviceId] ?? [];

  void receiveChatMessage(String deviceId, String text) {
    chatMessages.putIfAbsent(deviceId, () => []).add(
          ChatMessage(text: text, fromMe: false, time: DateTime.now()),
        );
    notifyListeners();
    unawaited(ChatHistoryStore().saveIfEnabled(deviceId, getChatMessages(deviceId)));
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
    unawaited(ChatHistoryStore().saveIfEnabled(deviceId, getChatMessages(deviceId)));
  }

  // ---- Saved chat history ---------------------------------------------
  //
  // `chatMessages`, above, is in-memory only, so on its own it disappears
  // on sign-out or app restart. Saving to disk is opt-in per peer: the
  // user turns it on explicitly (see [setChatHistorySaving]), and only
  // then does every later sent/received message also get written to disk
  // via ChatHistoryStore. Turning it off stops future messages from being
  // saved but leaves whatever's already on disk in place; deleting (see
  // [deleteChatHistory]) removes the save and turns saving off together,
  // in one step, since there's then nothing left to have an opinion on.

  /// Whether history saving is currently turned on for [deviceId].
  Future<bool> isChatHistorySavingEnabled(String deviceId) =>
      ChatHistoryStore().isEnabled(deviceId);

  /// Turns history saving on or off for [deviceId]. Turning it on saves
  /// the conversation as it stands right now, so nothing already said is
  /// lost once saving starts.
  Future<void> setChatHistorySaving(String deviceId, bool enabled) async {
    await ChatHistoryStore().setEnabled(deviceId, enabled, getChatMessages(deviceId));
  }

  /// Loads the on-disk history for [deviceId] into memory if nothing is
  /// there yet (e.g. right after opening a chat screen following an app
  /// restart). Does nothing if messages for this peer are already loaded,
  /// so it never clobbers the live conversation with a stale save.
  Future<void> ensureChatHistoryLoaded(String deviceId) async {
    if (chatMessages.containsKey(deviceId)) return;
    final messages = await ChatHistoryStore().load(deviceId);
    if (messages.isEmpty) return;
    chatMessages[deviceId] = messages;
    notifyListeners();
  }

  /// Deletes the conversation with [deviceId] everywhere: the in-memory
  /// list (so it disappears from the chat screen immediately) and the
  /// on-disk save (so it doesn't come back the next time the app starts,
  /// and history saving goes back to being off for this peer).
  Future<void> deleteChatHistory(String deviceId) async {
    chatMessages.remove(deviceId);
    notifyListeners();
    await ChatHistoryStore().deleteFile(deviceId);
  }

  // ---- File transfer -------------------------------------------------
  //
  // Files are streamed directly over the existing peer TCP/TLS connection
  // rather than via a separate HTTP server + link: chunks are read from
  // disk one at a time (never the whole file in memory), base64-encoded,
  // and sent as JSON lines using the same protocol as chat messages. This
  // reuses the connection's existing TOFU-authenticated channel instead of
  // opening a new, unauthenticated port.
  //
  // Known limitations (acceptable for LAN chat use, worth calling out
  // explicitly rather than solving): no resume after a dropped connection
  // — a failed transfer must be restarted from scratch — and no
  // pre-transfer disk-space check. Very large files (many GB) will be slow
  // due to base64 + JSON-line overhead; this is designed for documents and
  // photos, not bulk file transfer.

  // transferId -> transfer
  final Map<String, FileTransfer> fileTransfers = {};

  // transferId -> open sink for an incoming file currently being written
  final Map<String, IOSink> _incomingSinks = {};

  /// UI hook for incoming file offers, mirroring [onIncomingRequest]. A
  /// file offer always requires an explicit decision — unlike connection
  /// requests, it is never auto-accepted for saved peers, since accepting
  /// writes arbitrary data to the device's storage.
  void Function(FileTransfer transfer, void Function(bool accept) respond)?
      onIncomingFileOffer;

  List<FileTransfer> fileTransfersFor(String deviceId) => fileTransfers.values
      .where((t) => t.deviceId == deviceId)
      .toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  String _newTransferId() =>
      '${userId ?? 'me'}-${DateTime.now().microsecondsSinceEpoch}';

  /// Offers [file] to [deviceId]. The offer is sent immediately; the
  /// actual byte streaming only starts once (and if) the other side
  /// responds with 'file_accept' — see [_handleFileAccept].
  Future<FileTransfer> sendFile(String deviceId, File file) async {
    final conn = _tcpConnections[deviceId];
    if (conn == null || !conn.isConnected) {
      throw StateError("Not connected to $deviceId");
    }

    final size = await file.length();
    final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'file';
    final transfer = FileTransfer(
      transferId: _newTransferId(),
      deviceId: deviceId,
      name: name,
      size: size,
      direction: FileTransferDirection.outgoing,
      startedAt: DateTime.now(),
      localPath: file.path,
    );

    fileTransfers[transfer.transferId] = transfer;
    notifyListeners();

    conn.send({
      'type': 'file_offer',
      'transferId': transfer.transferId,
      'name': name,
      'size': size,
    });

    return transfer;
  }

  void _handleFileOffer(String deviceId, Map<String, dynamic> msg) {
    final transferId = msg['transferId'] as String?;
    final name = msg['name'] as String?;
    final size = msg['size'] as int?;
    if (transferId == null || name == null || size == null || size < 0) return;

    final transfer = FileTransfer(
      transferId: transferId,
      deviceId: deviceId,
      name: name,
      size: size,
      direction: FileTransferDirection.incoming,
      startedAt: DateTime.now(),
    );
    fileTransfers[transferId] = transfer;
    notifyListeners();

    final handler = onIncomingFileOffer;
    if (handler == null) {
      // Nobody is listening for offers right now (e.g. app in a weird
      // state) — decline rather than leaving the sender hanging until it
      // times out on its own.
      _declineIncomingFile(transfer);
      return;
    }

    handler(transfer, (userAccepted) {
      if (userAccepted) {
        unawaited(_acceptIncomingFile(transfer));
      } else {
        _declineIncomingFile(transfer);
      }
    });
  }

  Future<void> _acceptIncomingFile(FileTransfer transfer) async {
    final conn = _tcpConnections[transfer.deviceId];
    if (conn == null || !conn.isConnected) {
      transfer.status = FileTransferStatus.failed;
      notifyListeners();
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = _uniqueFile(dir, _sanitizeFileName(transfer.name));
      transfer.localPath = file.path;
      _incomingSinks[transfer.transferId] = file.openWrite();
      transfer.status = FileTransferStatus.inProgress;
      notifyListeners();

      conn.send({'type': 'file_accept', 'transferId': transfer.transferId});
    } catch (e) {
      transfer.status = FileTransferStatus.failed;
      notifyListeners();
    }
  }

  void _declineIncomingFile(FileTransfer transfer) {
    transfer.status = FileTransferStatus.declined;
    notifyListeners();
    _tcpConnections[transfer.deviceId]?.send({
      'type': 'file_decline',
      'transferId': transfer.transferId,
    });
  }

  void _handleFileAccept(String deviceId, Map<String, dynamic> msg) {
    final transfer = fileTransfers[msg['transferId'] as String?];
    if (transfer == null || transfer.direction != FileTransferDirection.outgoing) return;

    transfer.status = FileTransferStatus.inProgress;
    notifyListeners();
    unawaited(_streamFile(transfer));
  }

  void _handleFileDecline(String deviceId, Map<String, dynamic> msg) {
    final transfer = fileTransfers[msg['transferId'] as String?];
    if (transfer == null) return;
    transfer.status = FileTransferStatus.declined;
    notifyListeners();
  }

  Future<void> _streamFile(FileTransfer transfer) async {
    final file = File(transfer.localPath!);

    try {
      await for (final chunk in file.openRead()) {
        final conn = _tcpConnections[transfer.deviceId];
        if (conn == null || !conn.isConnected) {
          throw StateError("Connection lost during transfer");
        }

        conn.send({
          'type': 'file_chunk',
          'transferId': transfer.transferId,
          'data': base64Encode(chunk),
        });

        transfer.bytesTransferred += chunk.length;
        notifyListeners();

        // Yield to the event loop between chunks instead of writing the
        // whole file synchronously back-to-back, so a slow connection
        // doesn't pile everything into the socket's internal buffer at
        // once.
        await Future.delayed(Duration.zero);
      }

      final conn = _tcpConnections[transfer.deviceId];
      conn?.send({'type': 'file_complete', 'transferId': transfer.transferId});
      transfer.status = FileTransferStatus.completed;
      notifyListeners();
    } catch (e) {
      transfer.status = FileTransferStatus.failed;
      notifyListeners();
    }
  }

  void _handleFileChunk(String deviceId, Map<String, dynamic> msg) {
    final transferId = msg['transferId'] as String?;
    final data = msg['data'] as String?;
    final transfer = fileTransfers[transferId];
    final sink = _incomingSinks[transferId];
    if (transfer == null || sink == null || data == null) return;

    try {
      final bytes = base64Decode(data);
      sink.add(bytes);
      transfer.bytesTransferred += bytes.length;
      notifyListeners();
    } catch (e) {
      transfer.status = FileTransferStatus.failed;
      unawaited(sink.close());
      _incomingSinks.remove(transferId);
      notifyListeners();
    }
  }

  Future<void> _handleFileComplete(String deviceId, Map<String, dynamic> msg) async {
    final transferId = msg['transferId'] as String?;
    final transfer = fileTransfers[transferId];
    final sink = _incomingSinks.remove(transferId);
    if (transfer == null) return;

    await sink?.close();
    transfer.status = FileTransferStatus.completed;
    notifyListeners();
  }

  void _failInProgressTransfers(String deviceId) {
    var changed = false;
    for (final transfer in fileTransfers.values) {
      if (transfer.deviceId == deviceId &&
          (transfer.status == FileTransferStatus.inProgress ||
              transfer.status == FileTransferStatus.offered)) {
        transfer.status = FileTransferStatus.failed;
        final sink = _incomingSinks.remove(transfer.transferId);
        sink?.close();
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Strips any path component from a peer-supplied file name and drops
  /// characters outside a safe set. The name in a `file_offer` message
  /// comes from another device and must never be used to build a file
  /// path directly — a name like `../../secrets.txt` would otherwise let
  /// a peer write outside the intended downloads folder.
  String _sanitizeFileName(String rawName) {
    final segments = rawName.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
    final base = segments.isEmpty ? 'received_file' : segments.last;
    final sanitized = base.replaceAll(RegExp(r'[^A-Za-z0-9._\- ]'), '_').trim();
    return sanitized.isEmpty ? 'received_file' : sanitized;
  }

  /// Returns a File in [dir] for [name], appending " (1)", " (2)", etc. if
  /// a file with that name already exists, so an incoming transfer never
  /// silently overwrites an existing file.
  File _uniqueFile(Directory dir, String name) {
    var candidate = File('${dir.path}/$name');
    if (!candidate.existsSync()) return candidate;

    final dotIndex = name.lastIndexOf('.');
    final base = dotIndex > 0 ? name.substring(0, dotIndex) : name;
    final ext = dotIndex > 0 ? name.substring(dotIndex) : '';

    var i = 1;
    do {
      candidate = File('${dir.path}/$base ($i)$ext');
      i++;
    } while (candidate.existsSync());

    return candidate;
  }
}