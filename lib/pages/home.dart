// pages/home.dart
import 'package:flutter/material.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'dart:developer';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();

    // Rebuild whenever SessionData changes (e.g. a new peer is discovered
    // over UDP, or a connection's status changes).
    SessionData().addListener(_onSessionChanged);

    // Whenever a peer sends us a connection request, show a popup asking
    // whether to accept it.
    SessionData().onIncomingRequest = (deviceId, name, respond) {
      _addLog("Incoming connection request from $name.");

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
                _addLog("Declined request from $name.");
              },
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                respond(true);
                _addLog("Accepted request from $name.");
                if (mounted) setState(() {});
              },
              child: const Text('Accept'),
            ),
          ],
        ),
      );
    };
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SessionData().removeListener(_onSessionChanged);
    SessionData().onIncomingRequest = null;
    super.dispose();
  }

  void _addLog(String text) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    if (!mounted) return;
    setState(() {
      _log.insert(0, "[$time] $text");
      if (_log.length > 50) _log.removeLast();
    });
  }

  void _connectToPeer(PeerData peer) async {
    _addLog("Requesting connection to ${peer.name}...");
    try {
      final conn = await SessionData().connectToPeer(
        peer.deviceId,
        onMessage: (msg) {
          log("Message from ${peer.name}: $msg");
          _addLog("Received from ${peer.name}: $msg");
        },
        onError: (err) {
          log("TCP error ${peer.name}: $err");
          _addLog("Error with ${peer.name}: $err");
        },
        onDisconnected: () {
          log("Disconnected from ${peer.name}");
          _addLog("Disconnected from ${peer.name}");
          if (mounted) setState(() {});
        },
      );

      _addLog("${peer.name} accepted — connected (encrypted).");
      conn.send({'type': 'greeting', 'text': 'Hi from ${SessionData().userName}'});
      _addLog("Sent test greeting to ${peer.name}.");

      if (mounted) setState(() {});
    } catch (e) {
      log("Failed to connect to ${peer.name}: $e");
      _addLog("Request to ${peer.name} failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connect failed: $e")),
        );
      }
    }
  }

  void _sendTestMessage(PeerData peer) {
    final conn = SessionData().getTcpConnection(peer.deviceId);
    if (conn == null || !conn.isConnected) return;
    try {
      conn.send({'type': 'ping', 'text': 'ping from ${SessionData().userName}'});
      _addLog("Sent ping to ${peer.name}.");
    } catch (e) {
      _addLog("Failed to send ping to ${peer.name}: $e");
    }
  }

  void _disconnectFromPeer(PeerData peer) {
    SessionData().disconnectFromPeer(peer.deviceId);
    _addLog("Disconnected from ${peer.name}.");
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionData();
    final peers = session.allPeers;

    return Scaffold(
      appBar: AppBar(title: const Text('LocSand – Data')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Session', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('userId: ${session.userId ?? "-"}'),
            Text('userName: ${session.userName ?? "-"}'),
            const SizedBox(height: 16),
            const Text('Peers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Count: ${peers.length}'),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: peers.isEmpty
                  ? const Text('No peers in session yet.')
                  : ListView.builder(
                      itemCount: peers.length,
                      itemBuilder: (context, index) {
                        final p = peers[index];
                        final conn = session.getTcpConnection(p.deviceId);
                        final connected = conn != null && conn.isConnected;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(p.name),
                            subtitle: Text('${p.ip}:${p.port}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (connected)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(Icons.lock, size: 14, color: Colors.green),
                                  ),
                                Text(
                                  connected ? 'Connected' : 'Idle',
                                  style: TextStyle(fontSize: 10, color: connected ? Colors.green : Colors.grey),
                                ),
                                const SizedBox(width: 8),
                                if (connected)
                                  IconButton(
                                    icon: const Icon(Icons.send, size: 20),
                                    onPressed: () => _sendTestMessage(p),
                                    tooltip: 'Send test ping',
                                  ),
                                IconButton(
                                  icon: Icon(connected ? Icons.link_off : Icons.link),
                                  onPressed: () => connected ? _disconnectFromPeer(p) : _connectToPeer(p),
                                  tooltip: connected ? 'Disconnect' : 'Request connection',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            const Text('Activity Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                child: _log.isEmpty
                    ? const Text('Nothing yet.', style: TextStyle(color: Colors.white54, fontSize: 12))
                    : ListView.builder(
                        itemCount: _log.length,
                        itemBuilder: (context, index) => Text(
                          _log[index],
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}