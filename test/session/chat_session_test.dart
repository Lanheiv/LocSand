import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/chat_history_store.dart';
import 'package:locsand/src/session/chat_session.dart';

import '../support/test_host.dart';
import '../support/tls_pair.dart';

void main() {
  late Directory root;
  late TlsPair pair;
  late TestHost a;
  late TestHost b;

  setUpAll(() => root = installFakePathProvider());

  setUp(() async {
    final l = await linkedHosts();
    pair = l.pair;
    a = l.a;
    b = l.b;
  });
  tearDown(() => pair.close());

  test('message reaches the other side with correct fromMe on both sides', () async {
    a.sendChatMessage(a.peerId, 'Hello!');
    await waitUntil(() => b.getChatMessages(b.peerId).length == 1);

    final got = b.getChatMessages(b.peerId).single;
    expect(got.text, 'Hello!');
    expect(got.fromMe, isFalse);

    final mine = a.getChatMessages(a.peerId).single;
    expect(mine.text, 'Hello!');
    expect(mine.fromMe, isTrue);
  });

  test('two-way conversation preserves order', () async {
    a.sendChatMessage(a.peerId, '1');
    await waitUntil(() => b.getChatMessages(b.peerId).length == 1);
    b.sendChatMessage(b.peerId, '2');
    await waitUntil(() => a.getChatMessages(a.peerId).length == 2);
    a.sendChatMessage(a.peerId, '3');
    await waitUntil(() => b.getChatMessages(b.peerId).length == 3);

    expect(a.getChatMessages(a.peerId).map((m) => m.text), ['1', '2', '3']);
    expect(b.getChatMessages(b.peerId).map((m) => m.text), ['1', '2', '3']);
  });

  test('Unicode, newlines and emoji', () async {
    const text = 'Good day!\nĒūīāšņ 🙂\n"quotes" \\';
    a.sendChatMessage(a.peerId, text);
    await waitUntil(() => b.getChatMessages(b.peerId).isNotEmpty);
    expect(b.getChatMessages(b.peerId).single.text, text);
  });

  test('a message of exactly the maximum length (8000) is sent', () async {
    final text = 'x' * ChatSession.maxMessageLength;
    a.sendChatMessage(a.peerId, text);
    await waitUntil(() => b.getChatMessages(b.peerId).isNotEmpty);
    expect(b.getChatMessages(b.peerId).single.text.length, 8000);
  });

  test('an over-long message cannot be sent and is not added to history', () {
    expect(
      () => a.sendChatMessage(a.peerId, 'x' * (ChatSession.maxMessageLength + 1)),
      throwsStateError,
    );
    expect(a.getChatMessages(a.peerId), isEmpty);
  });

  test('a received over-long message is truncated to 8000', () async {
    pair.client.send({'type': 'chat', 'text': 'y' * 9000});
    await waitUntil(() => b.getChatMessages(b.peerId).isNotEmpty);
    expect(b.getChatMessages(b.peerId).single.text.length, 8000);
  });

  test('an empty message is ignored', () async {
    pair.client.send({'type': 'chat', 'text': ''});
    pair.client.send({'type': 'chat', 'text': 'marker'});
    await waitUntil(() => b.getChatMessages(b.peerId).isNotEmpty);
    expect(b.getChatMessages(b.peerId).map((m) => m.text), ['marker']);
  });

  test('chat without a "text" field does not cause an error', () async {
    pair.client.send({'type': 'chat'});
    pair.client.send({'type': 'chat', 'text': 'ok'});
    await waitUntil(() => b.getChatMessages(b.peerId).isNotEmpty);
    expect(b.getChatMessages(b.peerId).single.text, 'ok');
  });

  test('sending without a connection throws StateError', () async {
    await pair.client.disconnect();
    expect(() => a.sendChatMessage(a.peerId, 'x'), throwsStateError);
  });

  test('listeners are notified about conversation changes', () async {
    var notified = 0;
    b.addListener(() => notified++);
    a.sendChatMessage(a.peerId, 'x');
    await waitUntil(() => notified > 0);
  });

  group('history persistence', () {
    test('history is not saved by default', () async {
      expect(await b.isChatHistorySavingEnabled(b.peerId), isFalse);
      a.sendChatMessage(a.peerId, 'do not save');
      await waitUntil(() => b.getChatMessages(b.peerId).isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final fresh = TestHost('x', peerId: b.peerId);
      await fresh.ensureChatHistoryLoaded(b.peerId);
      expect(fresh.getChatMessages(b.peerId), isEmpty);
    });

    test('enabled history survives a "restart" (a new host loads from file)',
        () async {
      await b.setChatHistorySaving(b.peerId, true);
      expect(await b.isChatHistorySavingEnabled(b.peerId), isTrue);

      a.sendChatMessage(a.peerId, 'one');
      await waitUntil(() => b.getChatMessages(b.peerId).length == 1);
      a.sendChatMessage(a.peerId, 'two');
      await waitUntil(() => b.getChatMessages(b.peerId).length == 2);
      // saving happens asynchronously after the message is added
      await ChatHistoryStore().isEnabled(b.peerId);

      final fresh = TestHost('x', peerId: b.peerId);
      await fresh.ensureChatHistoryLoaded(b.peerId);
      expect(fresh.getChatMessages(b.peerId).map((m) => m.text), ['one', 'two']);
    });

    test('deleteChatHistory deletes the history and disables saving', () async {
      await b.setChatHistorySaving(b.peerId, true);
      a.sendChatMessage(a.peerId, 'to be deleted');
      await waitUntil(() => b.getChatMessages(b.peerId).length == 1);
      await ChatHistoryStore().isEnabled(b.peerId);

      await b.deleteChatHistory(b.peerId);
      expect(b.getChatMessages(b.peerId), isEmpty);
      expect(await b.isChatHistorySavingEnabled(b.peerId), isFalse);

      final fresh = TestHost('x', peerId: b.peerId);
      await fresh.ensureChatHistoryLoaded(b.peerId);
      expect(fresh.getChatMessages(b.peerId), isEmpty);
    });

    test('clearAllChatHistory clears memory and files', () async {
      await b.setChatHistorySaving(b.peerId, true);
      a.sendChatMessage(a.peerId, 'x');
      await waitUntil(() => b.getChatMessages(b.peerId).length == 1);
      await ChatHistoryStore().isEnabled(b.peerId);

      await b.clearAllChatHistory();
      expect(b.chatMessages, isEmpty);
      final dir = Directory('${root.path}/chat_history');
      expect(dir.listSync().whereType<File>(), isEmpty);
    });

    test('a corrupted history file is quarantined instead of crashing', () async {
      final id = 'corrupt-${DateTime.now().microsecondsSinceEpoch}';
      final dir = Directory('${root.path}/chat_history')..createSync(recursive: true);
      File('${dir.path}/$id.json').writeAsStringSync('{not json');

      final host = TestHost('x', peerId: id);
      await host.ensureChatHistoryLoaded(id);
      expect(host.getChatMessages(id), isEmpty);
      expect(
        dir.listSync().any((e) => e.path.contains('$id.json.corrupt-')),
        isTrue,
      );
    });
  });
}
