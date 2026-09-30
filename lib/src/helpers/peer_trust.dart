import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum TrustResult {
  newlyTrusted,

  trusted,

  mismatch,
}

class PeerTrustStore {
  static final PeerTrustStore _instance = PeerTrustStore._internal();
  factory PeerTrustStore() => _instance;
  PeerTrustStore._internal();

  Map<String, String> _fingerprints = {};
  File? _file;
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/peer_trust.json');

    if (await _file!.exists()) {
      try {
        final content = await _file!.readAsString();
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        _fingerprints = decoded.map((k, v) => MapEntry(k, v as String));
      } catch (_) {
        _fingerprints = {};
      }
    }
    _loaded = true;
  }

  static String _fingerprintOf(X509Certificate cert) {
    return cert.sha1.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  TrustResult evaluateSync(String deviceId, X509Certificate cert) {
    final fingerprint = _fingerprintOf(cert);
    final known = _fingerprints[deviceId];

    if (known == null) {
      _fingerprints[deviceId] = fingerprint;
      unawaited(_save());
      return TrustResult.newlyTrusted;
    }

    if (known == fingerprint) {
      return TrustResult.trusted;
    }

    return TrustResult.mismatch;
  }

  Future<void> forget(String deviceId) async {
    await ensureLoaded();
    if (_fingerprints.remove(deviceId) != null) {
      await _save();
    }
  }

  Future<void> _save() async {
    if (_file == null) return;
    await _file!.writeAsString(jsonEncode(_fingerprints));
  }
}