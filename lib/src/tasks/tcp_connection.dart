import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:locsand/src/helpers/line_framer.dart';
import 'package:locsand/src/helpers/tls_context.dart';

class TcpPeerConnection {
  static const Duration _pingEvery = Duration(seconds: 15);
  static const Duration _deadAfter = Duration(seconds: 45);
  static const Duration _awayGrace = Duration(minutes: 5);

  /// Largest protocol frame (one JSON line) either side will accept. A file
  /// chunk is ~171 KB of base64, a chat message at most ~48 KB.
  static const int maxFrameBytes = 256 * 1024;

  String? deviceId;

  final String ip;
  final int port;

  SecureSocket? _socket;
  StreamSubscription<List<int>>? _subscription;
  final LineFramer _framer = LineFramer(maxFrameBytes: maxFrameBytes);
  Timer? _keepAlive;
  DateTime _lastRx = DateTime.now();
  // Set when the peer says it is going to the background (e.g. file picker).
  // While it is in the future we do not treat silence as a dead connection.
  DateTime? _graceUntil;
  bool _connected = false;

  /// DER of the TLS certificate the server presented (client side only).
  /// Both sides sign its hash during the handshake (channel binding).
  Uint8List? serverCertDer;

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

    // The certificate is self-signed, so TLS here only provides encryption.
    // Who is on the other end is decided by the signed handshake in
    // SessionData._dial, which is bound to this very certificate.
    final socket = await SecureSocket.connect(
      ip,
      port,
      context: context,
      timeout: timeout,
      onBadCertificate: (_) => true,
    );

    final cert = socket.peerCertificate;
    if (cert == null) {
      socket.destroy();
      throw StateError('Peer did not present a TLS certificate');
    }
    serverCertDer = cert.der;
    _socket = socket;

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

    _subscription = _socket!.listen(
      _onData,
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

  void _onData(List<int> data) {
    List<Uint8List> frames;
    try {
      frames = _framer.add(data);
    } on FrameTooLargeException catch (e) {
      _closeForViolation('$e');
      return;
    }
    for (final frame in frames) {
      if (!_connected) return;
      _handleFrame(frame);
    }
  }

  void _handleFrame(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _lastRx = DateTime.now();
    _graceUntil = null; // any traffic means the peer is back
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) return;
      if (json['type'] == 'ping') return;
      if (json['type'] == 'away') {
        _graceUntil = DateTime.now().add(_awayGrace);
        return;
      }
      onMessage?.call(json);
    } catch (e) {
      log("Bad message from ${deviceId ?? ip}: $e");
    }
  }

  void _closeForViolation(String reason) {
    log("Closing ${deviceId ?? ip}: $reason");
    if (!_connected) return;
    _connected = false;
    _stopKeepAlive();
    unawaited(_subscription?.cancel());
    _socket?.destroy();
    onDisconnected?.call();
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