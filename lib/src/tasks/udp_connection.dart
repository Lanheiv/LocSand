import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/helpers/auth_protocol.dart';

class UdpPeerSearch {
  static const String _typeInfo = 'devicInfo';
  static const String _typeRequest = 'userRequest';

  static const Duration _announceEvery = Duration(seconds: 10);
  static const Duration _knownFor = Duration(seconds: 45);
  static const Duration _restartAfter = Duration(seconds: 5);
  static const List<Duration> _startupBurst = [
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  // Discovery packets are tiny; anything bigger is junk. Each source address
  // may send only a few packets per second (the app itself sends about one
  // every ten seconds), so a flood is dropped before any JSON is parsed.
  static const int _maxPacketBytes = 1024;
  static const int _maxPacketsPerSecondPerIp = 20;
  static const int _maxTrackedSources = 1024;

  static final InternetAddress _limitedBroadcast = InternetAddress('255.255.255.255');

  final String deviceId;
  String deviceName;
  final int udpPort, tcpPort;
  final InternetAddress broadcastAddress;
  bool enabledBroadcast;

  final void Function(PeerData) onPeerFound;

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  Timer? _restartTimer;
  final List<Timer> _burstTimers = [];

  bool _wanted = false;

  Set<String> _localAddresses = {};
  List<InternetAddress> _targets = [];

  final Map<String, DateTime> _lastHeard = {};
  final Map<String, DateTime> _lastReplyTo = {};
  final Map<String, _RateBucket> _rate = {};

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
    if (_wanted) return;
    _wanted = true;
    await _bind();
  }

  void stop() {
    _wanted = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    _closeSocket();
    _lastHeard.clear();
    _lastReplyTo.clear();
  }

  Future<void> refresh() async {
    if (!enabledBroadcast) return;
    await _announce(askForPeers: true);
  }

  void setBroadcast(bool value) {
    if (enabledBroadcast == value) return;
    enabledBroadcast = value;
    if (_socket == null) return;
    _stopAnnouncing();
    if (value) _startAnnouncing();
  }

  Future<void> _bind() async {
    if (!_wanted) return;

    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
    } catch (e) {
      log('UDP bind failed: $e');
      _scheduleRestart();
      return;
    }

    _socket = socket;
    socket.listen(
      (event) {
        if (event == RawSocketEvent.read) _drain(socket);
      },
      onError: (Object e) {
        log('UDP socket error: $e');
        _scheduleRestart();
      },
      onDone: () {
        if (identical(_socket, socket)) _scheduleRestart();
      },
      cancelOnError: true,
    );

    if (enabledBroadcast) _startAnnouncing();
  }

  void _scheduleRestart() {
    if (!_wanted || _restartTimer != null) return;
    _closeSocket();
    _restartTimer = Timer(_restartAfter, () {
      _restartTimer = null;
      unawaited(_bind());
    });
  }

  void _stopAnnouncing() {
    _announceTimer?.cancel();
    _announceTimer = null;
    for (final t in _burstTimers) {
      t.cancel();
    }
    _burstTimers.clear();
  }

  void _closeSocket() {
    _stopAnnouncing();

    final socket = _socket;
    _socket = null;
    socket?.close();
  }

  void _startAnnouncing() {
    unawaited(_announce(askForPeers: true));

    for (final delay in _startupBurst) {
      _burstTimers.add(
        Timer(delay, () => unawaited(_announce(askForPeers: true))),
      );
    }

    _announceTimer = Timer.periodic(_announceEvery, (_) {
      _housekeeping();
      unawaited(_announce());
    });
  }

  Future<void> _announce({bool askForPeers = false}) async {
    if (_socket == null) return;

    final networkChanged = await _refreshTargets();
    final info = _infoBytes();
    final request = (askForPeers || networkChanged) ? _requestBytes() : null;

    for (final target in _targets) {
      _safeSend(info, target, udpPort);
      if (request != null) _safeSend(request, target, udpPort);
    }
  }

  Future<bool> _refreshTargets() async {
    final targets = <String, InternetAddress>{
      broadcastAddress.address: broadcastAddress,
      _limitedBroadcast.address: _limitedBroadcast,
    };
    final local = <String>{};

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final nic in interfaces) {
        for (final addr in nic.addresses) {
          local.add(addr.address);
          final o = addr.rawAddress;
          if (o.length != 4) continue;
          final directed = InternetAddress('${o[0]}.${o[1]}.${o[2]}.255');
          targets[directed.address] = directed;
        }
      }
    } catch (e) {
      log('Listing network interfaces failed: $e');
    }

    _targets = targets.values.toList();

    final changed = local.length != _localAddresses.length ||
        !local.every(_localAddresses.contains);
    _localAddresses = local;
    return changed;
  }

  void _housekeeping() {
    final now = DateTime.now();
    _lastHeard.removeWhere((_, t) => now.difference(t) > _knownFor * 4);
    _lastReplyTo.removeWhere((_, t) => now.difference(t) > const Duration(minutes: 1));
  }

  void _drain(RawDatagramSocket socket) {
    while (true) {
      final datagram = socket.receive();
      if (datagram == null) break;
      _handle(datagram);
    }
  }

  bool _allowFrom(String ip) {
    final now = DateTime.now();
    final bucket = _rate[ip];
    if (bucket == null || now.difference(bucket.start) >= const Duration(seconds: 1)) {
      if (_rate.length >= _maxTrackedSources) _rate.clear();
      _rate[ip] = _RateBucket(now);
      return true;
    }
    bucket.count++;
    return bucket.count <= _maxPacketsPerSecondPerIp;
  }

  void _handle(Datagram d) {
    if (d.data.length > _maxPacketBytes) return;
    if (!_allowFrom(d.address.address)) return;
    try {
      final json = jsonDecode(utf8.decode(d.data, allowMalformed: true));
      if (json is! Map<String, dynamic>) return;

      final type = json['messageType'];
      final id = json['deviceId'];
      if (type is! String || id is! String) return;
      if (!deviceIdPattern.hasMatch(id)) return;
      if (id == deviceId) return;

      if (type == _typeInfo) {
        _onInfo(json, id, d);
      } else if (type == _typeRequest && enabledBroadcast) {
        _onRequest(d);
      }
    } catch (e) {
      log('bad UDP packet from ${d.address.address}: $e');
    }
  }

  void _onInfo(Map<String, dynamic> json, String id, Datagram d) {
    final name = json['name'];
    final port = json['port'];
    if (name is! String || port is! int || port < 1 || port > 65535) return;

    final now = DateTime.now();
    final previous = _lastHeard[id];
    _lastHeard[id] = now;

    onPeerFound(PeerData(
      deviceId: id,
      name: name.isEmpty ? id : (name.length > 64 ? name.substring(0, 64) : name),
      ip: d.address.address,
      port: port,
      lastSeen: now,
    ));

    final isNew = previous == null || now.difference(previous) > _knownFor;
    if (enabledBroadcast && isNew) _sendInfo(d.address, d.port);
  }

  void _onRequest(Datagram d) {
    final key = d.address.address;
    final now = DateTime.now();
    final last = _lastReplyTo[key];
    if (last != null && now.difference(last) < const Duration(seconds: 1)) return;
    _lastReplyTo[key] = now;

    _sendInfo(d.address, d.port);
  }

  List<int> _infoBytes() => utf8.encode(jsonEncode({
        'messageType': _typeInfo,
        'deviceId': deviceId,
        'name': deviceName,
        'port': tcpPort,
      }));

  List<int> _requestBytes() => utf8.encode(jsonEncode({
        'messageType': _typeRequest,
        'deviceId': deviceId,
      }));

  void _sendInfo(InternetAddress to, int port) => _safeSend(_infoBytes(), to, port);

  bool _safeSend(List<int> data, InternetAddress to, int port) {
    final socket = _socket;
    if (socket == null) return false;
    try {
      socket.send(data, to, port);
      return true;
    } on SocketException catch (e) {
      log('UDP send to ${to.address} failed: $e');
      return false;
    }
  }
}

class _RateBucket {
  _RateBucket(this.start);
  final DateTime start;
  int count = 1;
}
