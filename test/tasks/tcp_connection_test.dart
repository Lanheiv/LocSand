import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

import '../support/tls_pair.dart';

void main() {
  late TlsPair pair;

  setUp(() async => pair = await TlsPair.open());
  tearDown(() => pair.close());

  group('connection and messages', () {
    test('both ends are connected', () {
      expect(pair.client.isConnected, isTrue);
      expect(pair.server.isConnected, isTrue);
    });

    test('client → server', () async {
      pair.client.send({'type': 'chat', 'text': 'Hello'});
      final m = await pair.serverInbox.waitForType('chat');
      expect(m['text'], 'Hello');
    });

    test('server → client', () async {
      pair.server.send({'type': 'chat', 'text': 'Reply'});
      final m = await pair.clientInbox.waitForType('chat');
      expect(m['text'], 'Reply');
    });

    test('message order is preserved', () async {
      for (var i = 0; i < 50; i++) {
        pair.client.send({'type': 'n', 'i': i});
      }
      await waitUntil(() => pair.serverInbox.ofType('n').length == 50);
      expect(pair.serverInbox.ofType('n').map((m) => m['i']),
          List<int>.generate(50, (i) => i));
    });

    test('newlines and Unicode in text do not break framing', () async {
      const text = 'line1\nline2\r\nēūīāšņ 🙂 "quotes" \\ backslash';
      pair.client.send({'type': 'chat', 'text': text});
      final m = await pair.serverInbox.waitForType('chat');
      expect(m['text'], text);
    });

    test('a large message (~200 KB) is received completely', () async {
      final big = 'x' * 200000;
      pair.client.send({'type': 'chat', 'text': big});
      final m = await pair.serverInbox.waitForType('chat');
      expect((m['text'] as String).length, 200000);
    });

    test('flush() returns without an error', () async {
      pair.client.send({'type': 'chat', 'text': 'x'});
      await pair.client.flush();
    });
  });

  group('service messages and invalid data', () {
    test('ping and away are not passed to onMessage', () async {
      pair.client.send({'type': 'ping'});
      pair.client.markAway();
      pair.client.markBack();
      pair.client.send({'type': 'marker'});
      await pair.serverInbox.waitForType('marker');
      expect(pair.serverInbox.ofType('ping'), isEmpty);
      expect(pair.serverInbox.ofType('away'), isEmpty);
    });
  });

  group('disconnection', () {
    test('disconnect() on one side triggers onDisconnected on the other', () async {
      await pair.client.disconnect();
      await waitUntil(() => pair.serverClosed);
      expect(pair.client.isConnected, isFalse);
      expect(pair.server.isConnected, isFalse);
    });

    test('send() after disconnect throws StateError', () async {
      await pair.client.disconnect();
      expect(() => pair.client.send({'type': 'x'}), throwsStateError);
    });

    test('markAway/markBack after disconnect do not throw', () async {
      await pair.client.disconnect();
      pair.client.markAway();
      pair.client.markBack();
    });

    test('repeated disconnect() is safe', () async {
      await pair.client.disconnect();
      await pair.client.disconnect();
    });
  });

  group('connect()', () {
    test('stores the server TLS certificate DER (channel binding)', () {
      expect(pair.client.serverCertDer, isNotNull);
      expect(pair.client.serverCertDer, pair.serverCertDer);
    });

    test('connecting to a closed port throws an error', () async {
      final port = await freeTcpPort();
      final c = TcpPeerConnection(ip: '127.0.0.1', port: port);
      await expectLater(
        c.connect(timeout: const Duration(seconds: 2)),
        throwsA(isA<IOException>()),
      );
      expect(c.isConnected, isFalse);
    });

    test('a plain (non-TLS) server is rejected: the handshake fails', () async {
      final plain = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      plain.listen((s) {
        s.add(utf8.encode('HTTP/1.1 200 OK\r\n\r\n'));
        s.close();
      });
      final c = TcpPeerConnection(ip: '127.0.0.1', port: plain.port);
      await expectLater(
        c.connect(timeout: const Duration(seconds: 2)),
        throwsA(anything),
      );
      await plain.close();
    });

    test('repeated connect() on an already connected object does nothing', () async {
      await pair.client.connect();
      expect(pair.client.isConnected, isTrue);
    });
  });

  group('raw (malformed) data', () {
    late RawPair raw;
    setUp(() async => raw = await RawPair.open());
    tearDown(() => raw.close());

    Future<void> expectOnlyMarker() async {
      raw.write('{"type":"marker"}\n');
      await raw.serverInbox.waitForType('marker');
      expect(raw.serverInbox.items.length, 1);
      expect(raw.server.isConnected, isTrue);
    }

    test('malformed JSON is ignored and the connection stays alive', () async {
      raw.write('{"type":\n');
      await expectOnlyMarker();
    });

    test('JSON that is not an object is ignored', () async {
      raw.write('[1,2,3]\n"text"\n42\nnull\n');
      await expectOnlyMarker();
    });

    test('empty lines are ignored', () async {
      raw.write('\n\n\n');
      await expectOnlyMarker();
    });

    test('invalid UTF-8 is ignored', () async {
      raw.writeBytes([0xff, 0xfe, 0xfd, 10]);
      await expectOnlyMarker();
    });

    test('a frame split across several TCP chunks is reassembled', () async {
      raw.write('{"type":"sp');
      await raw.raw.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      raw.write('lit","v":1}\n');
      final m = await raw.serverInbox.waitForType('split');
      expect(m['v'], 1);
    });

    test('multiple messages in one write are separated', () async {
      raw.write('{"type":"a"}\n{"type":"b"}\n{"type":"c"}\n');
      await waitUntil(() => raw.serverInbox.items.length == 3);
      expect(raw.serverInbox.items.map((m) => m['type']), ['a', 'b', 'c']);
    });
  });
}
