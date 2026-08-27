import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';

class RootBackButton extends StatelessWidget {
  const RootBackButton({required this.buttonKey, super.key});

  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    return BackButton(
      key: buttonKey,
      onPressed: () => context.go(AppRoutes.home),
    );
  }
}
