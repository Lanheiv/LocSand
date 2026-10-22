import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/auth_protocol.dart';

Uint8List transcript({
  String role = 'client',
  String clientId = 'c',
  String serverId = 's',
  String clientNonce = 'cn',
  String serverNonce = 'sn',
  List<int> cert = const [1, 2, 3],
}) =>
    authTranscript(
      role: role,
      clientId: clientId,
      serverId: serverId,
      clientNonce: clientNonce,
      serverNonce: serverNonce,
      serverCertDer: Uint8List.fromList(cert),
    );

void main() {
  group('deviceIdPattern', () {
    test('accepts 64 lowercase hexadecimal characters', () {
      expect(deviceIdPattern.hasMatch('a' * 64), isTrue);
      expect(deviceIdPattern.hasMatch('0123456789abcdef' * 4), isTrue);
    });

    test('rejects wrong length, uppercase letters and other characters', () {
      expect(deviceIdPattern.hasMatch('a' * 63), isFalse);
      expect(deviceIdPattern.hasMatch('a' * 65), isFalse);
      expect(deviceIdPattern.hasMatch('A' * 64), isFalse);
      expect(deviceIdPattern.hasMatch('g' * 64), isFalse);
      expect(deviceIdPattern.hasMatch('${'a' * 63}\n'), isFalse);
      expect(deviceIdPattern.hasMatch(''), isFalse);
    });
  });

  group('deviceIdFromPublicKey', () {
    test('is the SHA-256 of the key text', () {
      expect(deviceIdFromPublicKey('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('result matches the ID format and is deterministic', () {
      final id = deviceIdFromPublicKey('-----BEGIN PUBLIC KEY-----x');
      expect(deviceIdPattern.hasMatch(id), isTrue);
      expect(deviceIdFromPublicKey('-----BEGIN PUBLIC KEY-----x'), id);
      expect(deviceIdFromPublicKey('another key'), isNot(id));
    });
  });

  group('newNonce', () {
    test('length satisfies the server check (16..64) and is unique', () {
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        final n = newNonce();
        expect(n.length, inInclusiveRange(16, 64));
        seen.add(n);
      }
      expect(seen.length, 200);
    });

    test('contains only URL-safe base64 characters', () {
      expect(RegExp(r'^[A-Za-z0-9_\-=]+$').hasMatch(newNonce()), isTrue);
    });
  });

  group('authTranscript', () {
    test('is deterministic', () {
      expect(transcript(), transcript());
    });

    test('structure: version, role, IDs, nonces, certificate hash', () {
      final decoded = jsonDecode(utf8.decode(transcript())) as List<dynamic>;
      expect(decoded, [
        'locsand-auth-v1',
        'client',
        'c',
        's',
        'cn',
        'sn',
        sha256.convert([1, 2, 3]).toString(),
      ]);
    });

    test('changing any field changes the data to be signed', () {
      final base = transcript();
      expect(transcript(role: 'server'), isNot(base));
      expect(transcript(clientId: 'x'), isNot(base));
      expect(transcript(serverId: 'x'), isNot(base));
      expect(transcript(clientNonce: 'x'), isNot(base));
      expect(transcript(serverNonce: 'x'), isNot(base));
      expect(transcript(cert: [9, 9, 9]), isNot(base));
    });
  });

  group('pemToDer', () {
    test('strips headers and decodes base64', () {
      final pem = '-----BEGIN CERTIFICATE-----\n'
          '${base64Encode([1, 2, 3, 4, 5])}\n'
          '-----END CERTIFICATE-----\n';
      expect(pemToDer(pem), [1, 2, 3, 4, 5]);
    });

    test('joins multiple lines and ignores blank lines / whitespace', () {
      final all = base64Encode(List<int>.generate(60, (i) => i));
      final pem = '-----BEGIN X-----\n  ${all.substring(0, 20)}  \n\n'
          '${all.substring(20)}\n-----END X-----';
      expect(pemToDer(pem), List<int>.generate(60, (i) => i));
    });
  });

  group('shortDeviceId', () {
    test('shows the first 16 characters in groups of 4', () {
      expect(shortDeviceId('a1b2c3d4e5f6a7b8${'f' * 48}'), 'a1b2 c3d4 e5f6 a7b8');
    });

    test('for a short ID the last group may be shorter', () {
      expect(shortDeviceId('abcdef'), 'abcd ef');
      expect(shortDeviceId(''), '');
    });
  });
}
