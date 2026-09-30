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

    final context = SecurityContext(withTrustedRoots: false);

    _clientContext = context;
    return context;
  }
}