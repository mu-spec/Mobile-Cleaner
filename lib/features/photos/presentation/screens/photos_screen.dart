import 'package:flutter/material.dart';
import 'package:mobile_cleaner/shared/widgets/feature_placeholder.dart';

class PhotosScreen extends StatelessWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Photos',
      description: 'Review duplicate, similar, blurry, and large photos before removing any.',
      icon: Icons.photo_library_rounded,
    );
  }
}
