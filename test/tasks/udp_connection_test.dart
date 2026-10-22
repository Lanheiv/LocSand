import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/tasks/udp_connection.dart';

import '../support/tls_pair.dart';

final String selfId = 'f' * 64;
final String otherId = 'a' * 64;

Map<String, dynamic> info(String id, {Object? name = 'Test Phone', Object? port = 5000}) =>
    {'messageType': 'devicInfo', 'deviceId': id, 'name': name, 'port': port};

Map<String, dynamic> request(String id) =>
    {'messageType': 'userRequest', 'deviceId': id};

/// Starts UdpPeerSearch on a free port and provides a "probe" — a plain UDP
/// socket used to send packets to 127.0.0.1.
class Harness {
  late UdpPeerSearch search;
  late int port;
  late RawDatagramSocket probe;
  final found = <PeerData>[];
  final replies = <Map<String, dynamic>>[];
  int sentinels = 0;

  static Future<Harness> start({bool broadcast = false}) async {
    final h = Harness();
    h.port = await freeUdpPort();
    h.search = UdpPeerSearch(
      deviceId: selfId,
      deviceName: 'This Device',
      tcpPort: 4444,
      udpPort: h.port,
      broadcastAddress: InternetAddress('127.255.255.255'),
      enabledBroadcast: broadcast,
      onPeerFound: h.found.add,
    );
    await h.search.start();

    h.probe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    h.probe.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = h.probe.receive();
      if (d == null) return;
      try {
        h.replies.add(jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>);
      } catch (_) {}
    });
    return h;
  }

  void sendRaw(List<int> bytes) =>
      probe.send(bytes, InternetAddress.loopbackIPv4, port);
  void sendJson(Object o) => sendRaw(utf8.encode(jsonEncode(o)));

  /// Sends a "sentinel" packet and waits until it is processed — at that point
  /// all previously sent packets are known to have been read.
  Future<void> flush() async {
    final id = (0xc0000 + (++sentinels)).toRadixString(16).padLeft(64, '0');
    sendJson(info(id));
    await waitUntil(() => found.any((p) => p.deviceId == id),
        reason: 'sentinel packet');
  }

  Future<void> dispose() async {
    search.stop();
    probe.close();
  }
}

void main() {
  late Harness h;

  group('receiving', () {
    setUp(() async => h = await Harness.start());
    tearDown(() => h.dispose());

    test('a valid devicInfo packet reports a device', () async {
      h.sendJson(info(otherId, name: 'Test Laptop', port: 5123));
      await waitUntil(() => h.found.isNotEmpty);
      final p = h.found.single;
      expect(p.deviceId, otherId);
      expect(p.name, 'Test Laptop');
      expect(p.ip, '127.0.0.1');
      expect(p.port, 5123);
    });

    test('an over-long name is truncated to 64 characters', () async {
      h.sendJson(info(otherId, name: 'x' * 100));
      await waitUntil(() => h.found.isNotEmpty);
      expect(h.found.single.name.length, 64);
    });

    test('empty name → the ID is used', () async {
      h.sendJson(info(otherId, name: ''));
      await waitUntil(() => h.found.isNotEmpty);
      expect(h.found.single.name, otherId);
    });

    test('packets from the device itself are ignored', () async {
      h.sendJson(info(selfId));
      await h.flush();
      expect(h.found.where((p) => p.deviceId == selfId), isEmpty);
    });

    final bad = <String, List<int>>{
      'invalid deviceId format': utf8.encode(jsonEncode(info('ABC'))),
      'deviceId with uppercase letters': utf8.encode(jsonEncode(info('A' * 64))),
      'port 0': utf8.encode(jsonEncode(info(otherId, port: 0))),
      'port 65536': utf8.encode(jsonEncode(info(otherId, port: 65536))),
      'port as a string': utf8.encode(jsonEncode(info(otherId, port: '5000'))),
      'name is not a string': utf8.encode(jsonEncode(info(otherId, name: 123))),
      'unknown messageType': utf8.encode(jsonEncode(
          {'messageType': 'foo', 'deviceId': otherId, 'name': 'x', 'port': 1})),
      'JSON is not an object': utf8.encode('[1,2,3]'),
      'malformed JSON': utf8.encode('{"messageType":'),
      'random bytes': List<int>.generate(100, (i) => 200 + i % 50),
      'packet above 1024 bytes':
          utf8.encode(jsonEncode(info(otherId, name: 'x' * 1100))),
    };
    for (final entry in bad.entries) {
      test('ignores: ${entry.key}', () async {
        h.sendRaw(entry.value);
        await h.flush();
        expect(h.found.where((p) => p.deviceId == otherId), isEmpty);
      });
    }

    test('floods from a single address are limited (rate limit)', () async {
      for (var i = 0; i < 200; i++) {
        final id = (i + 1).toRadixString(16).padLeft(64, '0');
        h.sendJson(info(id));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(h.found, isNotEmpty);
      expect(h.found.length, lessThan(60),
          reason: 'the limit is ~20 packets/s per IP');
    });

    test('stop() — after stopping, packets are no longer processed', () async {
      h.search.stop();
      h.sendJson(info(otherId));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(h.found, isEmpty);
    });
  });

  group('replies (broadcast enabled)', () {
    setUp(() async => h = await Harness.start(broadcast: true));
    tearDown(() => h.dispose());

    test('userRequest triggers a devicInfo reply with our TCP port', () async {
      h.sendJson(request(otherId));
      await waitUntil(() => h.replies.any((r) => r['messageType'] == 'devicInfo'));
      final r = h.replies.firstWhere((r) => r['messageType'] == 'devicInfo');
      expect(r['deviceId'], selfId);
      expect(r['name'], 'This Device');
      expect(r['port'], 4444);
    });

    test('a repeated userRequest within one second is ignored', () async {
      h.sendJson(request(otherId));
      h.sendJson(request(otherId));
      h.sendJson(request(otherId));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(h.replies.where((r) => r['messageType'] == 'devicInfo').length, 1);
    });

    test('a new device receives our info as a reply to its own info', () async {
      h.sendJson(info(otherId));
      await waitUntil(() => h.replies.any((r) => r['messageType'] == 'devicInfo'));
      expect(h.replies.first['deviceId'], selfId);
    });

    test('setBroadcast(false) stops replying', () async {
      h.search.setBroadcast(false);
      h.sendJson(request(otherId));
      await h.flush();
      expect(h.replies, isEmpty);
    });

    test('a deviceName change appears in subsequent replies', () async {
      h.search.deviceName = 'Renamed Device';
      h.sendJson(request(otherId));
      await waitUntil(() => h.replies.any((r) => r['messageType'] == 'devicInfo'));
      expect(h.replies.first['name'], 'Renamed Device');
    });
  });

  group('broadcast disabled', () {
    setUp(() async => h = await Harness.start(broadcast: false));
    tearDown(() => h.dispose());

    test('userRequest is not answered, but devices are still discovered', () async {
      h.sendJson(request(otherId));
      await h.flush();
      expect(h.replies, isEmpty);
    });

    test('setBroadcast(true) enables replies', () async {
      h.search.setBroadcast(true);
      h.sendJson(request(otherId));
      await waitUntil(() => h.replies.any((r) => r['messageType'] == 'devicInfo'));
    });
  });
}
