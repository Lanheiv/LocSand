import 'package:flutter/material.dart';

import 'package:locsand/src/core_protocols.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/view/chat_screen.dart';
import 'package:locsand/view/components/floating_app_bar.dart';
import 'package:locsand/view/components/incoming_file_dialog.dart';
import 'package:locsand/view/components/show_dialog.dart';
import 'package:locsand/view/pages/home_page.dart';
import 'package:locsand/view/pages/setting_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SessionData().onIncomingRequest = (deviceId, name, respond) {
      if (!mounted) return respond(false);
      showConnectionRequest(context, name: name, respond: respond);
    };
    SessionData().onIncomingSaveRequest = (deviceId, name, respond) {
      if (!mounted) return respond(false);
      showSaveRequest(context, name: name, respond: respond);
    };
    SessionData().onIncomingFileOffer = (transfer, respond) {
      if (!mounted) return respond(false);
      IncomingFileDialog.show(context, transfer: transfer, respond: respond);
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        SessionData().awayAll();
      case AppLifecycleState.resumed:
        SessionData().backAll();
        search?.refresh();
      default:
        break;
    }
  }

  Future<void> _openChat(PeerData peer) async {
    if (_connecting) return;
    final session = SessionData();

    if (!session.isConnected(peer.deviceId)) {
      setState(() => _connecting = true);
      try {
        await session.connectToPeer(peer.deviceId);
      } catch (e) {
        if (mounted) toast(context, 'Connect failed: ${errorText(e)}');
      }
      if (mounted) setState(() => _connecting = false);
      if (!session.isConnected(peer.deviceId) && !session.isPeerSaved(peer.deviceId)) {
        return;
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FloatingAppBar(
              title: 'Locsand',
              loading: _connecting,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_rounded),
                  tooltip: 'Settings',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingPage()),
                  ),
                ),
              ],
            ),
            Expanded(child: HomePage(onTapPeer: _openChat)),
          ],
        ),
      ),
    );
  }
}