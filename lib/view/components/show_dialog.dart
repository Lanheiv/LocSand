import 'package:flutter/material.dart';

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