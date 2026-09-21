import 'package:flutter/material.dart';

import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';

import 'package:locsand/view/components/peer_list.dart';

class HomePage extends StatefulWidget {
  final void Function(PeerData peer) onTapPeer;

  const HomePage({super.key, required this.onTapPeer});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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

  @override
  Widget build(BuildContext context) {
    final session = SessionData();

    return PeerList(
      peers: session.allPeers,
      session: session,
      onTapPeer: widget.onTapPeer,
    );
  }
}