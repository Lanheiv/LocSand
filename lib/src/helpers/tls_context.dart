// src/helpers/tls_context.dart
//
// Loads the app's bundled self-signed certificate and builds the
// SecurityContext objects used to encrypt every TCP connection with TLS.
//
// IMPORTANT — read this before you ship anything real:
// Every install of this app carries the SAME certificate + private key
// (see assets/certs/server.pem / server.key). That's enough to stop a
// passive eavesdropper on the LAN from reading your traffic in plain
// text, and it stops random sockets that aren't speaking this app's TLS
// setup from connecting. It does NOT prove which physical device you're
// talking to, because anyone who extracts the key from the app package
// has the same identity as every other peer.
//
// A proper fix later: generate a fresh key pair per device on first
// launch, and have peers pin each other's certificate fingerprint
// (e.g. include a SHA-256 hash of the cert in the UDP discovery
// message and refuse to connect if the TLS handshake presents a
// different one). That needs a cert-generation package since dart:io
// alone can't mint new certificates on-device.

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

  /// Context used by outgoing client connections. We do NOT trust the
  /// normal public CA list (withTrustedRoots: false) — the only
  /// certificate we're willing to trust is the one bundled with this
  /// app, so we only ever connect to other instances of it.
  static Future<SecurityContext> clientContext() async {
    if (_clientContext != null) return _clientContext!;

    final certBytes = await _loadAsset('assets/certs/server.pem');

    final context = SecurityContext(withTrustedRoots: false);
    context.setTrustedCertificatesBytes(certBytes);

    _clientContext = context;
    return context;
  }
}
