import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/data/chat_message.dart';
import 'package:locsand/src/data/file_transfer.dart';
import 'package:locsand/src/data/saved_peer.dart';

void main() {
  group('ChatMessage', () {
    test('JSON round trip', () {
      final m = ChatMessage(
          text: 'Hello\nā', fromMe: true, time: DateTime.utc(2026, 10, 16, 8, 30));
      final back = ChatMessage.fromJson(
          jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>);
      expect(back.text, m.text);
      expect(back.fromMe, true);
      expect(back.time.toUtc(), m.time);
    });

    test('missing fields get default values', () {
      final m = ChatMessage.fromJson({});
      expect(m.text, '');
      expect(m.fromMe, false);
      expect(m.time, isA<DateTime>());
    });

    test('an invalid time is rejected without throwing', () {
      expect(ChatMessage.fromJson({'time': 'not a date'}).time, isA<DateTime>());
    });
  });

  group('SavedPeer', () {
    test('JSON round trip', () {
      final p = SavedPeer(
        deviceId: 'a' * 64,
        name: 'Test Phone',
        lastKnownIp: '192.168.1.5',
        lastKnownPort: 5000,
        savedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final back = SavedPeer.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(back.deviceId, p.deviceId);
      expect(back.name, 'Test Phone');
      expect(back.lastKnownIp, '192.168.1.5');
      expect(back.lastKnownPort, 5000);
      expect(back.savedAt.toUtc(), p.savedAt);
    });

    test('IP and port are optional', () {
      final p = SavedPeer.fromJson({
        'deviceId': 'x',
        'name': 'n',
        'savedAt': '2026-01-01T00:00:00.000Z',
      });
      expect(p.lastKnownIp, '');
      expect(p.lastKnownPort, 0);
    });

    test('a missing required field throws', () {
      expect(() => SavedPeer.fromJson({'name': 'n'}), throwsA(anything));
    });
  });

  group('FileTransfer.progress', () {
    FileTransfer t(int size, int done) => FileTransfer(
          transferId: 'id',
          deviceId: 'd',
          name: 'f',
          size: size,
          direction: FileTransferDirection.incoming,
          startedAt: DateTime.now(),
          bytesTransferred: done,
        );

    test('an empty file has progress = 0 (no division by zero)', () {
      expect(t(0, 0).progress, 0);
    });

    test('halfway', () => expect(t(200, 100).progress, 0.5));
    test('completed', () => expect(t(200, 200).progress, 1.0));
    test('does not exceed 1', () => expect(t(100, 500).progress, 1.0));

    test('initial status is offered', () {
      expect(t(1, 0).status, FileTransferStatus.offered);
    });
  });
}
