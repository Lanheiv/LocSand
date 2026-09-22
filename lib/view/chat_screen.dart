import 'package:flutter/material.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/session_data.dart';

class ChatScreen extends StatefulWidget {
  final PeerData peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  bool _savingConnection = false;

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

  Future<void> _saveConnection() async {
    setState(() => _savingConnection = true);
    try {
      final accepted = await SessionData().requestSaveConnection(widget.peer.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? 'Connection saved — this device will try to auto-reconnect next time.'
                : '${widget.peer.name} declined the save request.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't save connection: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _savingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = SessionData().getChatMessages(widget.peer.deviceId);
    final conn = SessionData().getTcpConnection(widget.peer.deviceId);
    final connected = conn != null && conn.isConnected;
    final saved = SessionData().isPeerSaved(widget.peer.deviceId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peer.name),
        actions: [
          if (_savingConnection)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
              tooltip: saved
                  ? 'Saved — will auto-reconnect'
                  : (connected ? 'Save this connection' : 'Connect first to save'),
              onPressed: (!saved && connected) ? _saveConnection : null,
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
            child: messages.isEmpty
                ? const Center(child: Text('No messages yet.'))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final m = messages[messages.length - 1 - index];
                      return Align(
                        alignment: m.fromMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: m.fromMe ? Colors.blue[300] : Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m.text),
                              const SizedBox(height: 2),
                              Text(
                                '${m.time.hour.toString().padLeft(2, '0')}:${m.time.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 10, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
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