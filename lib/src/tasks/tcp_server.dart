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

    // NOTE on incoming-connection identity: we intentionally do NOT set
    // requestClientCertificate here. Dart's TLS stack verifies any client
    // certificate that is presented against the server's trusted roots as
    // soon as it's requested — even with requireClientCertificate: false —
    // and since every device's certificate is self-signed with no shared
    // CA, that verification always fails and aborts the whole handshake
    // (confirmed via CERTIFICATE_VERIFY_FAILED in testing). Mutual TLS
    // with self-signed, dynamically-trusted (TOFU) certificates isn't
    // something the current API supports without pre-provisioning every
    // peer's certificate as trusted ahead of time, which would defeat the
    // point of trust-on-first-use.
    //
    // So: the outbound direction (this device connecting to a peer) is
    // cryptographically verified via PeerTrustStore in tcp_connection.dart.
    // The inbound direction (a peer connecting to us) is not — the
    // deviceId in the 'request' message is an unauthenticated claim, and
    // the only real gate on it is the user's manual accept/decline in the
    // connection-request dialog. That's a real limitation, not a full
    // fix, and should be called out as such (e.g. in the thesis writeup)
    // rather than presented as symmetric protection.
    _server = await SecureServerSocket.bind(InternetAddress.anyIPv4, port, context);
    log("TCP server listening on port $port");

    _subscription = _server!.listen(
      _handleIncoming,
      onError: (Object e) => log("TCP server error: $e"),
    );
  }

  void _handleIncoming(SecureSocket socket) {
    late final TcpPeerConnection conn;
    bool accepted = false;

    conn = TcpPeerConnection.fromSocket(
      socket: socket,
      onMessage: (msg) {
        final type = msg['type'];

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

          // Saved peers skip the manual accept/decline dialog entirely —
          // both sides already agreed to trust each other when they saved
          // one another, so re-prompting on every reconnect would defeat
          // the point of saving in the first place.
          if (SessionData().isPeerSaved(incomingId)) {
            accepted = true;
            conn.send({'type': 'accept', 'deviceId': SessionData().userId, 'name': SessionData().userName});
            SessionData().registerIncomingConnection(incomingId, conn);
            log("Auto-accepted connection from saved peer $incomingName ($incomingId)");
            return;
          }

          final handler = SessionData().onIncomingRequest;
          if (handler == null) {
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

        // Everything post-handshake (chat, save, file transfer messages,
        // and anything added later) goes through the same dispatcher the
        // outbound connection side uses, so the protocol only needs to be
        // implemented once.
        SessionData().handlePeerMessage(conn.deviceId!, msg);
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