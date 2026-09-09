import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:locsand/data/peer_data.dart';

class UdpPeerSearch {
  final String deviceId;
  final String deviceName;
  final int udpPort;
  final int tcpPort;
  final InternetAddress broadcastAddress;
  final bool broadcastEnabled;
  final Function(PeerData) onPeerFound;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  bool _isRunning = false;

  UdpPeerSearch({
    required this.deviceId,
    required this.deviceName,
    required this.tcpPort,
    required this.udpPort,
    required this.broadcastAddress,
    required this.broadcastEnabled,
    required this.onPeerFound,
  });

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      udpPort,
      reuseAddress: true,
    );
    _socket!.broadcastEnabled = true;

    _socket!.listen((event) {
      final datagram = _socket!.receive();
      if (datagram == null) return;

      try {
        final text = String.fromCharCodes(datagram.data);
        final json = jsonDecode(text) as Map<String, dynamic>;

        //if (json['deviceId'] == deviceId) return;

        final peer = PeerData(
          deviceId: json['deviceId'] as String,
          name: json['name'] as String,
          ip: datagram.address.address,
          port: json['port'] as int,
          lastSeen: DateTime.now(),
        );

        onPeerFound(peer);
      } catch (_) {}
    });

    if(broadcastEnabled) {
      _startBroadcast();
    }
  }

  void _startBroadcast() {
    _broadcast();

    _broadcastTimer = Timer.periodic(
      const Duration(seconds: 10), // NOTE first 30s evey 3s send later evry 30s. if requested then send brotcast
      (_) => _broadcast(),
    );
  }

  void _broadcast() {
    if (_socket == null) return;

    final message = jsonEncode({
      'deviceId': deviceId,
      'name': deviceName,
      'port': tcpPort,
    });

    _socket!.send(
      message.codeUnits,
      broadcastAddress,
      udpPort,
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