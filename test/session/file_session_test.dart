import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/data/file_transfer.dart';
import 'package:locsand/src/helpers/settings_store.dart';
import 'package:locsand/src/session/file_session.dart';

import '../support/test_host.dart';
import '../support/tls_pair.dart';

void main() {
  late Directory root;
  late Directory src;
  late Directory recv;
  late TlsPair pair;
  late TestHost a; // sender
  late TestHost b; // receiver

  setUpAll(() => root = installFakePathProvider());

  setUp(() async {
    src = Directory('${root.path}/src_${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    recv = Directory('${root.path}/recv_${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    await SettingsStore().set('receiveDir', recv.path);

    final l = await linkedHosts();
    pair = l.pair;
    a = l.a;
    b = l.b;
  });

  tearDown(() => pair.close());

  File makeFile(String name, List<int> bytes) =>
      File('${src.path}/$name')..writeAsBytesSync(bytes);

  void bAcceptsAll() => b.onIncomingFileOffer = (t, respond) => respond(true);

  bool isFinal(FileTransferStatus s) =>
      s == FileTransferStatus.completed ||
      s == FileTransferStatus.failed ||
      s == FileTransferStatus.declined;

  Future<FileTransfer> sendAndWait(File f) async {
    final t = await a.sendFile(a.peerId, f);
    await waitUntil(() => isFinal(t.status),
        timeout: const Duration(seconds: 30), reason: 'transfer to finish');
    return t;
  }

  List<String> recvNames() =>
      recv.listSync().whereType<File>().map((f) => f.path.split('/').last).toList()
        ..sort();

  /// Sends a "raw" offer (bypassing sendFile) and waits for the receiver to accept.
  Future<void> rawOfferAccepted(String id, String name, int size) async {
    bAcceptsAll();
    pair.client.send(
        {'type': 'file_offer', 'transferId': id, 'name': name, 'size': size});
    await pair.clientInbox.waitForType('file_accept');
  }

  void rawChunk(String id, List<int> bytes) => pair.client
      .send({'type': 'file_chunk', 'transferId': id, 'data': base64Encode(bytes)});

  group('successful transfer', () {
    test('a text file (UTF-8) arrives intact', () async {
      bAcceptsAll();
      const content = 'Hello, world!\nSecond line: ēūīāšņ 🙂\n';
      final t = await sendAndWait(makeFile('hello.txt', utf8.encode(content)));

      expect(t.status, FileTransferStatus.completed);
      expect(File('${recv.path}/hello.txt').readAsStringSync(), content);

      final inc = b.fileTransfersFor(b.peerId).single;
      expect(inc.status, FileTransferStatus.completed);
      expect(inc.direction, FileTransferDirection.incoming);
      expect(inc.localPath, '${recv.path}/hello.txt');
      expect(inc.bytesTransferred, utf8.encode(content).length);
    });

    test('a 700 KB binary file (several 128 KiB chunks) matches byte for byte',
        () async {
      bAcceptsAll();
      final rnd = Random(42);
      final bytes = Uint8List.fromList(List<int>.generate(700000, (_) => rnd.nextInt(256)));
      final t = await sendAndWait(makeFile('data.bin', bytes));

      expect(t.status, FileTransferStatus.completed);
      expect(t.bytesTransferred, bytes.length);
      expect(t.progress, 1.0);
      expect(File('${recv.path}/data.bin').readAsBytesSync(), bytes);
      expect(b.fileTransfersFor(b.peerId).single.progress, 1.0);
    });

    test('an empty file (0 bytes)', () async {
      bAcceptsAll();
      final t = await sendAndWait(makeFile('empty.txt', []));
      expect(t.status, FileTransferStatus.completed);
      expect(File('${recv.path}/empty.txt').lengthSync(), 0);
    });

    test('no .locsand-part files remain after the transfer', () async {
      bAcceptsAll();
      await sendAndWait(makeFile('a.txt', utf8.encode('abc')));
      expect(recvNames(), ['a.txt']);
    });

    test('same name → "name (1).txt", the original is not overwritten',
        () async {
      bAcceptsAll();
      await sendAndWait(makeFile('dup.txt', utf8.encode('first')));
      await sendAndWait(makeFile('dup.txt', utf8.encode('second')));
      await sendAndWait(makeFile('dup.txt', utf8.encode('third')));

      expect(recvNames(), ['dup (1).txt', 'dup (2).txt', 'dup.txt']);
      expect(File('${recv.path}/dup.txt').readAsStringSync(), 'first');
      expect(File('${recv.path}/dup (1).txt').readAsStringSync(), 'second');
      expect(File('${recv.path}/dup (2).txt').readAsStringSync(), 'third');
    });

    test('multiple files in a row, history ordered by time', () async {
      bAcceptsAll();
      await sendAndWait(makeFile('1.txt', [1]));
      await sendAndWait(makeFile('2.txt', [2]));
      expect(b.fileTransfersFor(b.peerId).map((t) => t.name), ['1.txt', '2.txt']);
      expect(a.fileTransfersFor(a.peerId).length, 2);
    });

    test('progress notifications reach UI listeners', () async {
      bAcceptsAll();
      var n = 0;
      a.addListener(() => n++);
      await sendAndWait(makeFile('p.bin', Uint8List(400000)));
      expect(n, greaterThan(1));
    });
  });

  group('declining', () {
    test('receiver declines → declined on both sides, no file is created', () async {
      b.onIncomingFileOffer = (t, respond) => respond(false);
      final t = await sendAndWait(makeFile('no.txt', utf8.encode('x')));

      expect(t.status, FileTransferStatus.declined);
      expect(b.fileTransfersFor(b.peerId).single.status, FileTransferStatus.declined);
      expect(recvNames(), isEmpty);
    });

    test('no UI handler → the offer is automatically declined', () async {
      final t = await sendAndWait(makeFile('x.txt', [1]));
      expect(t.status, FileTransferStatus.declined);
    });

    test('sendFile without a connection throws StateError', () async {
      await pair.client.disconnect();
      await expectLater(
        a.sendFile(a.peerId, makeFile('x.txt', [1])),
        throwsStateError,
      );
    });
  });

  group('security — incoming offers', () {
    test('path injection ("../../evil.txt") cannot escape the receive folder',
        () async {
      await rawOfferAccepted('evil-1', '../../evil.txt', 3);
      rawChunk('evil-1', [1, 2, 3]);
      pair.client.send({'type': 'file_complete', 'transferId': 'evil-1'});
      await waitUntil(
          () => b.fileTransfers['evil-1']?.status == FileTransferStatus.completed);

      expect(b.fileTransfers['evil-1']!.name, 'evil.txt');
      expect(File('${recv.path}/evil.txt').existsSync(), isTrue);
      expect(File('${recv.parent.path}/evil.txt').existsSync(), isFalse);
      expect(File('${recv.parent.parent.path}/evil.txt').existsSync(), isFalse);
    });

    test('a Windows path and reserved name are sanitized', () async {
      await rawOfferAccepted('w-1', r'C:\temp\con.txt', 1);
      expect(b.fileTransfers['w-1']!.name, '_con.txt');
    });

    test('invalid offers are ignored without crashing', () async {
      b.onIncomingFileOffer = (t, respond) => respond(false);
      final bad = <Map<String, dynamic>>[
        {'transferId': '', 'name': 'a', 'size': 1},
        {'transferId': 'x' * 129, 'name': 'a', 'size': 1},
        {'transferId': 'n1', 'name': '', 'size': 1},
        {'transferId': 'n2', 'name': 'a' * 1025, 'size': 1},
        {'transferId': 'n3', 'name': 'a', 'size': -1},
        {'transferId': 'n4', 'name': 'a', 'size': '5'},
        {'transferId': 'n5', 'name': 5, 'size': 1},
        {'transferId': 5, 'name': 'a', 'size': 1},
        {'name': 'a', 'size': 1},
      ];
      for (final m in bad) {
        pair.client.send({'type': 'file_offer', ...m});
      }
      pair.client.send(
          {'type': 'file_offer', 'transferId': 'good', 'name': 'g.txt', 'size': 1});
      await pair.clientInbox.waitFor(
          (m) => m['type'] == 'file_decline' && m['transferId'] == 'good');
      expect(b.fileTransfers.keys.toList(), ['good']);
    });

    test('no more than 3 unanswered offers at the same time', () async {
      b.onIncomingFileOffer = (t, respond) {}; // the user does not respond
      for (final id in ['o1', 'o2', 'o3', 'o4']) {
        pair.client.send(
            {'type': 'file_offer', 'transferId': id, 'name': '$id.txt', 'size': 1});
      }
      final declined = await pair.clientInbox
          .waitFor((m) => m['type'] == 'file_decline');
      expect(declined['transferId'], 'o4');
      expect(b.fileTransfers.keys.toSet(), {'o1', 'o2', 'o3'});
    });

    test('a file above the 8 GiB limit is automatically declined', () async {
      b.onIncomingFileOffer = (t, respond) => respond(true);
      pair.client.send({
        'type': 'file_offer',
        'transferId': 'huge',
        'name': 'huge.iso',
        'size': FileSession.maxFileBytes + 1,
      });
      final m = await pair.clientInbox.waitForType('file_decline');
      expect(m['transferId'], 'huge');
      expect(b.fileTransfers, isEmpty);
    });

    test('a repeated offer with the same transferId is ignored', () async {
      b.onIncomingFileOffer = (t, respond) {};
      for (var i = 0; i < 2; i++) {
        pair.client.send(
            {'type': 'file_offer', 'transferId': 'same', 'name': 'a.txt', 'size': 1});
      }
      pair.client.send(
          {'type': 'file_offer', 'transferId': 'other', 'name': 'b.txt', 'size': 1});
      await waitUntil(() => b.fileTransfers.length == 2);
      expect(b.fileTransfers.keys.toSet(), {'same', 'other'});
    });
  });

  group('security — invalid chunks', () {
    Future<void> expectFailedAndCleaned(String id) async {
      await waitUntil(() => b.fileTransfers[id]!.status == FileTransferStatus.failed);
      await waitUntil(() => recvNames().isEmpty,
          reason: 'the .locsand-part file must be deleted');
    }

    test('a base64 chunk above 180 KiB → the transfer is aborted', () async {
      await rawOfferAccepted('big', 'a.bin', 10);
      pair.client.send({
        'type': 'file_chunk',
        'transferId': 'big',
        'data': 'A' * (181 * 1024),
      });
      await expectFailedAndCleaned('big');
      await pair.clientInbox.waitFor(
          (m) => m['type'] == 'file_decline' && m['transferId'] == 'big');
    });

    test('more data than the declared size → abort', () async {
      await rawOfferAccepted('over', 'a.bin', 4);
      rawChunk('over', [1, 2, 3, 4, 5]);
      await expectFailedAndCleaned('over');
    });

    test('invalid base64 → abort', () async {
      await rawOfferAccepted('b64', 'a.bin', 10);
      pair.client.send(
          {'type': 'file_chunk', 'transferId': 'b64', 'data': '***not base64***'});
      await expectFailedAndCleaned('b64');
    });

    test('file_complete with fewer bytes than declared → failed', () async {
      await rawOfferAccepted('short', 'a.bin', 10);
      rawChunk('short', [1, 2, 3]);
      pair.client.send({'type': 'file_complete', 'transferId': 'short'});
      await expectFailedAndCleaned('short');
    });

    test('chunks for an unknown transferId are ignored', () async {
      rawChunk('unknown', [1, 2, 3]);
      pair.client.send({'type': 'file_complete', 'transferId': 'unknown'});
      pair.client.send({'type': 'file_offer', 'transferId': 'z', 'name': 'z', 'size': 1});
      await waitUntil(() => b.fileTransfers.containsKey('z'));
      expect(b.fileTransfers.keys, ['z']);
    });

    test('chunks before acceptance (in offered status) are ignored', () async {
      b.onIncomingFileOffer = (t, respond) {}; // never accepts
      pair.client.send({'type': 'file_offer', 'transferId': 'pre', 'name': 'p', 'size': 3});
      await waitUntil(() => b.fileTransfers.containsKey('pre'));
      rawChunk('pre', [1, 2, 3]);
      pair.client.send({'type': 'file_complete', 'transferId': 'pre'});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(b.fileTransfers['pre']!.status, FileTransferStatus.offered);
      expect(b.fileTransfers['pre']!.bytesTransferred, 0);
    });

    test('file_accept / file_received for foreign transferIds affect nothing', () async {
      pair.client.send({'type': 'file_accept', 'transferId': 'none'});
      pair.client.send({'type': 'file_received', 'transferId': 'none', 'ok': true});
      pair.client.send({'type': 'file_decline', 'transferId': 'none'});
      pair.client.send({'type': 'file_offer', 'transferId': 'm', 'name': 'm', 'size': 1});
      await waitUntil(() => b.fileTransfers.containsKey('m'));
      expect(b.fileTransfers.keys, ['m']);
    });
  });

  group('connection interruption', () {
    test('an incoming transfer is aborted and the partial file is deleted', () async {
      await rawOfferAccepted('cut', 'cut.bin', 1000);
      rawChunk('cut', List<int>.filled(100, 7));
      await waitUntil(() => b.fileTransfers['cut']!.bytesTransferred == 100);
      expect(recvNames(), ['cut.bin.locsand-part']);

      await pair.client.disconnect();
      await waitUntil(() => b.fileTransfers['cut']!.status == FileTransferStatus.failed);
      await waitUntil(() => recvNames().isEmpty);
    });

    test('failTransfersFor does not touch transfers of other devices', () async {
      b.onIncomingFileOffer = (t, respond) {};
      pair.client.send({'type': 'file_offer', 'transferId': 'k', 'name': 'k', 'size': 1});
      await waitUntil(() => b.fileTransfers.containsKey('k'));
      b.failTransfersFor('other-device');
      expect(b.fileTransfers['k']!.status, FileTransferStatus.offered);
    });
  });
}
