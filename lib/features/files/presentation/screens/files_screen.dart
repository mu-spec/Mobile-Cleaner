import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/file_scan_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/category_files_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_category_card.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/folder_access_banner.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';

/// Files tab: a category grid over the Phase 6 scanner.
class FilesScreen extends ConsumerWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FileScanResult> scan = ref.watch(fileScanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: <Widget>[
          IconButton(
            key: const Key('files_rescan_button'),
            tooltip: 'Rescan',
            onPressed: () => ref.invalidate(fileScanProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(fileScanProvider);
            await ref.read(fileScanProvider.future);
          },
          child: scan.when(
            loading: () => const FilesScanningView(),
            error: (Object error, StackTrace stackTrace) => FilesErrorView(
              error: error,
              onRetry: () => ref.invalidate(fileScanProvider),
              onPermissions: () => context.push(AppRoutes.permissions),
            ),
            data: (FileScanResult result) => _CategoryGrid(result: result),
          ),
        ),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.result});

  final FileScanResult result;

  void _openCategory(BuildContext context, FileCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryFilesScreen(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool nothingFound = result.isEmpty;

    return ListView(
      key: const Key('files_overview'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        if (result.needsFolderAccess) ...<Widget>[
          const FolderAccessBanner(),
          const SizedBox(height: 12),
        ],
        Card(
          key: const Key('files_summary_card'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        nothingFound ? 'No files found' : 'Files on this phone',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        nothingFound
                            ? 'Grant media and storage access, then pull down '
                                  'to scan again.'
                            : '${result.totalFiles} files · '
                                  '${ByteFormatter.format(result.totalBytes)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  nothingFound
                      ? Icons.folder_off_rounded
                      : Icons.travel_explore_rounded,
                  color: nothingFound ? colors.onSurfaceVariant : colors.primary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: const Key('open_large_files'),
            leading: CircleAvatar(
              backgroundColor: colors.primaryContainer,
              child: Icon(Icons.data_usage_rounded, color: colors.primary),
            ),
            title: const Text('Large Files'),
            subtitle: const Text('Find your biggest space users'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(AppRoutes.largeFiles),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            key: const Key('open_downloads_cleaner'),
            leading: CircleAvatar(
              backgroundColor: colors.primaryContainer,
              child: Icon(Icons.cleaning_services_rounded, color: colors.primary),
            ),
            title: const Text('Downloads Cleaner'),
            subtitle: const Text('Clear out old downloads'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(AppRoutes.downloadsCleaner),
          ),
        ),
        const SizedBox(height: 18),
        Text('Categories', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Tap a category to review its files.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        GridView.count(
          key: const Key('files_category_grid'),
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.12,
          children: <Widget>[
            for (final FileCategory category in FileCategory.scannable)
              FileCategoryCard(
                summary: result.summaryFor(category),
                onTap: () => _openCategory(context, category),
              ),
          ],
        ),
        if (!nothingFound) ...<Widget>[
          const SizedBox(height: 24),
          Text(
            'Largest files',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          for (final ScannedFile file in result.largestFiles(limit: 10))
            ScannedFileTile(file: file),
        ],
        if (result.truncated) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            'Showing the top results per category. Rescan after cleaning to '
            'see more.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
