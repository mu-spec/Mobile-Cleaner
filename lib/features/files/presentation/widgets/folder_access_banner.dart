import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/features/files/data/storage_access_repository.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/file_scan_provider.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Reference-style prompt for Android's optional folder access.
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
      // Documents is accepted as a starting point on Android 11+, unlike a
      // storage-volume root or the Download root itself.
      await ref
          .read(storageAccessRepositoryProvider)
          .requestFolderAccess(initialDir: 'Documents');
      if (!mounted) {
        return;
      }
      ref.invalidate(fileScanProvider);
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color orange = isDark
        ? AppColors.darkOrange
        : AppColors.cleanupOrange;

    return Container(
      key: const Key('folder_access_banner'),
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF281A0E) : const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: orange.withValues(alpha: isDark ? 0.30 : 0.16),
        ),
        boxShadow: <BoxShadow>[
          if (!isDark)
            BoxShadow(
              color: orange.withValues(alpha: 0.11),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                key: const Key('folder_access_icon'),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: orange.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: PhosphorIcon(
                    PhosphorIconsDuotone.folderOpen,
                    size: 27,
                    color: orange,
                    duotoneSecondaryColor: const Color(0xFFFFBF66),
                    duotoneSecondaryOpacity: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Show more documents\nand downloads',
                      key: const Key('folder_access_title'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.22,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Android hides files other apps saved. Grant access to '
                      'a folder and Mobile Cleaner can include its documents, '
                      'archives, and installers.',
                      key: const Key('folder_access_description'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('folder_access_grant'),
              onPressed: _requesting ? null : _grant,
              style: FilledButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: orange.withValues(alpha: 0.45),
                minimumSize: const Size(146, 43),
                padding: const EdgeInsets.symmetric(horizontal: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              icon: _requesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_rounded, size: 18),
              label: const Text('Choose Folder'),
            ),
          ),
        ],
      ),
    );
  }
}
