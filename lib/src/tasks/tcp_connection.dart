import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:locsand/src/helpers/tls_context.dart';
import 'package:locsand/src/helpers/peer_trust.dart';

class TcpPeerConnection {
  static const Duration _pingEvery = Duration(seconds: 15);
  static const Duration _deadAfter = Duration(seconds: 45);
  static const Duration _awayGrace = Duration(minutes: 5);

  String? deviceId;

  final String ip;
  final int port;

  SecureSocket? _socket;
  StreamSubscription<String>? _subscription;
  Timer? _keepAlive;
  DateTime _lastRx = DateTime.now();
  // Set when the peer says it is going to the background (e.g. file picker).
  // While it is in the future we do not treat silence as a dead connection.
  DateTime? _graceUntil;
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

  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    if (_connected) return;

    final context = await TlsContext.clientContext();
    await PeerTrustStore().ensureLoaded();
    final expectedId = deviceId ?? ip;
    TrustResult? trustResult;

    try {
      _socket = await SecureSocket.connect(
        ip,
        port,
        context: context,
        timeout: timeout,
        onBadCertificate: (cert) {
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
    try {
      _socket!.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    _lastRx = DateTime.now();
    _startKeepAlive();

    _subscription = _socket!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            _lastRx = DateTime.now();
            _graceUntil = null; // any traffic means the peer is back
            try {
              final json = jsonDecode(line) as Map<String, dynamic>;
              if (json['type'] == 'ping') return;
              if (json['type'] == 'away') {
                _graceUntil = DateTime.now().add(_awayGrace);
                return;
              }
              onMessage?.call(json);
            } catch (e) {
              log("Bad message from ${deviceId ?? ip}: $e");
            }
          },
          onError: (Object e) {
            log("TCP error ${deviceId ?? ip}: $e");
            _connected = false;
            _stopKeepAlive();
            _socket?.destroy();
            onError?.call(e);
            onDisconnected?.call();
          },
          onDone: () {
            log("TCP done ${deviceId ?? ip}");
            _connected = false;
            _stopKeepAlive();
            _socket?.destroy();
            onDisconnected?.call();
          },
          cancelOnError: true,
        );
  }

  void _startKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(_pingEvery, (_) {
      if (!_connected) return;

      final now = DateTime.now();
      final inGrace = _graceUntil != null && now.isBefore(_graceUntil!);
      if (!inGrace && now.difference(_lastRx) > _deadAfter) {
        log("No traffic from ${deviceId ?? ip} for ${_deadAfter.inSeconds}s — closing");
        final callback = onDisconnected;
        unawaited(disconnect());
        callback?.call();
        return;
      }

      try {
        _socket?.write('{"type":"ping"}\n');
      } catch (_) {}
    });
  }

  void _stopKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }

  /// Tell the peer we are leaving the foreground, so it will not close the
  /// connection while we are silent.
  void markAway() {
    if (!_connected) return;
    try {
      _socket?.write('{"type":"away"}\n');
    } catch (_) {}
  }

  /// We are back in the foreground: restart the silence timer and ping.
  void markBack() {
    if (!_connected) return;
    _lastRx = DateTime.now();
    _graceUntil = null;
    try {
      _socket?.write('{"type":"ping"}\n');
    } catch (_) {}
  }

  void send(Map<String, dynamic> message) {
    if (!_connected || _socket == null) {
      throw StateError("TCP not connected for ${deviceId ?? ip}");
    }
    _socket!.write("${jsonEncode(message)}\n");
  }

  Future<void> flush() async {
    await _socket?.flush();
  }

  Future<void> disconnect() async {
    _connected = false;
    _stopKeepAlive();
    await _subscription?.cancel();
    _socket?.destroy();
    _socket = null;
  }
}