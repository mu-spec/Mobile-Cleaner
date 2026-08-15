import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/file_scan_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_category_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';

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
            loading: () => const _ScanningView(),
            error: (Object error, StackTrace stackTrace) => _ScanErrorView(
              error: error,
              onRetry: () => ref.invalidate(fileScanProvider),
              onPermissions: () => context.push(AppRoutes.permissions),
            ),
            data: (FileScanResult result) => _ScanResultView(result: result),
          ),
        ),
      ),
    );
  }
}

class _ScanResultView extends StatelessWidget {
  const _ScanResultView({required this.result});

  final FileScanResult result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    if (result.isEmpty) {
      return ListView(
        key: const Key('files_empty'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: <Widget>[
          const SizedBox(height: 60),
          Icon(
            Icons.folder_off_rounded,
            size: 56,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No files found',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Grant media and storage access, then pull down to scan again.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      );
    }

    return ListView(
      key: const Key('files_overview'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        Card(
          key: const Key('files_summary_card'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Files discovered',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${result.totalFiles} files · '
                        '${ByteFormatter.format(result.totalBytes)}',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.travel_explore_rounded, color: colors.primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('By category', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final FileCategory category in FileCategory.scannable)
          FileCategoryTile(
            summary: result.summaryFor(category),
            totalBytes: result.totalBytes,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CategoryFilesScreen(category: category),
              ),
            ),
          ),
        const SizedBox(height: 18),
        Text('Largest files', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        for (final ScannedFile file in result.largestFiles(limit: 10))
          ScannedFileTile(file: file),
        if (result.truncated) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            'Showing the top results per category. Rescan after cleaning to '
            'see more.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Full list of files inside a single category.
class CategoryFilesScreen extends ConsumerWidget {
  const CategoryFilesScreen({required this.category, super.key});

  final FileCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ScannedFile>> files = ref.watch(
      categoryFilesProvider(category),
    );

    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: SafeArea(
        child: files.when(
          loading: () => const _ScanningView(),
          error: (Object error, StackTrace stackTrace) => _ScanErrorView(
            error: error,
            onRetry: () => ref.invalidate(fileScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (List<ScannedFile> items) {
            if (items.isEmpty) {
              return Center(
                key: Key('category_empty_${category.key}'),
                child: Text('No ${category.label.toLowerCase()} found'),
              );
            }
            return ListView.separated(
              key: Key('category_list_${category.key}'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: items.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) =>
                  ScannedFileTile(file: items[index]),
            );
          },
        ),
      ),
    );
  }
}

class _ScanningView extends StatelessWidget {
  const _ScanningView();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('files_scanning'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            'Scanning your files…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Reading names, sizes, and dates only.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanErrorView extends StatelessWidget {
  const _ScanErrorView({
    required this.error,
    required this.onRetry,
    required this.onPermissions,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onPermissions;

  @override
  Widget build(BuildContext context) {
    final bool permissionIssue = error.toString().contains('PERMISSION');
    return ListView(
      key: const Key('files_error'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: <Widget>[
        const SizedBox(height: 60),
        Icon(
          permissionIssue ? Icons.lock_outline_rounded : Icons.error_outline,
          size: 52,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          permissionIssue
              ? 'Storage access is required'
              : 'We could not scan your files',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        if (permissionIssue)
          FilledButton.icon(
            key: const Key('files_permission_button'),
            onPressed: onPermissions,
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Review permissions'),
          ),
        const SizedBox(height: 10),
        TextButton.icon(
          key: const Key('files_retry_button'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
