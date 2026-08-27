import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showExitConfirmation(BuildContext context) async {
  final bool? shouldExit = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        key: const Key('exit_confirmation_dialog'),
        title: const Text('Exit'),
        content: const Text('Are you sure you want to exit?'),
        actions: <Widget>[
          TextButton(
            key: const Key('exit_no_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            key: const Key('exit_yes_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes'),
          ),
        ],
      );
    },
  );

  if (shouldExit == true) {
    await SystemNavigator.pop();
  }
}
