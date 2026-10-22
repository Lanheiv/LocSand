import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/auth_protocol.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

typedef Json = Map<String, dynamic>;

/// Replaces path_provider with a temporary folder so tests never touch real data.
class FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getDownloadsPath() async => root;
}

Directory installFakePathProvider() {
  final dir = Directory.systemTemp.createTempSync('locsand_test_');
  PathProviderPlatform.instance = FakePathProvider(dir.path);
  return dir;
}

/// Waits until the condition becomes true (or the test fails with a timeout).
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for condition${reason == null ? '' : ': $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<int> freeTcpPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

Future<int> freeUdpPort() async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  s.close();
  return p;
}

/// Collects received JSON messages with "wait until a matching message arrives".
class Inbox {
  final List<Json> items = [];
  final List<(bool Function(Json), Completer<Json>)> _waiters = [];
  void Function(Json)? tap;

  void add(Json m) {
    items.add(m);
    tap?.call(m);
    for (final w in _waiters.toList()) {
      if (w.$1(m)) {
        _waiters.remove(w);
        w.$2.complete(m);
      }
    }
  }

  Iterable<Json> ofType(String type) => items.where((m) => m['type'] == type);

  Future<Json> waitFor(
    bool Function(Json) test, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    for (final m in items) {
      if (test(m)) return Future.value(m);
    }
    final c = Completer<Json>();
    _waiters.add((test, c));
    return c.future.timeout(timeout, onTimeout: () {
      throw TestFailure(
          'Timed out waiting for message. Received types: ${items.map((m) => m['type']).toList()}');
    });
  }

  Future<Json> waitForType(String type, {Duration? timeout}) => waitFor(
        (m) => m['type'] == type,
        timeout: timeout ?? const Duration(seconds: 5),
      );
}

Future<({SecurityContext context, Uint8List certDer})>? _identity;

Future<({SecurityContext context, Uint8List certDer})> _serverIdentity() =>
    _identity ??= () async {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final priv = pair.privateKey as RSAPrivateKey;
      final pub = pair.publicKey as RSAPublicKey;
      final csr = X509Utils.generateRsaCsrPem({'CN': 'locsand-test'}, priv, pub);
      final certPem = X509Utils.generateSelfSignedCertificate(priv, csr, 30);

      final dir = Directory.systemTemp.createTempSync('locsand_tls_');
      final certFile = File('${dir.path}/cert.pem')..writeAsStringSync(certPem);
      final keyFile = File('${dir.path}/key.pem')
        ..writeAsStringSync(CryptoUtils.encodeRSAPrivateKeyToPem(priv));
      final ctx = SecurityContext()
        ..useCertificateChain(certFile.path)
        ..usePrivateKey(keyFile.path);
      return (context: ctx, certDer: pemToDer(certPem));
    }();

/// Two genuinely connected [TcpPeerConnection]s (TLS, 127.0.0.1): `client`
/// dialed, `server` accepted the connection.
class TlsPair {
  late TcpPeerConnection client;
  late TcpPeerConnection server;
  late Uint8List serverCertDer;
  late SecureServerSocket _listener;

  final Inbox clientInbox = Inbox();
  final Inbox serverInbox = Inbox();

  bool clientClosed = false;
  bool serverClosed = false;
  void Function()? onClientClosed;
  void Function()? onServerClosed;

  static Future<TlsPair> open() async {
    final p = TlsPair();
    final id = await _serverIdentity();
    p.serverCertDer = id.certDer;
    p._listener =
        await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, id.context);

    final accepted = Completer<TcpPeerConnection>();
    p._listener.listen((socket) {
      accepted.complete(TcpPeerConnection.fromSocket(
        socket: socket,
        onMessage: p.serverInbox.add,
        onDisconnected: () {
          p.serverClosed = true;
          p.onServerClosed?.call();
        },
      ));
    });

    p.client = TcpPeerConnection(
      ip: '127.0.0.1',
      port: p._listener.port,
      onMessage: p.clientInbox.add,
      onDisconnected: () {
        p.clientClosed = true;
        p.onClientClosed?.call();
      },
    );
    await p.client.connect();
    p.server = await accepted.future.timeout(const Duration(seconds: 5));
    return p;
  }

  Future<void> close() async {
    await client.disconnect();
    await server.disconnect();
    await _listener.close();
  }
}

/// The server is a regular [TcpPeerConnection], but the client is a raw TLS
/// socket end so that deliberately malformed data can be sent (impossible
/// through `send()`).
class RawPair {
  late SecureSocket raw;
  late TcpPeerConnection server;
  late SecureServerSocket _listener;
  final Inbox serverInbox = Inbox();
  bool serverClosed = false;

  static Future<RawPair> open() async {
    final p = RawPair();
    final id = await _serverIdentity();
    p._listener =
        await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, id.context);
    final accepted = Completer<TcpPeerConnection>();
    p._listener.listen((socket) {
      accepted.complete(TcpPeerConnection.fromSocket(
        socket: socket,
        onMessage: p.serverInbox.add,
        onDisconnected: () => p.serverClosed = true,
      ));
    });
    p.raw = await SecureSocket.connect(
      '127.0.0.1',
      p._listener.port,
      context: SecurityContext(withTrustedRoots: false),
      onBadCertificate: (_) => true,
    );
    p.raw.listen((_) {}, onError: (_) {}, onDone: () {});
    p.server = await accepted.future.timeout(const Duration(seconds: 5));
    return p;
  }

  void write(String s) => raw.add(utf8.encode(s));
  void writeBytes(List<int> b) => raw.add(b);

  Future<void> close() async {
    raw.destroy();
    await server.disconnect();
    await _listener.close();
  }
}
