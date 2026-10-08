import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A device id is the SHA-256 of its public key (hex). It therefore cannot be
/// chosen freely: to use id X a peer has to own the private key behind X.
final RegExp deviceIdPattern = RegExp(r'^[0-9a-f]{64}$');

String deviceIdFromPublicKey(String publicKeyPem) =>
    sha256.convert(utf8.encode(publicKeyPem)).toString();

String newNonce() {
  final rnd = Random.secure();
  return base64Url.encode(List<int>.generate(24, (_) => rnd.nextInt(256)));
}

/// The data both sides sign during the handshake. It contains both ids, both
/// nonces and the hash of the *server's TLS certificate as the client saw it*.
/// A man in the middle who terminates TLS himself presents a different
/// certificate, so the signature made by the real peer does not verify.
Uint8List authTranscript({
  required String role,
  required String clientId,
  required String serverId,
  required String clientNonce,
  required String serverNonce,
  required Uint8List serverCertDer,
}) {
  return Uint8List.fromList(utf8.encode(jsonEncode([
    'locsand-auth-v1',
    role,
    clientId,
    serverId,
    clientNonce,
    serverNonce,
    sha256.convert(serverCertDer).toString(),
  ])));
}

Uint8List pemToDer(String pem) {
  final body = pem
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return base64Decode(body);
}

/// "a1b2c3d4e5f6a7b8…" -> "a1b2 c3d4 e5f6 a7b8" (for showing to the user).
String shortDeviceId(String id) {
  final head = id.length > 16 ? id.substring(0, 16) : id;
  return [
    for (var i = 0; i < head.length; i += 4)
      head.substring(i, i + 4 > head.length ? head.length : i + 4)
  ].join(' ');
}
