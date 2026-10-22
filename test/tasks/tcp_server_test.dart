@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/helpers/auth_protocol.dart';
import 'package:locsand/src/helpers/device_identity.dart';
import 'package:locsand/src/helpers/peer_store.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';
import 'package:locsand/src/tasks/tcp_server.dart';

import '../support/tls_pair.dart';

/// A device that dials the server. Its key pair is separate from the server identity.
class ClientIdentity {
  ClientIdentity._(this.priv, this.pubPem) : id = deviceIdFromPublicKey(pubPem);

  factory ClientIdentity.generate() {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    return ClientIdentity._(
      pair.privateKey as RSAPrivateKey,
      CryptoUtils.encodeRSAPublicKeyToPem(pair.publicKey as RSAPublicKey),
    );
  }

  final RSAPrivateKey priv;
  final String pubPem;
  final String id;

  Uint8List sign(Uint8List d) => CryptoUtils.rsaSign(priv, d);
}

class Dial {
  late TcpPeerConnection conn;
  final Inbox inbox = Inbox();
  bool closed = false;
  late String clientNonce;
  late Json challenge;

  static Future<Dial> open(int port) async {
    final d = Dial();
    d.conn = TcpPeerConnection(
      ip: '127.0.0.1',
      port: port,
      onMessage: d.inbox.add,
      onDisconnected: () => d.closed = true,
    );
    await d.conn.connect();
    return d;
  }

  void hello(ClientIdentity c,
      {String? id, String? pub, String? nonce, String name = 'Test Client'}) {
    clientNonce = nonce ?? newNonce();
    conn.send({
      'type': 'hello',
      'deviceId': id ?? c.id,
      'name': name,
      'pub': pub ?? c.pubPem,
      'nonce': clientNonce,
    });
  }

  /// Waits for the challenge and verifies the server signature just like a real client.
  Future<void> readChallenge(ClientIdentity c) async {
    challenge = await inbox.waitForType('challenge');
    final serverId = challenge['deviceId'] as String;
    expect(deviceIdFromPublicKey(challenge['pub'] as String), serverId,
        reason: 'server ID is the hash of its public key');
    final ok = DeviceIdentity.verify(
      challenge['pub'] as String,
      authTranscript(
        role: 'server',
        clientId: c.id,
        serverId: serverId,
        clientNonce: clientNonce,
        serverNonce: challenge['nonce'] as String,
        serverCertDer: conn.serverCertDer!,
      ),
      base64Decode(challenge['sig'] as String),
    );
    expect(ok, isTrue, reason: 'server signature is invalid');
  }

  void request(ClientIdentity claimed, {ClientIdentity? signer}) {
    final sig = (signer ?? claimed).sign(authTranscript(
      role: 'client',
      clientId: claimed.id,
      serverId: challenge['deviceId'] as String,
      clientNonce: clientNonce,
      serverNonce: challenge['nonce'] as String,
      serverCertDer: conn.serverCertDer!,
    ));
    conn.send({'type': 'request', 'sig': base64Encode(sig)});
  }

  Future<void> fullHandshake(ClientIdentity c, {ClientIdentity? signer}) async {
    hello(c);
    await readChallenge(c);
    request(c, signer: signer);
  }

  Future<void> close() => conn.disconnect();
}

void main() {
  late int port;
  late String serverId;
  late ClientIdentity trustedClient;
  late ClientIdentity savedClient;
  late ClientIdentity attacker;
  final dials = <Dial>[];
  final prompts = <({String id, String shown})>[];

  Future<Dial> dial() async {
    final d = await Dial.open(port);
    dials.add(d);
    return d;
  }

  setUpAll(() async {
    installFakePathProvider();
    serverId = await DeviceIdentity.loadOrCreateId();
    SessionData().userId = serverId;
    SessionData().userName = 'Test Server';
    port = await freeTcpPort();
    await TcpPeerServer(port: port).start();
    trustedClient = ClientIdentity.generate();
    savedClient = ClientIdentity.generate();
    attacker = ClientIdentity.generate();
  });

  tearDown(() async {
    for (final d in dials) {
      await d.close();
    }
    dials.clear();
    prompts.clear();
    SessionData().onIncomingRequest = null;
  });

  void userAnswers(bool yes) {
    SessionData().onIncomingRequest = (id, shown, respond) {
      prompts.add((id: id, shown: shown));
      respond(yes);
    };
  }

  group('successful handshake', () {
    test('user accepts and chat messages are delivered', () async {
      userAnswers(true);
      final d = await dial();
      await d.fullHandshake(trustedClient);

      final accept = await d.inbox.waitForType('accept');
      expect(accept['deviceId'], serverId);
      expect(accept['name'], 'Test Server');

      expect(prompts.single.id, trustedClient.id);
      expect(prompts.single.shown, contains('Test Client'));
      expect(prompts.single.shown, contains(shortDeviceId(trustedClient.id)));

      await waitUntil(() => SessionData().isConnected(trustedClient.id));

      d.conn.send({'type': 'chat', 'text': 'Hello from the client'});
      await waitUntil(
          () => (SessionData().chatMessages[trustedClient.id]?.length ?? 0) == 1);
      final msg = SessionData().chatMessages[trustedClient.id]!.single;
      expect(msg.text, 'Hello from the client');
      expect(msg.fromMe, isFalse);
    });

    test('a saved device is accepted without prompting', () async {
      await SavedPeersStore().save(savedClient.id, 'Saved Device');
      addTearDown(() => SavedPeersStore().remove(savedClient.id));
      var asked = false;
      SessionData().onIncomingRequest = (_, __, respond) {
        asked = true;
        respond(false);
      };

      final d = await dial();
      await d.fullHandshake(savedClient);
      await d.inbox.waitForType('accept');
      expect(asked, isFalse);
    });
  });

  group('rejection', () {
    test('user declines → reject and the connection is closed', () async {
      userAnswers(false);
      final d = await dial();
      await d.fullHandshake(trustedClient);
      await d.inbox.waitForType('reject');
      await waitUntil(() => d.closed);
      expect(d.inbox.ofType('accept'), isEmpty);
    });

    test('no (UI) handler → reject', () async {
      final d = await dial();
      await d.fullHandshake(trustedClient);
      await d.inbox.waitForType('reject');
    });
  });

  group('attacks and invalid data', () {
    test('signature with a different key (ID spoofing) → connection is terminated',
        () async {
      userAnswers(true);
      final d = await dial();
      d.hello(trustedClient);
      await d.readChallenge(trustedClient);
      // The attacker impersonates the trusted client.
      d.request(trustedClient, signer: attacker);
      await waitUntil(() => d.closed);
      expect(d.inbox.ofType('accept'), isEmpty);
      expect(prompts, isEmpty, reason: 'the user must not see a forged request');
    });

    test('hello where the ID does not match the public key → abort', () async {
      userAnswers(true);
      final d = await dial();
      // Claims to be the saved client but presents the trusted client's key.
      d.hello(trustedClient, id: savedClient.id);
      await waitUntil(() => d.closed);
      expect(d.inbox.ofType('challenge'), isEmpty);
    });

    test('hello with a too-short nonce → abort', () async {
      final d = await dial();
      d.hello(trustedClient, nonce: 'short');
      await waitUntil(() => d.closed);
    });

    test('hello with the server\'s own ID → abort', () async {
      final d = await dial();
      d.hello(trustedClient, id: serverId);
      await waitUntil(() => d.closed);
    });

    test('hello with an invalid ID format → abort', () async {
      final d = await dial();
      d.hello(trustedClient, id: 'invalid-id');
      await waitUntil(() => d.closed);
    });

    test('messages before authentication are ignored', () async {
      userAnswers(true);
      final chatsBefore = SessionData().chatMessages.length;
      final d = await dial();
      d.conn.send({'type': 'chat', 'text': 'before handshake'});
      d.conn.send({'type': 'file_offer', 'transferId': 'x', 'name': 'a', 'size': 1});
      d.conn.send({'type': 'request', 'sig': 'AAAA'}); // request without hello
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(d.inbox.ofType('accept'), isEmpty);
      expect(SessionData().chatMessages.length, chatsBefore);
      expect(prompts, isEmpty);
    });

    test('request with an invalid base64 signature → abort', () async {
      userAnswers(true);
      final d = await dial();
      d.hello(trustedClient);
      await d.readChallenge(trustedClient);
      d.conn.send({'type': 'request', 'sig': '!!!not base64!!!'});
      await waitUntil(() => d.closed);
      expect(prompts, isEmpty);
    });

    test('request without a signature → abort', () async {
      final d = await dial();
      d.hello(trustedClient);
      await d.readChallenge(trustedClient);
      d.conn.send({'type': 'request'});
      await waitUntil(() => d.closed);
    });

    test('a signature from another session (nonce reuse) is not valid', () async {
      userAnswers(true);
      // Session 1: obtain a valid signature of the trusted client.
      final d1 = await dial();
      d1.hello(trustedClient);
      await d1.readChallenge(trustedClient);
      final oldSig = trustedClient.sign(authTranscript(
        role: 'client',
        clientId: trustedClient.id,
        serverId: d1.challenge['deviceId'] as String,
        clientNonce: d1.clientNonce,
        serverNonce: d1.challenge['nonce'] as String,
        serverCertDer: d1.conn.serverCertDer!,
      ));
      await d1.close();

      // Session 2: try the same signature with a new server nonce.
      final d2 = await dial();
      d2.hello(trustedClient);
      await d2.readChallenge(trustedClient);
      d2.conn.send({'type': 'request', 'sig': base64Encode(oldSig)});
      await waitUntil(() => d2.closed);
      expect(d2.inbox.ofType('accept'), isEmpty);
    });

    test('limit of pending (unauthenticated) connections per IP = 4', () async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final idle = <Dial>[];
      for (var i = 0; i < 4; i++) {
        idle.add(await dial());
      }
      var rejected = false;
      try {
        final fifth = await dial();
        await waitUntil(() => fifth.closed, timeout: const Duration(seconds: 5));
        rejected = true;
      } on IOException {
        rejected = true; // being rejected at the TLS level is also valid
      }
      expect(rejected, isTrue);
      expect(idle.every((d) => !d.closed), isTrue);
    });
  });
}
