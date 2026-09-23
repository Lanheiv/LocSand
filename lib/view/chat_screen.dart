import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/chat_message.dart';
import 'package:locsand/src/data/file_transfer.dart';

class ChatScreen extends StatefulWidget {
  final PeerData peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    SessionData().addListener(_onChanged);
  }

  @override
  void dispose() {
    SessionData().removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    try {
      SessionData().sendChatMessage(widget.peer.deviceId, text);
      _controller.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Send failed: $e")),
      );
    }
  }

  Future<void> _toggleSave() async {
    final saved = SessionData().isPeerSaved(widget.peer.deviceId);
    if (saved) {
      await SessionData().forgetSavedPeer(widget.peer.deviceId);
    } else {
      await SessionData().savePeer(widget.peer.deviceId);
    }
  }

  Future<void> _attachFile() async {
    // Using file_picker ^10.3.10 (not v11) — v11.0.0-11.0.3 has an
    // upstream Android build bug where its own android/build.gradle
    // doesn't apply the kotlin-android plugin, breaking every Android
    // build (github.com/miguelpruivo/flutter_file_picker/issues/1973).
    // 10.3.10 already inherits compileSdk from the app, so it's fine for
    // compileSdk 37 — and it's back to the instance-based API.
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path == null) return;

    try {
      await SessionData().sendFile(widget.peer.deviceId, File(path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("File send failed: $e")),
        );
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _bubble({required bool fromMe, required Widget child}) {
    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: fromMe ? Colors.blue[300] : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }

  Widget _chatBubble(ChatMessage m) {
    return _bubble(
      fromMe: m.fromMe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(m.text),
          const SizedBox(height: 2),
          Text(
            _formatTime(m.time),
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _fileBubble(FileTransfer t) {
    final fromMe = t.direction == FileTransferDirection.outgoing;

    String statusLine;
    switch (t.status) {
      case FileTransferStatus.offered:
        statusLine = fromMe ? 'Waiting for them to accept…' : 'Incoming file offer';
        break;
      case FileTransferStatus.accepted:
      case FileTransferStatus.inProgress:
        statusLine =
            '${_formatSize(t.bytesTransferred)} / ${_formatSize(t.size)} (${(t.progress * 100).toStringAsFixed(0)}%)';
        break;
      case FileTransferStatus.completed:
        statusLine = fromMe ? 'Sent' : 'Saved to ${t.localPath ?? 'device storage'}';
        break;
      case FileTransferStatus.declined:
        statusLine = fromMe ? 'Declined by peer' : 'Declined';
        break;
      case FileTransferStatus.failed:
        statusLine = 'Transfer failed';
        break;
    }

    return _bubble(
      fromMe: fromMe,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(t.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (t.status == FileTransferStatus.inProgress || t.status == FileTransferStatus.accepted)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SizedBox(
                width: 160,
                child: LinearProgressIndicator(value: t.size > 0 ? t.progress.toDouble() : null),
              ),
            ),
          Text(statusLine, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(
            _formatTime(t.startedAt),
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = SessionData().getChatMessages(widget.peer.deviceId);
    final transfers = SessionData().fileTransfersFor(widget.peer.deviceId);
    final conn = SessionData().getTcpConnection(widget.peer.deviceId);
    final connected = conn != null && conn.isConnected;
    final saved = SessionData().isPeerSaved(widget.peer.deviceId);

    // Chat messages and file transfers are separate lists in SessionData
    // (different lifecycles, different fields) but share one timeline in
    // the UI, ordered by when each happened.
    final timeline = <Object>[...messages, ...transfers]
      ..sort((a, b) {
        final ta = a is ChatMessage ? a.time : (a as FileTransfer).startedAt;
        final tb = b is ChatMessage ? b.time : (b as FileTransfer).startedAt;
        return ta.compareTo(tb);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peer.name),
        actions: [
          IconButton(
            icon: Icon(saved ? Icons.star : Icons.star_border),
            tooltip: saved ? 'Saved' : 'Save',
            onPressed: _toggleSave,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              connected ? 'Connected' : 'Not connected',
              style: TextStyle(
                fontSize: 12,
                color: connected ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: timeline.isEmpty
                ? const Center(child: Text('No messages yet.'))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: timeline.length,
                    itemBuilder: (context, index) {
                      final item = timeline[timeline.length - 1 - index];
                      return item is ChatMessage ? _chatBubble(item) : _fileBubble(item as FileTransfer);
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Send file',
                    onPressed: connected ? _attachFile : null,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: connected,
                      decoration: InputDecoration(
                        hintText: connected ? 'Type a message' : 'Not connected',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: connected ? _send : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}