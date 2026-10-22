import 'package:flutter/foundation.dart';
import 'package:locsand/src/session/chat_session.dart';
import 'package:locsand/src/session/file_session.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

import 'tls_pair.dart';

/// Minimal stand-in for "SessionData": only chat and file session logic,
/// without the singleton and without the handshake.
class TestHost extends ChangeNotifier with ChatSession, FileSession {
  TestHost(this.userId, {required this.peerId});

  @override
  final String? userId;

  /// The remote peer's ID as seen by this host.
  final String peerId;

  TcpPeerConnection? conn;

  @override
  TcpPeerConnection? liveConnection(String deviceId) {
    final c = conn;
    return c != null && c.isConnected ? c : null;
  }

  void handleMessage(Json msg) {
    final type = msg['type'];
    if (type == 'chat') {
      receiveChatMessage(peerId, msg['text'] as String? ?? '');
    } else if (type is String && type.startsWith('file_')) {
      handleFileMessage(peerId, type, msg);
    }
  }
}

int _n = 0;

/// Two linked hosts: `a` (caller) and `b` (acceptor).
Future<({TlsPair pair, TestHost a, TestHost b})> linkedHosts() async {
  final n = ++_n;
  final aId = 'A$n';
  final bId = 'B$n';
  final pair = await TlsPair.open();
  final a = TestHost(aId, peerId: bId)..conn = pair.client;
  final b = TestHost(bId, peerId: aId)..conn = pair.server;
  pair.clientInbox.tap = a.handleMessage;
  pair.serverInbox.tap = b.handleMessage;
  pair.onClientClosed = () => a.failTransfersFor(bId);
  pair.onServerClosed = () => b.failTransfersFor(aId);
  return (pair: pair, a: a, b: b);
}
