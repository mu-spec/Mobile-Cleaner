import 'package:flutter/material.dart';
import 'package:mobile_cleaner/shared/widgets/feature_placeholder.dart';

class CleanScreen extends StatelessWidget {
  const CleanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Clean',
      description:
          'Scan safely for cache, temporary files, and other removable items.',
      icon: Icons.auto_fix_high_rounded,
    );
  }
}
