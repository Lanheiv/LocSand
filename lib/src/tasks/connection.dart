import 'dart:developer';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:locsand/data/peerData.dart';

class UdpPeerSearch {
  final String deviceId;
  final String deviceName;
  final int port; // you can use 0 for now
  final Function(PeerInfo) onPeerFound;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  bool _isRunning = false;

  final broadcastAddress = InternetAddress('255.255.255.255');
  final broadcastPort = 53318;

  UdpPeerSearch({
    required this.deviceId,
    required this.deviceName,
    required this.port,
    required this.onPeerFound,
  });

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      broadcastPort,
      reuseAddress: true,
    );
    _socket!.broadcastEnabled = true;

    _socket!.listen((event) {
      final datagram = _socket!.receive();
      if (datagram == null) return;

      try {
        final text = String.fromCharCodes(datagram.data);
        final json = jsonDecode(text) as Map<String, dynamic>;

        // if (json['deviceId'] == deviceId) return;

        final peer = PeerInfo(
          deviceId: json['deviceId'] as String,
          name: json['name'] as String,
          ip: datagram.address.address,
          port: json['port'] as int,
          lastSeen: DateTime.now(),
        );

        onPeerFound(peer);
      } catch (_) {}
    });

    _startBroadcast();
  }

  void _startBroadcast() {
    _broadcast();

    _broadcastTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _broadcast(),
    );
  }

  void _broadcast() {
    if (_socket == null) return;

    final message = jsonEncode({
      'deviceId': deviceId,
      'name': deviceName,
      'port': port,
    });

    _socket!.send(
      message.codeUnits,
      broadcastAddress,
      broadcastPort,
    );
  }

  void stop() {
    _isRunning = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _socket?.close();
    _socket = null;
  }
}