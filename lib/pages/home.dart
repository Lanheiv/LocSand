import 'package:flutter/material.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/pages/chat_screen.dart';

/// A minimal home screen used just to test the chat feature:
/// lists discovered peers, connects on tap (auto-accepting incoming
/// requests), then opens the chat screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    SessionData().addListener(_onChanged);

    // Ask the user before accepting any incoming connection request.
    SessionData().onIncomingRequest = (deviceId, name, respond) {
      if (!mounted) {
        respond(false);
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Connection request'),
          content: Text('$name wants to connect. Allow it?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                respond(false);
              },
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                respond(true);
              },
              child: const Text('Accept'),
            ),
          ],
        ),
      );
    };
  }

  @override
  void dispose() {
    SessionData().removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openChat(PeerData peer) async {
    final conn = SessionData().getTcpConnection(peer.deviceId);

    if (conn == null || !conn.isConnected) {
      setState(() => _connecting = true);
      try {
        await SessionData().connectToPeer(peer.deviceId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Connect failed: $e")),
          );
        }
      } finally {
        if (mounted) setState(() => _connecting = false);
      }
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionData();
    final peers = session.allPeers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Test'),
        actions: [
          if (_connecting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Me: ${session.userName ?? "-"} (${session.userId ?? "-"})'),
          ),
          const Divider(height: 1),
          Expanded(
            child: peers.isEmpty
                ? const Center(child: Text('No peers found yet.'))
                : ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (context, index) {
                      final p = peers[index];
                      final conn = session.getTcpConnection(p.deviceId);
                      final connected = conn != null && conn.isConnected;

                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text('${p.ip}:${p.port}'),
                        leading: Icon(
                          connected ? Icons.link : Icons.link_off,
                          color: connected ? Colors.green : Colors.grey,
                        ),
                        trailing: const Icon(Icons.chat_bubble_outline),
                        onTap: () => _openChat(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
