import 'package:flutter/material.dart';

import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/saved_peer.dart';

class ChatPage extends StatefulWidget {
  final void Function(PeerData peer) onTapPeer;

  const ChatPage({super.key, required this.onTapPeer});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  @override
  void initState() {
    super.initState();
    SessionData().addListener(_onChanged);
  }

  @override
  void dispose() {
    SessionData().removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmForget(SavedPeer saved) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget connection?'),
        content: Text(
          "This removes ${saved.name} from your saved connections. "
          "It won't auto-reconnect anymore unless you save it again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SessionData().forgetSavedPeer(saved.deviceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionData();
    final saved = session.allSavedPeers..sort((a, b) => b.savedAt.compareTo(a.savedAt));

    if (saved.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No saved connections yet.\n\n'
            'Open a chat from Home and tap the bookmark icon to save it '
            'here — saved connections are remembered and reconnected to '
            'automatically the next time the app starts.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: saved.length,
      itemBuilder: (context, index) {
        final s = saved[index];
        // Prefer the live peer entry (fresher ip/port) and fall back to
        // the saved record if it hasn't been (re)discovered yet.
        final peer = session.getPeer(s.deviceId) ??
            PeerData(
              deviceId: s.deviceId,
              name: s.name,
              ip: s.lastKnownIp,
              port: s.lastKnownPort,
              lastSeen: s.savedAt,
            );
        final conn = session.getTcpConnection(s.deviceId);
        final connected = conn != null && conn.isConnected;
        final messages = session.getChatMessages(s.deviceId);
        final lastMessage = messages.isNotEmpty ? messages.last : null;

        return ListTile(
          leading: Icon(
            connected ? Icons.link : Icons.link_off,
            color: connected ? Colors.green : Colors.grey,
          ),
          title: Text(s.name),
          subtitle: Text(
            lastMessage != null
                ? lastMessage.text
                : (connected ? 'Connected' : 'Not connected · last seen at ${s.lastKnownIp}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'forget') _confirmForget(s);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'forget', child: Text('Forget')),
            ],
          ),
          onTap: () => widget.onTapPeer(peer),
        );
      },
    );
  }
}