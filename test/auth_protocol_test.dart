import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/auth_protocol.dart';
import 'package:locsand/src/helpers/device_identity.dart';

Uint8List _transcript({
  String role = 'client',
  String clientId = 'c',
  String serverId = 's',
  String cn = 'cn',
  String sn = 'sn',
  List<int> cert = const [1, 2, 3],
}) =>
    authTranscript(
      role: role,
      clientId: clientId,
      serverId: serverId,
      clientNonce: cn,
      serverNonce: sn,
      serverCertDer: Uint8List.fromList(cert),
    );

void main() {
  test('device id is the SHA-256 of the public key and cannot be chosen freely', () {
    final id = deviceIdFromPublicKey('-----BEGIN PUBLIC KEY-----abc');
    expect(deviceIdPattern.hasMatch(id), isTrue);
    expect(deviceIdFromPublicKey('-----BEGIN PUBLIC KEY-----abc'), id);
    expect(deviceIdFromPublicKey('-----BEGIN PUBLIC KEY-----abd'), isNot(id));
  });

  test('nonces are unique and long enough', () {
    final a = newNonce(), b = newNonce();
    expect(a, isNot(b));
    expect(a.length, greaterThanOrEqualTo(16));
  });

  test('the transcript changes when any bound value changes', () {
    final base = _transcript();
    expect(_transcript(), base);
    expect(_transcript(role: 'server'), isNot(base));
    expect(_transcript(clientId: 'x'), isNot(base));
    expect(_transcript(serverId: 'x'), isNot(base));
    expect(_transcript(cn: 'x'), isNot(base));
    expect(_transcript(sn: 'x'), isNot(base));
    // A man in the middle presents a different TLS certificate:
    expect(_transcript(cert: const [9, 9, 9]), isNot(base));
  });

  test('pemToDer decodes the certificate body', () {
    final der = Uint8List.fromList(List<int>.generate(40, (i) => i));
    final pem = '-----BEGIN CERTIFICATE-----\r\n${base64Encode(der)}\r\n-----END CERTIFICATE-----\r\n';
    expect(pemToDer(pem), der);
  });

  test('a signature verifies only for the right key and the right transcript', () {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final other = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final priv = pair.privateKey as RSAPrivateKey;
    final pubPem = CryptoUtils.encodeRSAPublicKeyToPem(pair.publicKey as RSAPublicKey);
    final otherPem = CryptoUtils.encodeRSAPublicKeyToPem(other.publicKey as RSAPublicKey);

    final data = _transcript();
    final sig = CryptoUtils.rsaSign(priv, data);

    expect(DeviceIdentity.verify(pubPem, data, sig), isTrue);
    expect(DeviceIdentity.verify(otherPem, data, sig), isFalse, reason: 'wrong key');
    expect(DeviceIdentity.verify(pubPem, _transcript(cn: 'replayed'), sig), isFalse,
        reason: 'different handshake');
    expect(DeviceIdentity.verify('garbage', data, sig), isFalse);
  });

  test('shortDeviceId groups the first 16 characters', () {
    expect(shortDeviceId('0123456789abcdef0000'), '0123 4567 89ab cdef');
  });
}
