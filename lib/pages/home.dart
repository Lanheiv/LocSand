// pages/home.dart
import 'package:flutter/material.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';
import 'dart:developer';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void refresh() {
    if (mounted) setState(() {});
  }

  void _connectToPeer(PeerData peer) async {
    try {
      final conn = await SessionData().connectToPeer(
        peer.deviceId,
        onMessage: (msg) {
          log("Message from ${peer.name}: $msg");
          // Here you can update some state / show snackbar / etc.
          if (mounted) setState(() {});
        },
        onError: (err) {
          log("TCP error ${peer.name}: $err");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Connection error: $err")),
            );
          }
        },
        onDisconnected: () {
          log("Disconnected from ${peer.name}");
          if (mounted) setState(() {});
        },
      );

      // Optional: send a hello message after connect
      conn.send({
        'type': 'hello',
        'text': 'Hi from ${peer.name}',
      });

      if (mounted) setState(() {});
    } catch (e) {
      log("Failed to connect to ${peer.name}: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connect failed: $e")),
        );
      }
    }
  }

  void _disconnectFromPeer(PeerData peer) {
    SessionData().disconnectFromPeer(peer.deviceId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionData();
    final peers = session.allPeers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LocSand – Data'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Session',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('userId: ${session.userId ?? "-"}'),
            Text('userName: ${session.userName ?? "-"}'),
            Text('userIp: ${session.userIp ?? "-"}'),
            Text('userOnlineTime: ${session.userOnlineTime ?? "-"}'),
            const SizedBox(height: 16),
            const Text(
              'Peers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Count: ${peers.length}'),
            const SizedBox(height: 8),
            Expanded(
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
                                Text(
                                  connected ? 'Connected' : 'Idle',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: connected
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(
                                    connected
                                        ? Icons.link_off
                                        : Icons.link,
                                  ),
                                  onPressed: () {
                                    if (connected) {
                                      _disconnectFromPeer(p);
                                    } else {
                                      _connectToPeer(p);
                                    }
                                  },
                                  tooltip: connected
                                      ? 'Disconnect'
                                      : 'Connect',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}