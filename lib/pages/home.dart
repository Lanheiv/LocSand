import 'package:flutter/material.dart';

import 'package:locsand/data/session_data.dart';
import 'package:locsand/data/peer_data.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Call this from anywhere (e.g., from UDP service) to refresh UI
  void refresh() {
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
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(p.name),
                            subtitle: Text('${p.ip}:${p.port}'),
                            trailing: Text(
                              p.deviceId,
                              style: const TextStyle(fontSize: 10),
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