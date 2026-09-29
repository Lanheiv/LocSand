import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:path_provider/path_provider.dart';

(String certPem, String keyPem) _generateCertificate() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = pair.privateKey as RSAPrivateKey;
  final publicKey = pair.publicKey as RSAPublicKey;

  final csrPem = X509Utils.generateRsaCsrPem(
    {'CN': 'locsand-device'},
    privateKey,
    publicKey,
  );

  final certPem = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csrPem,
    365,
  );

  return (certPem, CryptoUtils.encodeRSAPrivateKeyToPem(privateKey));
}

class CertGenerator {
  static Future<(File pem, File key)> ensureDeviceCertificate() async {
    final dir = await getApplicationSupportDirectory();
    final pemFile = File('${dir.path}/server.pem');
    final keyFile = File('${dir.path}/server.key');

    if (await pemFile.exists() && await keyFile.exists()) {
      return (pemFile, keyFile);
    }

    final (certPem, keyPem) = await Isolate.run(_generateCertificate);

    await pemFile.writeAsString(certPem);
    await keyFile.writeAsString(keyPem);

    return (pemFile, keyFile);
  }
}
