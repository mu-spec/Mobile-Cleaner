import 'package:flutter/material.dart';
import 'package:mobile_cleaner/shared/widgets/feature_placeholder.dart';

class AppsScreen extends StatelessWidget {
  const AppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Apps',
      description: 'Understand which installed apps use the most storage on your device.',
      icon: Icons.apps_rounded,
    );
  }
}
