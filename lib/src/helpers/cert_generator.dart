import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:locsand/src/helpers/atomic_file.dart';
import 'package:path_provider/path_provider.dart';

typedef DeviceKeyFiles = ({File cert, File key, File publicKey});

(String certPem, String keyPem, String publicKeyPem) _generateIdentity() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = pair.privateKey as RSAPrivateKey;
  final publicKey = pair.publicKey as RSAPublicKey;

  final csrPem = X509Utils.generateRsaCsrPem(
    {'CN': 'locsand-device'},
    privateKey,
    publicKey,
  );

  // The certificate only wraps the key for TLS transport. The device identity
  // is the public key itself (see DeviceIdentity), so expiry of this wrapper
  // does not matter; use a long validity instead of a rotation scheme.
  final certPem = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csrPem,
    3650,
  );

  return (
    certPem,
    CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    CryptoUtils.encodeRSAPublicKeyToPem(publicKey),
  );
}

class CertGenerator {
  static Future<DeviceKeyFiles>? _inFlight;

  static Future<DeviceKeyFiles> ensureDeviceCertificate() =>
      _inFlight ??= _ensure();

  static Future<DeviceKeyFiles> _ensure() async {
    final dir = await getApplicationSupportDirectory();
    final cert = File('${dir.path}/server.pem');
    final key = File('${dir.path}/server.key');
    final publicKey = File('${dir.path}/identity.pub.pem');

    // identity.pub.pem is written last, so its presence means the set is
    // complete. Installs from before the identity change have no such file and
    // get a fresh key pair (and therefore a new device id).
    if (await cert.exists() && await key.exists() && await publicKey.exists()) {
      return (cert: cert, key: key, publicKey: publicKey);
    }

    final (certPem, keyPem, publicKeyPem) = await Isolate.run(_generateIdentity);

    await writeFileAtomic(key, keyPem);
    await _restrictToOwner(key);
    await writeFileAtomic(cert, certPem);
    await writeFileAtomic(publicKey, publicKeyPem);

    return (cert: cert, key: key, publicKey: publicKey);
  }

  static Future<void> _restrictToOwner(File file) async {
    if (!(Platform.isLinux || Platform.isMacOS)) return;
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {}
  }
}
