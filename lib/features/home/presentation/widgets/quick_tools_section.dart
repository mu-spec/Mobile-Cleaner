import 'package:flutter/material.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/smart_scan_cta.dart';

/// Secondary cleaner tools, grouped into one card.
///
/// Previously four large grid cards, which gave every secondary tool the same
/// visual weight as the primary Scan action and pushed the recommendations
/// below the fold. One card of compact rows keeps the hierarchy clear and
/// takes roughly half the height.
///
/// Destinations are unchanged — the same four callbacks, wired to the same
/// screens.
class QuickToolsSection extends StatelessWidget {
  const QuickToolsSection({
    required this.onPhotos,
    required this.onFiles,
    required this.onApps,
    required this.onPermissions,
    super.key,
  });

  final VoidCallback onPhotos;
  final VoidCallback onFiles;
  final VoidCallback onApps;
  final VoidCallback onPermissions;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('quick_tools_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const HomeSectionHeader(
          title: 'Quick tools',
          caption: 'Review before removing anything.',
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              HomeToolRow(
                rowKey: const Key('quick_photos'),
                icon: Icons.photo_library_rounded,
                title: 'Photos',
                subtitle: 'Duplicates, screenshots, large images',
                onTap: onPhotos,
              ),
              HomeToolRow(
                rowKey: const Key('quick_files'),
                icon: Icons.folder_rounded,
                title: 'Large files',
                subtitle: 'Find your biggest space users',
                onTap: onFiles,
              ),
              HomeToolRow(
                rowKey: const Key('quick_apps'),
                icon: Icons.apps_rounded,
                title: 'Apps',
                subtitle: 'Check installed app sizes',
                onTap: onApps,
              ),
              HomeToolRow(
                rowKey: const Key('quick_permissions'),
                icon: Icons.folder_shared_rounded,
                title: 'Storage access',
                subtitle: 'Review or update permissions',
                onTap: onPermissions,
                showDivider: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
