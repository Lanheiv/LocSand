// src/tasks/tcp_server.dart
//
// Listens for incoming encrypted connections. When someone connects and
// sends a "request", we don't just let them in — we ask the app (via
// SessionData().onIncomingRequest) whether to accept them first.

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:locsand/src/helpers/tls_context.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';
import 'package:locsand/src/data/session_data.dart';

class TcpPeerServer {
  final int port;
  SecureServerSocket? _server;
  StreamSubscription<SecureSocket>? _subscription;

  TcpPeerServer({required this.port});

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;

    final context = await TlsContext.serverContext();
    _server = await SecureServerSocket.bind(InternetAddress.anyIPv4, port, context);
    log("TCP (TLS) server listening on port $port");

    _subscription = _server!.listen(
      _handleIncoming,
      onError: (Object e) => log("TCP server error: $e"),
    );
  }

  void _handleIncoming(SecureSocket socket) {
    late final TcpPeerConnection conn;
    bool accepted = false; // becomes true only after the app says yes

    conn = TcpPeerConnection.fromSocket(
      socket: socket,
      onMessage: (msg) {
        final type = msg['type'];

        // First message must be a connection request.
        if (!accepted) {
          if (type != 'request') {
            log("Ignoring message before a connection request: $msg");
            return;
          }

          final incomingId = msg['deviceId'] as String?;
          final incomingName = msg['name'] as String? ?? incomingId ?? 'Unknown device';
          if (incomingId == null) {
            log("Connection request had no deviceId — dropping it");
            conn.disconnect();
            return;
          }
          conn.deviceId = incomingId;

          final handler = SessionData().onIncomingRequest;
          if (handler == null) {
            // Nobody is listening for requests — refuse by default.
            conn.send({'type': 'reject'});
            conn.disconnect();
            return;
          }

          handler(incomingId, incomingName, (userSaidYes) {
            if (userSaidYes) {
              accepted = true;
              conn.send({'type': 'accept', 'deviceId': SessionData().userId, 'name': SessionData().userName});
              SessionData().registerIncomingConnection(incomingId, conn);
              log("Accepted connection from $incomingName ($incomingId)");
            } else {
              conn.send({'type': 'reject'});
              conn.disconnect();
              log("Declined connection from $incomingName ($incomingId)");
            }
          });
          return;
        }

        // Already accepted — this is a normal application message.
        log("Message from ${conn.deviceId}: $msg");
      },
      onDisconnected: () {
        if (conn.deviceId != null) {
          SessionData().disconnectFromPeer(conn.deviceId!, closeSocket: false);
        }
      },
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    await _server?.close();
    _server = null;
  }
}
