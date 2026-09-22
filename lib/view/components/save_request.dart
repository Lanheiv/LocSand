import 'package:flutter/material.dart';

class SaveRequestDialog extends StatelessWidget {
  final String name;
  final void Function(bool accepted) respond;

  const SaveRequestDialog({
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
      builder: (context) => SaveRequestDialog(name: name, respond: respond),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save connection'),
      content: Text(
        '$name wants to save this connection so you can both '
        'auto-reconnect later without rediscovering each other. Allow it?',
      ),
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
          child: const Text('Save'),
        ),
      ],
    );
  }
}