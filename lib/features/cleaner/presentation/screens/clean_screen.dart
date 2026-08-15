import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/smart_scan_result.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/smart_scan_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';

/// Smart Scan: runs the large files, old downloads, and APK checks together.
///
/// This screen only reports and routes. Deleting still happens in the tool
/// that owns each category, so there is exactly one delete path in the app.
class CleanScreen extends ConsumerWidget {
  const CleanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SmartScanResult> scan = ref.watch(smartScanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Scan'),
        actions: <Widget>[
          IconButton(
            key: const Key('smart_scan_rescan'),
            tooltip: 'Scan again',
            onPressed: () => refreshSmartScan(ref),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            refreshSmartScan(ref);
            await ref.read(smartScanProvider.future);
          },
          child: scan.when(
            loading: () => const FilesScanningView(),
            error: (Object error, StackTrace stackTrace) => FilesErrorView(
              error: error,
              onRetry: () => refreshSmartScan(ref),
              onPermissions: () => context.push(AppRoutes.permissions),
            ),
            data: (SmartScanResult result) => result.isEmpty
                ? const _NothingFound()
                : _ScanFindings(result: result),
          ),
        ),
      ),
    );
  }
}

class _ScanFindings extends StatelessWidget {
  const _ScanFindings({required this.result});

  final SmartScanResult result;

  void _openTool(BuildContext context, SmartScanCategory category) {
    final String route = switch (category) {
      SmartScanCategory.largeFiles => AppRoutes.largeFiles,
      SmartScanCategory.oldDownloads => AppRoutes.downloadsCleaner,
      SmartScanCategory.apkInstallers => AppRoutes.apkCleaner,
    };
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('smart_scan_findings'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        _TotalCard(result: result),
        const SizedBox(height: 18),
        Text(
          'What we found',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Open a tool to review and remove.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final SmartScanCategory category in SmartScanCategory.values)
          _GroupCard(
            group: result.groupFor(category),
            onOpen: () => _openTool(context, category),
          ),
        const SizedBox(height: 18),
        Text(
          'Biggest items',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        for (final ScannedFile file in result.uniqueFiles.take(5))
          ScannedFileTile(file: file),
      ],
    );
  }
}

/// Headline: how much could be recovered in total.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.result});

  final SmartScanResult result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('smart_scan_total_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Could be recovered',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ByteFormatter.format(result.totalBytes),
              key: const Key('smart_scan_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'across ${result.totalFiles} '
              '${result.totalFiles == 1 ? 'file' : 'files'}',
              key: const Key('smart_scan_total_files'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (result.hasOverlap) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Some files match more than one check and are counted once '
                'here.',
                key: const Key('smart_scan_overlap_note'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onOpen});

  final SmartScanGroup group;
  final VoidCallback onOpen;

  IconData get _icon => switch (group.category) {
    SmartScanCategory.largeFiles => Icons.data_usage_rounded,
    SmartScanCategory.oldDownloads => Icons.history_rounded,
    SmartScanCategory.apkInstallers => Icons.android_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool empty = group.isEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: Key('smart_group_${group.category.name}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: empty
              ? colors.surfaceContainerHighest
              : colors.primaryContainer,
          child: Icon(
            _icon,
            color: empty ? colors.onSurfaceVariant : colors.primary,
          ),
        ),
        title: Text(
          group.category.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          empty
              ? 'Nothing found'
              : '${group.fileCount} '
                    '${group.fileCount == 1 ? 'file' : 'files'} · '
                    '${ByteFormatter.format(group.totalBytes)}',
          key: Key('smart_group_summary_${group.category.name}'),
        ),
        trailing: empty
            ? null
            : const Icon(Icons.chevron_right_rounded),
        // An empty check has nothing to review, so it is not tappable.
        onTap: empty ? null : onOpen,
      ),
    );
  }
}

class _NothingFound extends StatelessWidget {
  const _NothingFound();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('smart_scan_clean'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 60),
        Icon(
          Icons.check_circle_outline_rounded,
          size: 64,
          color: colors.primary,
        ),
        const SizedBox(height: 18),
        Text(
          'Nothing to clean',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'No large files, old downloads, or leftover installers were found.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
