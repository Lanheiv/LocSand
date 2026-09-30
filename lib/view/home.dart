import 'package:flutter/material.dart';

import 'package:locsand/src/core_protocols.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';

import 'package:locsand/view/chat_screen.dart';

import 'package:locsand/view/pages/home_page.dart';
import 'package:locsand/view/pages/setting_page.dart';

import 'package:locsand/view/components/show_dialog.dart';
import 'package:locsand/view/components/app_bar.dart';

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
      if (!mounted) {
        respond(false);
        return;
      }
      ConnectionRequestDialog.show(context, name: name, respond: respond);
    };
    SessionData().onIncomingFileOffer = (transfer, respond) {
      if (!mounted) {
        respond(false);
        return;
      }
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
    if (state == AppLifecycleState.resumed) {
      search?.refresh();
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingPage()),
    );
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

    final nowConnected =
        SessionData().getTcpConnection(peer.deviceId)?.isConnected ?? false;
    if (!nowConnected && !SessionData().isPeerSaved(peer.deviceId)) return;

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
      );
    }
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
              onSettings: _openSettings,
              onUser: () {
                // open user/profile
              },
            ),
            Expanded(child: HomePage(onTapPeer: _openChat)),
          ],
        ),
      ),
    );
  }
}