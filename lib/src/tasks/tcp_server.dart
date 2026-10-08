import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/helpers/auth_protocol.dart';
import 'package:locsand/src/helpers/device_identity.dart';
import 'package:locsand/src/helpers/tls_context.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

/// Accepts incoming TLS connections.
///
/// Handshake on top of TLS (all frames are JSON lines):
///   client -> hello      {deviceId, name, pub, nonce}
///   server -> challenge  {deviceId, pub, nonce, sig}   sig = server signature
///   client -> request    {sig}                         sig = client signature
/// Both signatures cover both ids, both nonces and the hash of the server's
/// TLS certificate. Only after the client's signature verifies is the claimed
/// device id believed - and only then may a saved peer be auto-accepted.
class TcpPeerServer {
  static const Duration _authTimeout = Duration(seconds: 15);
  static const Duration _userDecisionTimeout = Duration(seconds: 60);
  static const int _maxPreAuth = 16;
  static const int _maxPreAuthPerIp = 4;
  static const int _maxPendingPrompts = 3;

  final int port;
  SecureServerSocket? _server;
  DeviceIdentity? _identity;

  int _preAuth = 0;
  final Map<String, int> _preAuthByIp = {};
  int _pendingPrompts = 0;
  final Set<String> _promptIps = {};

  TcpPeerServer({required this.port});

  Future<void> start() async {
    if (_server != null) return;

    _identity = await DeviceIdentity.load();
    final context = await TlsContext.serverContext();

    _server = await SecureServerSocket.bind(InternetAddress.anyIPv4, port, context);
    log("TCP server listening on port $port");

    _server!.listen(
      _handleIncoming,
      onError: (Object e) => log("TCP server error: $e"),
    );
  }

  void _handleIncoming(SecureSocket socket) {
    final identity = _identity!;
    final ip = socket.remoteAddress.address;

    if (_preAuth >= _maxPreAuth || (_preAuthByIp[ip] ?? 0) >= _maxPreAuthPerIp) {
      socket.destroy();
      return;
    }
    _preAuth++;
    _preAuthByIp[ip] = (_preAuthByIp[ip] ?? 0) + 1;

    var preAuthReleased = false;
    void releasePreAuth() {
      if (preAuthReleased) return;
      preAuthReleased = true;
      _preAuth--;
      final left = (_preAuthByIp[ip] ?? 1) - 1;
      if (left <= 0) {
        _preAuthByIp.remove(ip);
      } else {
        _preAuthByIp[ip] = left;
      }
    }

    var promptHeld = false;
    void releasePrompt() {
      if (!promptHeld) return;
      promptHeld = false;
      _pendingPrompts--;
      _promptIps.remove(ip);
    }

    late final TcpPeerConnection conn;
    bool accepted = false;
    var stage = 0; // 0: expect hello, 1: expect request, 2: authenticated
    var claimedId = '';
    var claimedPub = '';
    var claimedName = '';
    var clientNonce = '';
    var serverNonce = '';
    Timer? authTimer;
    Timer? decisionTimer;

    void cleanup() {
      authTimer?.cancel();
      authTimer = null;
      decisionTimer?.cancel();
      decisionTimer = null;
      releasePreAuth();
      releasePrompt();
    }

    void closeConn() {
      cleanup();
      unawaited(conn.disconnect());
    }

    authTimer = Timer(_authTimeout, () {
      if (!accepted && stage < 2) closeConn();
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

    bool acceptPeer(String incomingId) {
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

    void askUser() {
      final handler = SessionData().onIncomingRequest;
      if (handler == null ||
          _pendingPrompts >= _maxPendingPrompts ||
          _promptIps.contains(ip)) {
        trySend({'type': 'reject'});
        closeConn();
        return;
      }
      _pendingPrompts++;
      _promptIps.add(ip);
      promptHeld = true;

      decisionTimer = Timer(_userDecisionTimeout, () {
        trySend({'type': 'reject'});
        closeConn();
      });

      final shown = '$claimedName  (ID ${shortDeviceId(claimedId)})';
      handler(claimedId, shown, (userSaidYes) {
        decisionTimer?.cancel();
        decisionTimer = null;
        releasePrompt();
        if (userSaidYes) {
          if (acceptPeer(claimedId)) {
            log("Accepted connection from $claimedName ($claimedId)");
          }
        } else {
          trySend({'type': 'reject'});
          closeConn();
          log("Declined connection from $claimedName ($claimedId)");
        }
      });
    }

    void onHello(Map<String, dynamic> msg) {
      final id = msg['deviceId'];
      final pub = msg['pub'];
      final nonce = msg['nonce'];
      final name = msg['name'];
      if (id is! String ||
          pub is! String ||
          nonce is! String ||
          !deviceIdPattern.hasMatch(id) ||
          pub.length > 1024 ||
          nonce.length < 16 ||
          nonce.length > 64 ||
          id == identity.deviceId ||
          deviceIdFromPublicKey(pub) != id) {
        log("Invalid hello from $ip - dropping connection");
        closeConn();
        return;
      }
      var cleaned = (name is String ? name : '').replaceAll(RegExp(r'[\x00-\x1f]'), ' ').trim();
      if (cleaned.length > 64) cleaned = cleaned.substring(0, 64);

      claimedId = id;
      claimedPub = pub;
      claimedName = cleaned.isEmpty ? shortDeviceId(id) : cleaned;
      clientNonce = nonce;
      serverNonce = newNonce();

      final signature = identity.sign(authTranscript(
        role: 'server',
        clientId: claimedId,
        serverId: identity.deviceId,
        clientNonce: clientNonce,
        serverNonce: serverNonce,
        serverCertDer: identity.certDer,
      ));
      trySend({
        'type': 'challenge',
        'deviceId': identity.deviceId,
        'pub': identity.publicKeyPem,
        'nonce': serverNonce,
        'sig': base64Encode(signature),
      });
      stage = 1;
    }

    void onRequest(Map<String, dynamic> msg) {
      final sigB64 = msg['sig'];
      Uint8List? signature;
      try {
        if (sigB64 is String && sigB64.length <= 1024) signature = base64Decode(sigB64);
      } catch (_) {}

      final ok = signature != null &&
          DeviceIdentity.verify(
            claimedPub,
            authTranscript(
              role: 'client',
              clientId: claimedId,
              serverId: identity.deviceId,
              clientNonce: clientNonce,
              serverNonce: serverNonce,
              serverCertDer: identity.certDer,
            ),
            signature,
          );
      if (!ok) {
        log("Signature check failed for $claimedId from $ip - dropping connection");
        closeConn();
        return;
      }

      stage = 2;
      authTimer?.cancel();
      authTimer = null;
      releasePreAuth();
      conn.deviceId = claimedId;

      if (SessionData().isPeerSaved(claimedId)) {
        if (acceptPeer(claimedId)) {
          log("Auto-accepted verified saved peer $claimedName ($claimedId)");
        }
        return;
      }
      askUser();
    }

    conn = TcpPeerConnection.fromSocket(
      socket: socket,
      onMessage: (msg) {
        final type = msg['type'];

        if (accepted) {
          SessionData().handlePeerMessage(conn.deviceId!, msg);
          return;
        }
        if (stage == 0) {
          if (type == 'hello') onHello(msg);
        } else if (stage == 1) {
          if (type == 'request') onRequest(msg);
        }
        // Anything else before authentication is ignored.
      },
      onDisconnected: () {
        cleanup();
        if (accepted && conn.deviceId != null) {
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
