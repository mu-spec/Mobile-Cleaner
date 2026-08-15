import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/storage_access_repository.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/file_scan_provider.dart';

/// Prompts for folder access when scoped storage is hiding non-media files.
///
/// Android only shows this when a grant would actually reveal more: the
/// scanner reports `needsFolderAccess` after checking the platform version and
/// existing grants.
class FolderAccessBanner extends ConsumerStatefulWidget {
  const FolderAccessBanner({super.key});

  @override
  ConsumerState<FolderAccessBanner> createState() => _FolderAccessBannerState();
}

class _FolderAccessBannerState extends ConsumerState<FolderAccessBanner> {
  bool _requesting = false;

  Future<void> _grant() async {
    setState(() => _requesting = true);
    try {
      // Documents is a safe starting point. Android 11+ refuses grants on the
      // Download folder and on volume roots, so it must not start there.
      await ref
          .read(storageAccessRepositoryProvider)
          .requestFolderAccess(initialDir: 'Documents');
      if (!mounted) {
        return;
      }
      // Re-run every scan so newly visible files appear.
      ref.invalidate(fileScanProvider);
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('folder_access_banner'),
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.folder_open_rounded, color: colors.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Show more documents and downloads',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Android hides files other apps saved. Grant access to a folder '
              'and Mobile Cleaner can include its documents, archives, and '
              'installers.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('folder_access_grant'),
                onPressed: _requesting ? null : _grant,
                icon: _requesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded, size: 18),
                label: const Text('Choose folder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
