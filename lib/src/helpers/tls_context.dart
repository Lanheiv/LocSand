import 'dart:io';

import 'package:locsand/src/helpers/cert_generator.dart';

class TlsContext {
  static SecurityContext? _serverContext;
  static SecurityContext? _clientContext;

  static Future<SecurityContext> serverContext() async {
    if (_serverContext != null) return _serverContext!;

    final (pemFile, keyFile) = await CertGenerator.ensureDeviceCertificate();

    final context = SecurityContext();
    context.useCertificateChain(pemFile.path);
    context.usePrivateKey(keyFile.path);

    _serverContext = context;
    return context;
  }
  static Future<SecurityContext> clientContext() async {
    if (_clientContext != null) return _clientContext!;

    // No certificate is loaded here on purpose: presenting one only
    // matters if the server requests it, and TcpPeerServer deliberately
    // doesn't (see the note in tcp_server.dart — requesting a client
    // certificate makes Dart's TLS stack verify it against trusted roots,
    // which always fails for self-signed certs and aborts the handshake).
    final context = SecurityContext(withTrustedRoots: false);

    _clientContext = context;
    return context;
  }
}