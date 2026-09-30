import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'package:locsand/src/core_protocols.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/saved_peer.dart';

import 'package:locsand/view/components/card_style.dart';
import 'package:locsand/view/components/section_header.dart';
import 'package:locsand/view/components/saved_peer_card.dart';
import 'package:locsand/view/components/nearby_peer_card.dart';
import 'package:locsand/view/components/horizontal_scroller.dart';

class HomePage extends StatefulWidget {
  final void Function(PeerData peer) onTapPeer;

  const HomePage({super.key, required this.onTapPeer});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _maxWidth = 800;

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

  Future<void> _refresh() async {
    await search?.refresh();
    await Future.delayed(const Duration(seconds: 2));
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

    final saved = [...session.allSavedPeers]
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    final savedIds = saved.map((s) => s.deviceId).toSet();

    // Nearby now includes saved devices too (they are marked in the card).
    final nearby = [...session.allPeers]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    bool isConnected(String id) =>
        session.getTcpConnection(id)?.isConnected ?? false;

    // Count each device once, even if it is both saved and nearby.
    final allIds = {...savedIds, ...nearby.map((p) => p.deviceId)};
    final connectedCount = allIds.where(isConnected).length;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SectionHeader(title: 'Saved', count: saved.length),
              ),
              SliverToBoxAdapter(
                child: saved.isEmpty
                    ? const _EmptyNote(
                        text: 'No saved connections yet.'
                      )
                    : SizedBox(
                        height: SavedPeerCard.height,
                        child: ScrollConfiguration(
                          // lets you drag the row with a mouse on desktop
                          behavior: ScrollConfiguration.of(context).copyWith(
                            dragDevices: {
                              PointerDeviceKind.touch,
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.trackpad,
                            },
                          ),
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: saved.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final s = saved[index];
                              final peer = session.getPeer(s.deviceId) ??
                                  PeerData(
                                    deviceId: s.deviceId,
                                    name: s.name,
                                    ip: s.lastKnownIp,
                                    port: s.lastKnownPort,
                                    lastSeen: s.savedAt,
                                  );
                              final connected = isConnected(s.deviceId);
                              final messages =
                                  session.getChatMessages(s.deviceId);

                              return SavedPeerCard(
                                name: s.name,
                                subtitle: messages.isNotEmpty
                                    ? messages.last.text
                                    : (connected ? 'Connected' : s.lastKnownIp),
                                connected: connected,
                                onTap: () => widget.onTapPeer(peer),
                                onForget: () => _confirmForget(s),
                              );
                            },
                          ),
                        ),
                      ),
              ),

              // ---- Nearby ----
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Nearby',
                  count: nearby.length,
                ),
              ),
            if (nearby.isEmpty)
              const SliverToBoxAdapter(
                child: _EmptyNote(
                  text: 'No new devices found. Both devices need to be on '
                      'the same Wi-Fi network (guest networks often block '
                      'discovery). Pull down or tap Refresh to search again.',
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: HorizontalScroller(
                    height: 136,
                    itemCount: nearby.length,
                    itemBuilder: (context, index) {
                      final p = nearby[index];
                      return SizedBox(
                        width: 180,
                        child: NearbyPeerCard(
                          name: p.name,
                          address: '${p.ip}:${p.port}',
                          connected: isConnected(p.deviceId),
                          saved: savedIds.contains(p.deviceId),
                          onTap: () => widget.onTapPeer(p),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}