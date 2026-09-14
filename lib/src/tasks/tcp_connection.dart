import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:locsand/src/helpers/tls_context.dart';

class TcpPeerConnection {
  String? deviceId;

  final String ip;
  final int port;

  Socket? _socket;
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
    required Socket socket,
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
    _socket = await SecureSocket.connect(ip, port, context: context, timeout: timeout);
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
