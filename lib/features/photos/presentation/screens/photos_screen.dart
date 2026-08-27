import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/photo_cleanup_summary.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/photo_cleanup_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';

/// Photos tab: the Photo Cleanup dashboard.
///
/// One row per photo tool, each showing what it could recover, so the tab
/// answers "where is my storage going" before the user opens anything.
///
/// Every figure comes from the tool's own provider, so the number here is the
/// number the tool shows. This screen reports and routes only — it never
/// deletes, so the single Phase 12 delete path stays in the tools.
class PhotosScreen extends ConsumerWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PhotoCleanupSummary> cleanup = ref.watch(
      photoCleanupProvider,
    );

    return Scaffold(
      key: const Key('photos_screen'),
      appBar: AppBar(
        title: const Text('Photos'),
        actions: <Widget>[
          IconButton(
            key: const Key('photo_cleanup_rescan'),
            tooltip: 'Scan again',
            onPressed: () => refreshPhotoCleanup(ref),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            refreshPhotoCleanup(ref);
            await ref.read(photoCleanupProvider.future);
          },
          child: cleanup.when(
            loading: () => const FilesScanningView(),
            error: (Object error, StackTrace stackTrace) => FilesErrorView(
              error: error,
              onRetry: () => refreshPhotoCleanup(ref),
              onPermissions: () => context.push(AppRoutes.permissions),
            ),
            data: (PhotoCleanupSummary summary) =>
                _PhotoCleanupView(summary: summary),
          ),
        ),
      ),
    );
  }
}

class _PhotoCleanupView extends StatelessWidget {
  const _PhotoCleanupView({required this.summary});

  final PhotoCleanupSummary summary;

  /// Where each row leads.
  static String? _routeFor(PhotoCleanupTool tool) => switch (tool) {
    PhotoCleanupTool.duplicatePhotos => AppRoutes.photoDuplicates,
    PhotoCleanupTool.screenshots => AppRoutes.screenshotCleaner,
    PhotoCleanupTool.largePhotos => AppRoutes.largePhotos,
    PhotoCleanupTool.similarPhotos => AppRoutes.similarPhotos,
  };

  void _open(BuildContext context, PhotoCleanupTool tool) {
    final String? route = _routeFor(tool);
    if (route == null) {
      return;
    }
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final List<PhotoCleanupEntry> ranked = summary.rankedFindings;
    final PhotoCleanupEntry? biggest = ranked.isEmpty ? null : ranked.first;

    return ListView(
      key: const Key('photo_cleanup_dashboard'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        _CleanupCard(
          summary: summary,
          onOpen: (PhotoCleanupTool tool) => _open(context, tool),
        ),
        const SizedBox(height: 16),
        SizedBox(
          // The theme no longer stretches buttons, so ask for the full width
          // here. A finite constraint, unlike Size.fromHeight.
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('photo_review_button'),
            // Opens whichever tool holds the most space.
            onPressed: biggest == null
                ? null
                : () => _open(context, biggest.tool),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Review Photos'),
          ),
        ),
        if (summary.isEmpty) ...<Widget>[
          const SizedBox(height: 24),
          const _NothingToClean(),
        ],
      ],
    );
  }
}

/// The "Photo Cleanup" panel: one row per tool, label and size.
class _CleanupCard extends StatelessWidget {
  const _CleanupCard({required this.summary, required this.onOpen});

  final PhotoCleanupSummary summary;
  final ValueChanged<PhotoCleanupTool> onOpen;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('photo_cleanup_card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Photo Cleanup',
              key: const Key('photo_cleanup_heading'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              ByteFormatter.format(summary.totalBytes),
              key: const Key('photo_cleanup_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'across ${summary.totalPhotos} '
              '${summary.totalPhotos == 1 ? 'photo' : 'photos'}',
              key: const Key('photo_cleanup_total_photos'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            for (final PhotoCleanupEntry entry in summary.entries)
              _CleanupRow(entry: entry, onOpen: () => onOpen(entry.tool)),
            if (summary.hasOverlap) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Some photos appear in more than one tool and are counted '
                'once in the total.',
                key: const Key('photo_cleanup_overlap_note'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// One line: `Duplicate Photos      640 MB`.
///
/// Similar Photos shows `Analyze` in place of a size, because a figure it has
/// not measured would be a guess.
class _CleanupRow extends StatelessWidget {
  const _CleanupRow({required this.entry, required this.onOpen});

  final PhotoCleanupEntry entry;
  final VoidCallback onOpen;

  IconData get _icon => switch (entry.tool) {
    PhotoCleanupTool.duplicatePhotos => Icons.photo_library_rounded,
    PhotoCleanupTool.screenshots => Icons.screenshot_rounded,
    PhotoCleanupTool.largePhotos => Icons.photo_size_select_large_rounded,
    PhotoCleanupTool.similarPhotos => Icons.auto_awesome_motion_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool pending = !entry.hasFigure;
    final bool dim = pending || entry.isEmpty;

    final String trailing = pending
        ? 'Analyze'
        : entry.isEmpty
        ? 'None'
        // "up to", because which shot the user keeps changes the figure.
        : entry.isEstimate
        ? 'up to ${ByteFormatter.format(entry.bytes)}'
        : ByteFormatter.format(entry.bytes);

    return InkWell(
      key: Key('photo_tool_${entry.tool.name}'),
      // Always tappable: an empty tool still opens, and Similar Photos
      // explains itself rather than being an unexplained dead row.
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(
              _icon,
              size: 20,
              color: dim ? colors.onSurfaceVariant : colors.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    entry.tool.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: dim ? colors.onSurfaceVariant : colors.onSurface,
                    ),
                  ),
                  Text(
                    pending ? 'Coming next' : entry.tool.description,
                    key: Key('photo_tool_note_${entry.tool.name}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              trailing,
              key: Key('photo_tool_value_${entry.tool.name}'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: pending
                    ? colors.primary
                    : dim
                    ? colors.onSurfaceVariant
                    : colors.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingToClean extends StatelessWidget {
  const _NothingToClean();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      key: const Key('photo_cleanup_clean'),
      children: <Widget>[
        Icon(
          Icons.check_circle_outline_rounded,
          size: 52,
          color: colors.primary,
        ),
        const SizedBox(height: 14),
        Text(
          'Your photos look tidy',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'No duplicates, screenshots, or oversized images were found.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
