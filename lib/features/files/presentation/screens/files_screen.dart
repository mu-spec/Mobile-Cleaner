import 'package:flutter/material.dart';
import 'package:mobile_cleaner/shared/widgets/feature_placeholder.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Files',
      description: 'Find large downloads, old documents, archives, and other storage-heavy files.',
      icon: Icons.folder_rounded,
    );
  }
}
