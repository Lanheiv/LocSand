import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:locsand/src/data/peer_data.dart';

class UdpPeerSearch {
  final String deviceId, deviceName;
  final int udpPort, tcpPort;
  final InternetAddress broadcastAddress;
  final bool enabledBroadcast;
  
  final Function(PeerData) onPeerFound;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  bool _isRunning = false;

  String requestUsers = "userRequest";
  String devicMassage = "devicInfo";

  UdpPeerSearch({
    required this.deviceId,
    required this.deviceName,
    required this.tcpPort,
    required this.udpPort,
    required this.broadcastAddress,
    required this.enabledBroadcast,
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
      if (event != RawSocketEvent.read) return;
      
      final datagram = _socket!.receive();
      if (datagram == null) return;

      try {
        final text = String.fromCharCodes(datagram.data);
        final json = jsonDecode(text) as Map<String, dynamic>;

        String messageType = json['messageType'];

        if (messageType == "devicInfo") {
          if (json['deviceId'] == deviceId) return;

          final peer = PeerData(
            deviceId: json['deviceId'] as String,
            name: json['name'] as String,
            ip: datagram.address.address,
            port: json['port'] as int,
            lastSeen: DateTime.now(),
          );

          onPeerFound(peer);
        } else if (messageType == "userRequest" && enabledBroadcast) {
          _broadcast();
        }
      } catch (_) {}
    });

    if(enabledBroadcast) {
      _broadcastRequest();
      _startBroadcast();
    }
  }

  void _startBroadcast() {
    _broadcast();

    _broadcastTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _broadcast(),
    );
  }

  void _broadcastRequest() {
    if (_socket == null) return;

    final message = jsonEncode({
      'messageType': requestUsers,
      'deviceId': deviceId,
    });

    _socket!.send(
      message.codeUnits,
      broadcastAddress,
      udpPort,
    );
  }

  void _broadcast() {
    if (_socket == null) return;

    final message = jsonEncode({
      'messageType': devicMassage,
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