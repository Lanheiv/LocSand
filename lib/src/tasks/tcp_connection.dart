// src/tasks/tcp_connection.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

class TcpPeerConnection {
  final String deviceId;
  final String ip;
  final int port;

  Socket? _socket;
  StreamSubscription<String>? _subscription; // <-- change type
  bool _connected = false;

  // Callbacks
  final Function(Map<String, dynamic> message)? onMessage;
  final Function(Object error)? onError;
  final Function()? onDisconnected;

  TcpPeerConnection({
    required this.deviceId,
    required this.ip,
    required this.port,
    this.onMessage,
    this.onError,
    this.onDisconnected,
  });

  bool get isConnected => _connected && _socket != null;

  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    if (_connected) return;

    _socket = await Socket.connect(ip, port, timeout: timeout);
    _connected = true;
    log("TCP connected to $deviceId at $ip:$port");

    // Listen to incoming data as lines of text
    _subscription = _socket!
        .map((bytes) => utf8.decode(bytes))
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final json = jsonDecode(line) as Map<String, dynamic>;
              onMessage?.call(json);
            } catch (e) {
              log("Bad message from $deviceId: $e");
            }
          },
          onError: (Object e) {
            log("TCP error $deviceId: $e");
            _connected = false;
            onError?.call(e);
            onDisconnected?.call();
          },
          onDone: () {
            log("TCP done $deviceId");
            _connected = false;
            onDisconnected?.call();
          },
          cancelOnError: true,
        );
  }

  void send(Map<String, dynamic> message) {
    if (!_connected || _socket == null) {
      throw StateError("TCP not connected for $deviceId");
    }
    final line = jsonEncode(message);
    _socket!.write("$line\n");
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _socket?.destroy();
    _socket = null;
    _connected = false;
  }
}