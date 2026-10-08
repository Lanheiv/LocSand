import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:locsand/src/helpers/auth_protocol.dart';
import 'package:locsand/src/helpers/cert_generator.dart';

/// The cryptographic identity of this device. The device id is derived from
/// the public key, and [sign] proves possession of the matching private key.
class DeviceIdentity {
  DeviceIdentity._({
    required this.deviceId,
    required this.publicKeyPem,
    required this.certDer,
    required RSAPrivateKey privateKey,
  }) : _privateKey = privateKey;

  final String deviceId;
  final String publicKeyPem;

  /// DER of our own TLS certificate (used for channel binding).
  final Uint8List certDer;
  final RSAPrivateKey _privateKey;

  static Future<DeviceIdentity>? _loading;

  static Future<DeviceIdentity> load() => _loading ??= _load();

  static Future<String> loadOrCreateId() async => (await load()).deviceId;

  static Future<DeviceIdentity> _load() async {
    try {
      final files = await CertGenerator.ensureDeviceCertificate();
      final certPem = await files.cert.readAsString();
      final keyPem = await files.key.readAsString();
      final publicKeyPem = await files.publicKey.readAsString();
      return DeviceIdentity._(
        deviceId: deviceIdFromPublicKey(publicKeyPem),
        publicKeyPem: publicKeyPem,
        certDer: pemToDer(certPem),
        privateKey: CryptoUtils.rsaPrivateKeyFromPem(keyPem),
      );
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Uint8List sign(Uint8List data) => CryptoUtils.rsaSign(_privateKey, data);

  static bool verify(String publicKeyPem, Uint8List data, Uint8List signature) {
    try {
      return CryptoUtils.rsaVerify(
        CryptoUtils.rsaPublicKeyFromPem(publicKeyPem),
        data,
        signature,
      );
    } catch (_) {
      return false;
    }
  }
}
