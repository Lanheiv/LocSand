import 'package:flutter/material.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';

class PeerList extends StatelessWidget {
  final List<PeerData> peers;
  final SessionData session;
  final void Function(PeerData peer) onTapPeer;

  const PeerList({
    super.key,
    required this.peers,
    required this.session,
    required this.onTapPeer,
  });

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) {
      return const Center(child: Text('No peers found yet.'));
    }

    return ListView.builder(
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
          onTap: () => onTapPeer(p),
        );
      },
    );
  }
}