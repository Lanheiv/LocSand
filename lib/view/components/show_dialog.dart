import 'package:flutter/material.dart';
import 'package:locsand/src/data/file_transfer.dart';

class ConnectionRequestDialog extends StatelessWidget {
  final String name;
  final void Function(bool accepted) respond;

  const ConnectionRequestDialog({
    super.key,
    required this.name,
    required this.respond,
  });

  static Future<void> show(
    BuildContext context, {
    required String name,
    required void Function(bool accepted) respond,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConnectionRequestDialog(name: name, respond: respond),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connection request'),
      content: Text('$name wants to connect. Allow it?'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            respond(false);
          },
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            respond(true);
          },
          child: const Text('Accept'),
        ),
      ],
    );
  }
}

class IncomingFileDialog extends StatelessWidget {
  final FileTransfer transfer;
  final void Function(bool accepted) respond;

  const IncomingFileDialog({
    super.key,
    required this.transfer,
    required this.respond,
  });

  static Future<void> show(
    BuildContext context, {
    required FileTransfer transfer,
    required void Function(bool accepted) respond,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => IncomingFileDialog(transfer: transfer, respond: respond),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Incoming file'),
      content: Text('${transfer.name} (${_formatSize(transfer.size)})'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            respond(false);
          },
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            respond(true);
          },
          child: const Text('Accept'),
        ),
      ],
    );
  }
}