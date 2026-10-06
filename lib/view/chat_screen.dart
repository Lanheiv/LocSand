import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/view/components/chat_menu.dart';
import 'package:locsand/view/components/chat_timeline.dart';
import 'package:locsand/view/components/floating_app_bar.dart';
import 'package:locsand/view/components/show_dialog.dart';

class ChatScreen extends StatefulWidget {
  final PeerData peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _session = SessionData();
  final _controller = TextEditingController();
  bool _historyEnabled = false;
  bool _hasText = false;
  bool _connecting = false;
  bool _picking = false;

  String get _id => widget.peer.deviceId;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onChanged);
    _session.ensureChatHistoryLoaded(_id);
    _session.isChatHistorySavingEnabled(_id).then((enabled) {
      if (mounted) setState(() => _historyEnabled = enabled);
    });
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    try {
      _session.sendChatMessage(_id, text);
      _controller.clear();
    } catch (e) {
      toast(context, 'Send failed: ${errorText(e)}');
    }
  }

  Future<void> _reconnect() async {
    setState(() => _connecting = true);
    try {
      await _session.connectToPeer(_id);
    } catch (e) {
      if (mounted) toast(context, 'Connect failed: ${errorText(e)}');
    }
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _toggleHistory() async {
    final enabled = !_historyEnabled;
    await _session.setChatHistorySaving(_id, enabled);
    if (!mounted) return;
    setState(() => _historyEnabled = enabled);
    toast(context, enabled ? 'Saving chat history' : 'Stopped saving new messages');
  }

  Future<void> _delete() async {
    if (!await confirmDeleteHistory(context)) return;
    await _session.deleteChatHistory(_id);
    if (mounted) setState(() => _historyEnabled = false);
  }

  Future<void> _attachFile() async {
    if (_picking) return;
    _picking = true;
    String? path;
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: false,
        withReadStream: false,
      );
      path = result?.files.firstOrNull?.path;
    } catch (e) {
      if (mounted) toast(context, 'Could not open file picker: ${errorText(e)}');
    } finally {
      _picking = false;
    }
    if (path == null) return;
    try {
      // The connection may have dropped while the picker was open.
      if (!_session.isConnected(_id)) {
        if (mounted) setState(() => _connecting = true);
        try {
          await _session.connectToPeer(_id);
        } finally {
          if (mounted) setState(() => _connecting = false);
        }
      }
      await _session.sendFile(_id, File(path));
    } catch (e) {
      if (mounted) toast(context, 'File send failed: ${errorText(e)}');
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    toast(context, 'Copied');
  }

  void _onMenu(ChatAction action) {
    switch (action) {
      case ChatAction.reconnect:
        _reconnect();
      case ChatAction.save:
        _session.isPeerSaved(_id)
            ? _session.forgetSavedPeer(_id)
            : _session.savePeer(_id);
      case ChatAction.history:
        _toggleHistory();
      case ChatAction.delete:
        _delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _session.getChatMessages(_id);
    final connected = _session.isConnected(_id);

    final entries = <ChatEntry>[
      ...messages.map(ChatEntry.message),
      ..._session.fileTransfersFor(_id).map(ChatEntry.file),
    ]..sort((a, b) => a.time.compareTo(b.time));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FloatingAppBar(
              title: widget.peer.name,
              loading: _connecting,
              showBack: true,
              actions: [
                ChatMenu(
                  connected: connected,
                  connecting: _connecting,
                  saved: _session.isPeerSaved(_id),
                  historyEnabled: _historyEnabled,
                  canDelete: _historyEnabled || messages.isNotEmpty,
                  onSelected: _onMenu,
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: FloatingAppBar.sidePadding(context),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: FloatingAppBar.maxWidth),
                    child: Column(
                      children: [
                        Expanded(child: ChatTimeline(entries: entries, onCopy: _copy)),
                        _composer(connected),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(bool connected) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file),
              tooltip: 'Send file',
              onPressed: connected ? _attachFile : null,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: connected,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: connected ? 'Type a message' : 'Not connected',
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              color: Theme.of(context).colorScheme.primary,
              onPressed: connected && _hasText ? _send : null,
            ),
          ],
        ),
      ),
    );
  }
}