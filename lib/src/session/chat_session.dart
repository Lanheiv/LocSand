import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locsand/src/data/chat_message.dart';
import 'package:locsand/src/helpers/chat_history_store.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

mixin ChatSession on ChangeNotifier {
  /// Same limit for sending and receiving, so our own client never sends
  /// something the other side would cut.
  static const int maxMessageLength = 8000;

  TcpPeerConnection? liveConnection(String deviceId);

  final Map<String, List<ChatMessage>> chatMessages = {};
  final Map<String, Future<void>> _historyLoads = {};

  List<ChatMessage> getChatMessages(String deviceId) =>
      chatMessages[deviceId] ?? const [];

  void receiveChatMessage(String deviceId, String text) {
    if (text.isEmpty) return;
    if (text.length > maxMessageLength) {
      text = text.substring(0, maxMessageLength);
    }
    unawaited(_addMessage(
      deviceId,
      ChatMessage(text: text, fromMe: false, time: DateTime.now()),
    ));
  }

  void sendChatMessage(String deviceId, String text) {
    final conn = liveConnection(deviceId);
    if (conn == null) throw StateError('Not connected');
    if (text.length > maxMessageLength) {
      throw StateError('Message is too long (max $maxMessageLength characters)');
    }
    conn.send({'type': 'chat', 'text': text});
    unawaited(_addMessage(
      deviceId,
      ChatMessage(text: text, fromMe: true, time: DateTime.now()),
    ));
  }

  Future<void> _addMessage(String deviceId, ChatMessage message) async {
    await ensureChatHistoryLoaded(deviceId);
    chatMessages.putIfAbsent(deviceId, () => []).add(message);
    notifyListeners();
    try {
      await ChatHistoryStore().saveIfEnabled(deviceId, chatMessages[deviceId]!);
    } catch (e) {
      debugPrint('Saving chat history failed: $e');
    }
  }

  Future<bool> isChatHistorySavingEnabled(String deviceId) =>
      ChatHistoryStore().isEnabled(deviceId);

  Future<void> setChatHistorySaving(String deviceId, bool enabled) async {
    await ensureChatHistoryLoaded(deviceId);
    await ChatHistoryStore().setEnabled(deviceId, enabled, getChatMessages(deviceId));
  }

  Future<void> ensureChatHistoryLoaded(String deviceId) {
    if (chatMessages.containsKey(deviceId)) return Future.value();
    return _historyLoads[deviceId] ??= _loadHistory(deviceId).whenComplete(() {
      _historyLoads.remove(deviceId);
    });
  }

  Future<void> _loadHistory(String deviceId) async {
    final messages = await ChatHistoryStore().load(deviceId);
    if (chatMessages.containsKey(deviceId)) return;
    chatMessages[deviceId] = messages;
    if (messages.isNotEmpty) notifyListeners();
  }

  Future<void> clearAllChatHistory() async {
    chatMessages.clear();
    notifyListeners();
    await ChatHistoryStore().deleteAll();
  }

  Future<void> deleteChatHistory(String deviceId) async {
    chatMessages.remove(deviceId);
    notifyListeners();
    await ChatHistoryStore().deleteFile(deviceId);
  }
}
