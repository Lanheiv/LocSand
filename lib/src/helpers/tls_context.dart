import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

class TlsContext {
  static SecurityContext? _serverContext;
  static SecurityContext? _clientContext;

  static Future<Uint8List> _loadAsset(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }
  
  static Future<SecurityContext> serverContext() async {
    if (_serverContext != null) return _serverContext!;

    final certBytes = await _loadAsset('assets/certs/server.pem');
    final keyBytes = await _loadAsset('assets/certs/server.key');

    final context = SecurityContext();
    context.useCertificateChainBytes(certBytes);
    context.usePrivateKeyBytes(keyBytes);

    _serverContext = context;
    return context;
  }
  static Future<SecurityContext> clientContext() async {
    if (_clientContext != null) return _clientContext!;

    final certBytes = await _loadAsset('assets/certs/server.pem');

    final context = SecurityContext(withTrustedRoots: false);
    context.setTrustedCertificatesBytes(certBytes);

    _clientContext = context;
    return context;
  }
}
