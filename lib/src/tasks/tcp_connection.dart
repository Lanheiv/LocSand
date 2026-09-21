import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:locsand/src/helpers/tls_context.dart';
import 'package:locsand/src/helpers/peer_trust.dart';

class TcpPeerConnection {
  String? deviceId;

  final String ip;
  final int port;

  SecureSocket? _socket;
  StreamSubscription<String>? _subscription;
  bool _connected = false;

  final Function(Map<String, dynamic> message)? onMessage;
  final Function(Object error)? onError;
  final Function()? onDisconnected;

  TcpPeerConnection({
    this.deviceId,
    required this.ip,
    required this.port,
    this.onMessage,
    this.onError,
    this.onDisconnected,
  });

  TcpPeerConnection.fromSocket({
    required SecureSocket socket,
    this.onMessage,
    this.onError,
    this.onDisconnected,
  })  : ip = socket.remoteAddress.address,
        port = socket.remotePort {
    _socket = socket;
    _connected = true;
    _listen();
  }

  bool get isConnected => _connected && _socket != null;

  /// The certificate the remote side presented during the TLS handshake,
  /// if any. On the client side this is always the peer's server
  /// certificate. On the server side (sockets built via [fromSocket]) this
  /// is only non-null when the remote side presented a client certificate,
  /// which requires [SecureServerSocket.bind] to have been called with
  /// `requestClientCertificate: true`.
  X509Certificate? get peerCertificate => _socket?.peerCertificate;

  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    if (_connected) return;

    final context = await TlsContext.clientContext();
    await PeerTrustStore().ensureLoaded();

    // The identity we're trying to reach. Falling back to the IP keeps the
    // check meaningful even if a caller ever connects without a known
    // deviceId, though in practice SessionData always supplies one.
    final expectedId = deviceId ?? ip;
    TrustResult? trustResult;

    try {
      _socket = await SecureSocket.connect(
        ip,
        port,
        context: context,
        timeout: timeout,
        onBadCertificate: (cert) {
          // This device generates its own self-signed certificate, so every
          // peer certificate is technically "bad" as far as a CA-based trust
          // chain is concerned. Instead of blindly accepting it, we fall
          // back to trust-on-first-use: the first certificate we see for a
          // deviceId is remembered, and every later connection to that same
          // deviceId must present the exact same certificate. A mismatch
          // means either the peer regenerated its keys or someone else is
          // answering on that deviceId/IP — either way we refuse to proceed
          // silently.
          trustResult = PeerTrustStore().evaluateSync(expectedId, cert);
          return trustResult != TrustResult.mismatch;
        },
      );
    } on HandshakeException {
      if (trustResult == TrustResult.mismatch) {
        throw StateError(
          "Certificate for $expectedId does not match the certificate we "
          "trusted previously. Refusing to connect — this could mean the "
          "peer reset its identity, or that another device is impersonating "
          "it.",
        );
      }
      rethrow;
    }

    if (trustResult == TrustResult.newlyTrusted) {
      log("Trusting $expectedId's certificate for the first time");
    }

    _connected = true;
    log("TCP (TLS) connected to ${deviceId ?? ip}:$port");
    _listen();
  }

  void _listen() {
    _subscription = _socket!
        .cast<List<int>>()
        .map((bytes) => utf8.decode(bytes))
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final json = jsonDecode(line) as Map<String, dynamic>;
              onMessage?.call(json);
            } catch (e) {
              log("Bad message from ${deviceId ?? ip}: $e");
            }
          },
          onError: (Object e) {
            log("TCP error ${deviceId ?? ip}: $e");
            _connected = false;
            onError?.call(e);
            onDisconnected?.call();
          },
          onDone: () {
            log("TCP done ${deviceId ?? ip}");
            _connected = false;
            onDisconnected?.call();
          },
          cancelOnError: true,
        );
  }

  void send(Map<String, dynamic> message) {
    if (!_connected || _socket == null) {
      throw StateError("TCP not connected for ${deviceId ?? ip}");
    }
    _socket!.write("${jsonEncode(message)}\n");
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _socket?.destroy();
    _socket = null;
    _connected = false;
  }
}