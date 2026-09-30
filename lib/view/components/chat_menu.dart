import 'package:flutter/material.dart';

enum ChatAction { reconnect, save, history, delete }

class ChatMenu extends StatelessWidget {
  const ChatMenu({
    super.key,
    required this.connected,
    required this.connecting,
    required this.saved,
    required this.historyEnabled,
    required this.canDelete,
    required this.onSelected,
  });

  final bool connected;
  final bool connecting;
  final bool saved;
  final bool historyEnabled;
  final bool canDelete;
  final void Function(ChatAction action) onSelected;

  Widget _item(IconData icon, String label, {Color? color}) => Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Text(label),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ChatAction>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: ChatAction.reconnect,
          enabled: !connected && !connecting,
          child: _item(
            connected ? Icons.link : Icons.link_off,
            connected ? 'Connected' : (connecting ? 'Connecting…' : 'Reconnect'),
            color: connected ? Colors.green : Colors.grey,
          ),
        ),
        PopupMenuItem(
          value: ChatAction.save,
          child: _item(
            saved ? Icons.bookmark : Icons.bookmark_border,
            saved ? 'Remove from saved' : 'Save',
          ),
        ),
        PopupMenuItem(
          value: ChatAction.history,
          child: _item(
            historyEnabled ? Icons.history : Icons.history_toggle_off,
            historyEnabled ? 'Stop saving history' : 'Save history',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: ChatAction.delete,
          enabled: canDelete,
          child: _item(Icons.delete_outline, 'Delete & stop saving'),
        ),
      ],
    );
  }
}
