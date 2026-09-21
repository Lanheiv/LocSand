import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum TrustResult {
  /// We had no certificate on file for this deviceId, so this one was
  /// stored and accepted.
  newlyTrusted,

  /// The presented certificate matches the one we stored previously.
  trusted,

  /// The presented certificate does NOT match the one we stored previously.
  /// The caller must refuse the connection.
  mismatch,
}

/// Trust-on-first-use (TOFU) store for peer TLS certificates.
///
/// Since every device generates its own self-signed certificate (see
/// CertGenerator), there is no certificate authority to validate against.
/// Instead, the first certificate seen for a given deviceId is pinned, and
/// every later connection to that deviceId must present the same
/// certificate — otherwise we treat it as a possible impersonation attempt
/// rather than silently trusting it (which is what `onBadCertificate: (_)
/// => true` used to do).
class PeerTrustStore {
  static final PeerTrustStore _instance = PeerTrustStore._internal();
  factory PeerTrustStore() => _instance;
  PeerTrustStore._internal();

  Map<String, String> _fingerprints = {};
  File? _file;
  bool _loaded = false;
  Future<void>? _loading;

  /// Loads the trust store from disk. Safe to call repeatedly — the file is
  /// only read once.
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
        // Corrupt trust file — start clean rather than crash. Every peer
        // will simply be re-trusted on next contact.
        _fingerprints = {};
      }
    }
    _loaded = true;
  }

  static String _fingerprintOf(X509Certificate cert) {
    return cert.sha1.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Synchronous check-and-store, for use inside the synchronous
  /// `onBadCertificate` callback. [ensureLoaded] must have completed before
  /// this is called.
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

  /// Async equivalent of [evaluateSync], for call sites that can await
  /// (e.g. after receiving an incoming connection request).
  Future<TrustResult> checkAndTrust(String deviceId, X509Certificate cert) async {
    await ensureLoaded();
    return evaluateSync(deviceId, cert);
  }

  /// Removes a stored fingerprint, e.g. if the user explicitly chooses to
  /// re-trust a peer whose certificate changed.
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