@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/auth_protocol.dart';
import 'package:locsand/src/helpers/device_identity.dart';

import '../support/tls_pair.dart';

void main() {
  late Directory root;
  late DeviceIdentity identity;

  setUpAll(() async {
    root = installFakePathProvider();
    // The first load generates a 2048-bit RSA key (can take several seconds).
    identity = await DeviceIdentity.load();
  });

  Uint8List data(String s) => Uint8List.fromList(utf8.encode(s));

  test('ID is the SHA-256 of the public key and matches the ID format', () {
    expect(identity.deviceId, deviceIdFromPublicKey(identity.publicKeyPem));
    expect(deviceIdPattern.hasMatch(identity.deviceId), isTrue);
  });

  test('load() returns the same identity (cached)', () async {
    expect(identical(await DeviceIdentity.load(), identity), isTrue);
    expect(await DeviceIdentity.loadOrCreateId(), identity.deviceId);
  });

  test('key files are created and the certificate DER matches the file', () {
    final cert = File('${root.path}/server.pem');
    expect(cert.existsSync(), isTrue);
    expect(File('${root.path}/server.key').existsSync(), isTrue);
    expect(File('${root.path}/identity.pub.pem').existsSync(), isTrue);
    expect(pemToDer(cert.readAsStringSync()), identity.certDer);
  });

  test('a valid signature verifies with its own public key', () {
    final msg = data('locsand handshake');
    final sig = identity.sign(msg);
    expect(DeviceIdentity.verify(identity.publicKeyPem, msg, sig), isTrue);
  });

  test('tampered data does not verify', () {
    final sig = identity.sign(data('original'));
    expect(DeviceIdentity.verify(identity.publicKeyPem, data('tampered'), sig),
        isFalse);
  });

  test('a tampered signature does not verify', () {
    final msg = data('original');
    final sig = identity.sign(msg);
    final bad = Uint8List.fromList(sig)..[0] ^= 0xff;
    expect(DeviceIdentity.verify(identity.publicKeyPem, msg, bad), isFalse);
  });

  test('another device (different key) cannot forge a signature', () {
    final other = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final msg = data('original');
    final forged =
        CryptoUtils.rsaSign(other.privateKey as RSAPrivateKey, msg);
    expect(DeviceIdentity.verify(identity.publicKeyPem, msg, forged), isFalse);
  });

  test('malformed key or empty signature → false, not an exception', () {
    final msg = data('x');
    expect(DeviceIdentity.verify('not a PEM', msg, identity.sign(msg)), isFalse);
    expect(DeviceIdentity.verify(identity.publicKeyPem, msg, Uint8List(0)),
        isFalse);
  });
}
