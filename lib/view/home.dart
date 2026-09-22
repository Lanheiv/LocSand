import 'dart:io';

import 'package:flutter/material.dart';

import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/data/peer_data.dart';

import 'package:locsand/view/chat_screen.dart';

import 'package:locsand/view/pages/chat_page.dart';
import 'package:locsand/view/pages/setting_page.dart';
import 'package:locsand/view/pages/home_page.dart';

import 'package:locsand/view/components/show_dialog.dart';
import 'package:locsand/view/components/save_request.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _connecting = false;

  int currentPage = 0;

  List<Widget> get pages => [
        HomePage(onTapPeer: _openChat),
        ChatPage(onTapPeer: _openChat),
        const SettingPage(),
      ];

  final List<String> pageTitles = const [
    'Home',
    'Chats',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    SessionData().addListener(_onChanged);
    SessionData().onIncomingRequest = (deviceId, name, respond) {
      // Already a saved/trusted peer — no need to ask again every time
      // they reconnect. The TLS certificate pinning in PeerTrustStore
      // still protects against someone else answering on that deviceId.
      if (SessionData().isPeerSaved(deviceId)) {
        respond(true);
        return;
      }
      if (!mounted) {
        respond(false);
        return;
      }
      ConnectionRequestDialog.show(context, name: name, respond: respond);
    };
    SessionData().onSaveRequest = (deviceId, name, respond) {
      if (!mounted) {
        respond(false);
        return;
      }
      SaveRequestDialog.show(context, name: name, respond: respond);
    };
  }

  @override
  void dispose() {
    SessionData().removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openChat(PeerData peer) async {
    final conn = SessionData().getTcpConnection(peer.deviceId);

    if (conn == null || !conn.isConnected) {
      setState(() => _connecting = true);
      try {
        await SessionData().connectToPeer(peer.deviceId);
      } catch (e) {
        if (mounted) {
          final message = e is SocketException
              ? "Couldn't reach ${peer.name} — they may be offline or just starting up. Try again in a moment."
              : "Connect failed: $e";
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      } finally {
        if (mounted) setState(() => _connecting = false);
      }
    }

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
      appBar: AppBar(
        title: Text(pageTitles[currentPage]),
        actions: [
          if (_connecting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
      body: pages[currentPage],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentPage,
        onTap: (index) {
          setState(() => currentPage = index);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: "Chats"),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: "More"),
        ],
      ),
    );
  }
}