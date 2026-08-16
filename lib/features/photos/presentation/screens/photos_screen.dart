import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';

/// Photos tab.
///
/// Screenshots are the first photo tool. Duplicate, similar, and blurry photo
/// detection are still to come, so they are listed as upcoming rather than
/// hidden, which keeps the tab honest about what it can do today.
class PhotosScreen extends StatelessWidget {
  const PhotosScreen({super.key});

  /// Photo tools planned for later phases.
  static const Map<String, String> _upcomingTools = <String, String>{
    'Similar photos': 'Near-identical shots',
    'Blurry photos': 'Out-of-focus pictures',
  };

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Photos')),
      body: SafeArea(
        child: ListView(
          key: const Key('photos_tools'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: <Widget>[
            Text(
              'Photo tools',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Review before removing anything.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: const Key('open_screenshot_cleaner'),
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: Icon(
                    Icons.screenshot_rounded,
                    color: colors.primary,
                  ),
                ),
                title: const Text('Screenshots'),
                subtitle: const Text('Find and clear old screenshots'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.screenshotCleaner),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: const Key('open_large_photos'),
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: Icon(Icons.photo_size_select_large_rounded,
                      color: colors.primary),
                ),
                title: const Text('Large photos'),
                subtitle: const Text('Find your biggest images'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.largePhotos),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: const Key('open_duplicates_from_photos'),
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: Icon(Icons.copy_all_rounded, color: colors.primary),
                ),
                title: const Text('Duplicates'),
                subtitle: const Text('Byte-identical copies'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.duplicates),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Coming soon',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final MapEntry<String, String> tool
                in _upcomingTools.entries)
              Opacity(
                opacity: 0.55,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.surfaceContainerHighest,
                    child: Icon(
                      Icons.hourglass_empty_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  title: Text(tool.key),
                  subtitle: Text(tool.value),
                  enabled: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
