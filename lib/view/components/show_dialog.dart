import 'package:flutter/material.dart';

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String errorText(Object e) => e is StateError ? e.message : '$e';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String yes,
  String no = 'Cancel',
  bool danger = false,
  bool dismissible = true,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: dismissible,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(no),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showConnectionRequest(
  BuildContext context, {
  required String name,
  required void Function(bool accepted) respond,
}) async => respond(await _confirm(
      context,
      title: 'Connection request',
      body: '$name wants to connect. Allow it?',
      yes: 'Accept',
      no: 'Decline',
      dismissible: false,
    ));

Future<void> showSaveRequest(
  BuildContext context, {
  required String name,
  required void Function(bool accepted) respond,
}) async => respond(await _confirm(
      context,
      title: 'Save connection',
      body: '$name wants to save this connection so you can both '
          'auto-reconnect later without confirmation. Allow it?',
      yes: 'Save',
      no: 'Decline',
      dismissible: false,
    ));

Future<bool> confirmForget(BuildContext context, String name) => _confirm(
      context,
      title: 'Forget connection?',
      body: 'This removes $name from your saved connections. It will not '
          'auto-reconnect anymore unless you save it again.',
      yes: 'Forget',
    );

Future<bool> confirmDeleteHistory(BuildContext context) => _confirm(
      context,
      title: 'Delete & stop saving?',
      body: 'This deletes this conversation from this screen and from '
          'storage, and turns history saving off for this peer. This '
          'cannot be undone.',
      yes: 'Delete',
      danger: true,
    );
