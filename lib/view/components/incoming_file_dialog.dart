import 'package:flutter/material.dart';

import 'package:locsand/src/data/file_transfer.dart';
import 'package:locsand/src/helpers/receive_folder.dart';
import 'package:locsand/src/helpers/time_format.dart';

class IncomingFileDialog extends StatefulWidget {
  const IncomingFileDialog({super.key, required this.transfer});

  final FileTransfer transfer;

  static Future<void> show(
    BuildContext context, {
    required FileTransfer transfer,
    required void Function(bool accepted) respond,
  }) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingFileDialog(transfer: transfer),
    );
    respond(accepted ?? false);
  }

  @override
  State<IncomingFileDialog> createState() => _IncomingFileDialogState();
}

class _IncomingFileDialogState extends State<IncomingFileDialog> {
  String? _folder;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await receiveDirectory();
    if (mounted) setState(() => _folder = dir.path);
  }

  Future<void> _change() async {
    if (await pickReceiveFolder() != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.transfer;

    return AlertDialog(
      title: const Text('Incoming file'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${t.name} (${formatSize(t.size)})'),
          const SizedBox(height: 16),
          Text(
            'Save to',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(_folder ?? '…', maxLines: 3, overflow: TextOverflow.ellipsis),
          TextButton.icon(
            onPressed: _change,
            icon: const Icon(Icons.folder_open),
            label: const Text('Change folder'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: _folder == null ? null : () => Navigator.pop(context, true),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}
