import 'package:flutter/material.dart';

import 'package:locsand/src/data/file_transfer.dart';
import 'package:locsand/src/helpers/time_format.dart';
import 'package:locsand/view/components/card_style.dart';

class BubbleColors {
  final Color background;
  final Color text;
  final Color meta;

  const BubbleColors._(this.background, this.text, this.meta);

  factory BubbleColors.of(BuildContext context, bool fromMe) {
    final scheme = Theme.of(context).colorScheme;
    final text = fromMe ? scheme.onPrimaryContainer : scheme.onSurface;
    return BubbleColors._(
      fromMe ? scheme.primaryContainer : cardColor(context),
      text,
      text.withValues(alpha: 0.6),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final bool fromMe;
  final bool tail;
  final Widget child;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.fromMe,
    required this.tail,
    required this.child,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    const big = Radius.circular(18);
    const small = Radius.circular(4);
    final maxWidth = (MediaQuery.sizeOf(context).width * 0.78).clamp(0.0, 480.0);

    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.fromLTRB(12, 7, 10, 6),
          decoration: BoxDecoration(
            color: BubbleColors.of(context, fromMe).background,
            borderRadius: BorderRadius.only(
              topLeft: big,
              topRight: big,
              bottomLeft: (!fromMe && tail) ? small : big,
              bottomRight: (fromMe && tail) ? small : big,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class TextMessageContent extends StatelessWidget {
  final String text;
  final DateTime time;
  final bool fromMe;

  const TextMessageContent({
    super.key,
    required this.text,
    required this.time,
    required this.fromMe,
  });
  @override
  Widget build(BuildContext context) {
    final colors = BubbleColors.of(context, fromMe);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectionArea(
          child: Text(
            text,
            textWidthBasis: TextWidthBasis.longestLine,
            style: TextStyle(color: colors.text, fontSize: 15.5, height: 1.25),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatClock(time),
          style: TextStyle(color: colors.meta, fontSize: 11),
        ),
      ],
    );
  }
}

class FileMessageContent extends StatelessWidget {
  final FileTransfer transfer;

  const FileMessageContent({super.key, required this.transfer});

  bool get _fromMe => transfer.direction == FileTransferDirection.outgoing;

  bool get _active => transfer.status == FileTransferStatus.inProgress;

  bool get _failed =>
      transfer.status == FileTransferStatus.declined ||
      transfer.status == FileTransferStatus.failed;

  IconData get _icon {
    if (transfer.status == FileTransferStatus.completed) return Icons.check_rounded;
    if (_failed) return Icons.error_outline_rounded;
    return _fromMe ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
  }

  String get _status {
    final size = formatSize(transfer.size);
    switch (transfer.status) {
      case FileTransferStatus.offered:
        return _fromMe ? 'Waiting for them to accept…' : 'Waiting for your answer';
      case FileTransferStatus.inProgress:
        return '${formatSize(transfer.bytesTransferred)} of $size';
      case FileTransferStatus.completed:
        return _fromMe ? 'Sent · $size' : 'Received · $size';
      case FileTransferStatus.declined:
        return 'Declined';
      case FileTransferStatus.failed:
        return 'Transfer failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BubbleColors.of(context, _fromMe);
    final scheme = Theme.of(context).colorScheme;
    final iconColor = _failed
        ? scheme.error
        : (transfer.status == FileTransferStatus.completed ? Colors.green : scheme.primary);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 230),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_status, style: TextStyle(color: colors.meta, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (_active)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: transfer.size > 0 ? transfer.progress : null,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              formatClock(transfer.startedAt),
              style: TextStyle(color: colors.meta, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class DateChip extends StatelessWidget {
  final String label;

  const DateChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: cardColor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}