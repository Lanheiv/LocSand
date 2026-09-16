import 'dart:io';
import 'package:basic_utils/basic_utils.dart';
import 'package:path_provider/path_provider.dart';

class CertGenerator {
  static Future<(File pem, File key)> ensureDeviceCertificate() async {
    final dir = await getApplicationSupportDirectory();
    final pemFile = File('${dir.path}/server.pem');
    final keyFile = File('${dir.path}/server.key');

    if (await pemFile.exists() && await keyFile.exists()) {
      return (pemFile, keyFile);
    }

    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;

    // Build a real CSR first, then self-sign it. The previous code passed
    // an always-empty string here, which produced an invalid certificate.
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

    await pemFile.writeAsString(certPem);
    await keyFile.writeAsString(CryptoUtils.encodeRSAPrivateKeyToPem(privateKey));

    return (pemFile, keyFile);
  }
}