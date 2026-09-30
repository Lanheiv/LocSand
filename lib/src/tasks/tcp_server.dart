import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:locsand/src/helpers/tls_context.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';
import 'package:locsand/src/data/session_data.dart';

class TcpPeerServer {
  final int port;
  SecureServerSocket? _server;

  TcpPeerServer({required this.port});

  Future<void> start() async {
    if (_server != null) return;

    final context = await TlsContext.serverContext();

    _server = await SecureServerSocket.bind(InternetAddress.anyIPv4, port, context);
    log("TCP server listening on port $port");

    _server!.listen(
      _handleIncoming,
      onError: (Object e) => log("TCP server error: $e"),
    );
  }

  void _handleIncoming(SecureSocket socket) {
    late final TcpPeerConnection conn;
    bool accepted = false;

    Timer? requestTimer = Timer(const Duration(seconds: 15), () {
      if (!accepted) conn.disconnect();
    });

    bool trySend(Map<String, dynamic> message) {
      try {
        conn.send(message);
        return true;
      } catch (e) {
        log("Could not reach ${conn.deviceId ?? conn.ip}: $e");
        return false;
      }
    }

    bool acceptPeer(String incomingId, String incomingName) {
      final sent = trySend({
        'type': 'accept',
        'deviceId': SessionData().userId,
        'name': SessionData().userName,
      });
      if (!sent) return false;
      accepted = true;
      SessionData().registerIncomingConnection(incomingId, conn);
      return true;
    }

    conn = TcpPeerConnection.fromSocket(
      socket: socket,
      onMessage: (msg) {
        final type = msg['type'];

        if (!accepted) {
          if (type != 'request') {
            log("Ignoring message before a connection request: $msg");
            return;
          }
          requestTimer?.cancel();
          requestTimer = null;

          final incomingId = msg['deviceId'] as String?;
          var incomingName = msg['name'] as String? ?? incomingId ?? 'Unknown device';
          if (incomingName.length > 64) incomingName = incomingName.substring(0, 64);
          if (incomingId == null || incomingId.isEmpty || incomingId.length > 128) {
            log("Connection request had no valid deviceId — dropping it");
            conn.disconnect();
            return;
          }
          conn.deviceId = incomingId;

          if (SessionData().isPeerSaved(incomingId)) {
            if (acceptPeer(incomingId, incomingName)) {
              log("Auto-accepted connection from saved peer $incomingName ($incomingId)");
            }
            return;
          }

          final handler = SessionData().onIncomingRequest;
          if (handler == null) {
            trySend({'type': 'reject'});
            conn.disconnect();
            return;
          }

          handler(incomingId, incomingName, (userSaidYes) {
            if (userSaidYes) {
              if (acceptPeer(incomingId, incomingName)) {
                log("Accepted connection from $incomingName ($incomingId)");
              }
            } else {
              trySend({'type': 'reject'});
              conn.disconnect();
              log("Declined connection from $incomingName ($incomingId)");
            }
          });
          return;
        }

        SessionData().handlePeerMessage(conn.deviceId!, msg);
      },
      onDisconnected: () {
        requestTimer?.cancel();
        requestTimer = null;
        if (conn.deviceId != null) {
          SessionData().disconnectFromPeer(
            conn.deviceId!,
            closeSocket: false,
            ifCurrent: conn,
          );
        }
      },
    );
  }
}
