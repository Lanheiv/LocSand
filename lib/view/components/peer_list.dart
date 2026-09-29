import 'package:flutter/material.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';

class PeerList extends StatelessWidget {
  final List<PeerData> peers;
  final SessionData session;
  final void Function(PeerData peer) onTapPeer;
  final Future<void> Function()? onRefresh;

  const PeerList({
    super.key,
    required this.peers,
    required this.session,
    required this.onTapPeer,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...peers]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final Widget list = sorted.isEmpty
        ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              Padding(
                padding: EdgeInsets.fromLTRB(24, 120, 24, 24),
                child: Text(
                  'No devices found yet.\n\n'
                  'Pull down to search again. Both devices need to be on the '
                  'same Wi-Fi network (guest networks often block discovery).',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          )
        : ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final p = sorted[index];
              final conn = session.getTcpConnection(p.deviceId);
              final connected = conn != null && conn.isConnected;
              final saved = session.isPeerSaved(p.deviceId);

              return ListTile(
                title: Text(p.name),
                subtitle: Text('${p.ip}:${p.port}'),
                leading: Icon(
                  connected ? Icons.link : Icons.link_off,
                  color: connected ? Colors.green : Colors.grey,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (saved)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.bookmark, size: 18, color: Colors.amber),
                      ),
                    const Icon(Icons.chat_bubble_outline),
                  ],
                ),
                onTap: () => onTapPeer(p),
              );
            },
          );

    final refresh = onRefresh;
    return refresh == null ? list : RefreshIndicator(onRefresh: refresh, child: list);
  }
}
