import 'package:flutter/material.dart';

import 'package:locsand/src/data/chat_message.dart';
import 'package:locsand/src/data/file_transfer.dart';
import 'package:locsand/src/helpers/time_format.dart';
import 'package:locsand/view/components/message_bubble.dart';

class ChatEntry {
  final DateTime time;
  final bool fromMe;
  final ChatMessage? message;
  final FileTransfer? transfer;

  ChatEntry.message(ChatMessage m)
      : time = m.time,
        fromMe = m.fromMe,
        message = m,
        transfer = null;

  ChatEntry.file(FileTransfer t)
      : time = t.startedAt,
        fromMe = t.direction == FileTransferDirection.outgoing,
        message = null,
        transfer = t;

  String? get copyText => message?.text ?? transfer?.localPath;

  bool joins(ChatEntry other) =>
      fromMe == other.fromMe &&
      isSameDay(time, other.time) &&
      time.difference(other.time).inMinutes.abs() < 3;
}

class ChatTimeline extends StatelessWidget {
  const ChatTimeline({super.key, required this.entries, required this.onCopy});

  final List<ChatEntry> entries;
  final void Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const Center(child: Text('No messages yet.'));

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) => _item(entries.length - 1 - index),
    );
  }

  Widget _item(int i) {
    final e = entries[i];
    final prev = i > 0 ? entries[i - 1] : null;
    final next = i < entries.length - 1 ? entries[i + 1] : null;
    final newDay = prev == null || !isSameDay(prev.time, e.time);
    final copy = e.copyText;

    final bubble = Padding(
      padding: EdgeInsets.only(top: prev != null && e.joins(prev) ? 2 : 8),
      child: MessageBubble(
        fromMe: e.fromMe,
        tail: next == null || !e.joins(next),
        onLongPress: e.message != null || copy == null || copy.isEmpty
            ? null
            : () => onCopy(copy),
        child: e.message != null
            ? TextMessageContent(text: e.message!.text, time: e.time, fromMe: e.fromMe)
            : FileMessageContent(transfer: e.transfer!),
      ),
    );

    if (!newDay) return bubble;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [DateChip(label: dayLabel(e.time)), bubble],
    );
  }
}
