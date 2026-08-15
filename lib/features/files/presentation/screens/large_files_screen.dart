import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_summary.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/large_files_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_category_card.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';

/// Large Files: find the biggest space users above a size threshold.
///
/// Read-only. It surfaces what is taking room and lets the user decide.
class LargeFilesScreen extends ConsumerStatefulWidget {
  const LargeFilesScreen({super.key});

  @override
  ConsumerState<LargeFilesScreen> createState() => _LargeFilesScreenState();
}

class _LargeFilesScreenState extends ConsumerState<LargeFilesScreen> {
  LargeFileFilter _filter = LargeFileFilter.defaultFilter;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<LargeFileSummary> summary = ref.watch(
      largeFileSummaryProvider(_filter),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Large Files'),
        actions: <Widget>[
          IconButton(
            key: const Key('large_files_rescan'),
            tooltip: 'Rescan',
            onPressed: () => ref.invalidate(largeFileScanProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _FilterBar(
              selected: _filter,
              onSelected: (LargeFileFilter value) =>
                  setState(() => _filter = value),
            ),
            Expanded(
              child: summary.when(
                loading: () => const FilesScanningView(),
                error: (Object error, StackTrace stackTrace) => FilesErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(largeFileScanProvider),
                  onPermissions: () => context.push(AppRoutes.permissions),
                ),
                data: (LargeFileSummary data) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(largeFileScanProvider);
                    await ref.read(largeFileScanProvider.future);
                  },
                  child: data.isEmpty
                      ? _EmptyLargeFiles(filter: _filter)
                      : _LargeFileList(summary: data),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Threshold chips: 100 MB+, 500 MB+, 1 GB+.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final LargeFileFilter selected;
  final ValueChanged<LargeFileFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('large_files_filter_bar'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: <Widget>[
          for (final LargeFileFilter option in LargeFileFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('large_filter_${option.name}'),
                label: Text(option.label),
                selected: option == selected,
                onSelected: (_) => onSelected(option),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _LargeFileList extends StatelessWidget {
  const _LargeFileList({required this.summary});

  final LargeFileSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('large_files_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: <Widget>[
        _TotalCard(summary: summary),
        const SizedBox(height: 16),
        Text(
          'Biggest first',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        for (final ScannedFile file in summary.files)
          ScannedFileTile(file: file),
      ],
    );
  }
}

/// Headline card: how much space the matching files occupy.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final LargeFileSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('large_files_total_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Space used by these files',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ByteFormatter.format(summary.totalBytes),
              key: const Key('large_files_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.fileCount} '
              '${summary.fileCount == 1 ? 'file' : 'files'} over '
              '${summary.filter.threshold}',
              key: const Key('large_files_count'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (summary.bytesByCategory.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              _CategoryBreakdown(summary: summary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Which categories the space belongs to.
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.summary});

  final LargeFileSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      key: const Key('large_files_breakdown'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final MapEntry<FileCategory, int> entry
            in summary.bytesByCategory.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colorForCategory(entry.key),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.key.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  ByteFormatter.format(entry.value),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyLargeFiles extends StatelessWidget {
  const _EmptyLargeFiles({required this.filter});

  final LargeFileFilter filter;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('large_files_empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 60),
        Icon(
          Icons.check_circle_outline_rounded,
          size: 56,
          color: colors.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'No files over ${filter.threshold}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Nothing on this phone is that large. Try a smaller threshold.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
