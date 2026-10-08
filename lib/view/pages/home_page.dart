import 'package:flutter/material.dart';

import 'package:locsand/src/core_protocols.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/view/components/card_style.dart';
import 'package:locsand/view/components/floating_app_bar.dart';
import 'package:locsand/view/components/horizontal_scroller.dart';
import 'package:locsand/view/components/nearby_peer_card.dart';
import 'package:locsand/view/components/saved_peer_card.dart';
import 'package:locsand/view/components/section_header.dart';
import 'package:locsand/view/components/show_dialog.dart';

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

  Future<void> _refresh() async {
    await search?.refresh();
    await Future.delayed(const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionData();

    final saved = session.allSavedPeers
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    final nearby = session.allPeers
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return RefreshIndicator(
      onRefresh: _refresh,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: FloatingAppBar.sidePadding(context)),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: FloatingAppBar.maxWidth),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (session.startupError != null)
                  SliverToBoxAdapter(
                    child: Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          session.startupError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SectionHeader(title: 'Saved', count: saved.length),
                ),
                SliverToBoxAdapter(
                  child: saved.isEmpty
                      ? const _EmptyNote('No saved connections yet.')
                      : HorizontalScroller(
                          height: SavedPeerCard.height,
                          itemCount: saved.length,
                          itemBuilder: (context, index) {
                            final s = saved[index];
                            final messages = session.getChatMessages(s.deviceId);
                            final connected = session.isConnected(s.deviceId);
                            return SavedPeerCard(
                              name: s.name,
                              subtitle: messages.isNotEmpty
                                  ? messages.last.text
                                  : (connected ? 'Connected' : s.lastKnownIp),
                              connected: connected,
                              online: session.isPeerOnline(s.deviceId),
                              onTap: () => widget.onTapPeer(session.resolvePeer(s)),
                              onForget: () async {
                                if (await confirmForget(context, s.name)) {
                                  await session.forgetSavedPeer(s.deviceId);
                                }
                              },
                            );
                          },
                        ),
                ),
                SliverToBoxAdapter(
                  child: SectionHeader(title: 'Nearby', count: nearby.length),
                ),
                SliverToBoxAdapter(
                  child: nearby.isEmpty
                      ? const _EmptyNote(
                          'No devices found. Both devices need to be on the '
                          'same Wi-Fi network (guest networks often block '
                          'discovery). Pull down to search again.',
                        )
                      : HorizontalScroller(
                          height: NearbyPeerCard.height,
                          itemCount: nearby.length,
                          itemBuilder: (context, index) {
                            final p = nearby[index];
                            return NearbyPeerCard(
                              name: p.name,
                              address: '${p.ip}:${p.port}',
                              connected: session.isConnected(p.deviceId),
                              saved: session.isPeerSaved(p.deviceId),
                              onTap: () => widget.onTapPeer(p),
                            );
                          },
                        ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
