import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/navigation/root_back_button.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/smart_scan_result.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/smart_scan_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';

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
        leading: const RootBackButton(buttonKey: Key('clean_back_button')),
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
    final List<SmartScanGroup> ranked = result.nonEmptyGroups;
    final SmartScanGroup? biggest = ranked.isEmpty ? null : ranked.first;

    return ListView(
      key: const Key('smart_scan_findings'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        _RecoverableCard(
          result: result,
          onOpenTool: (SmartScanCategory category) =>
              _openTool(context, category),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('review_cleanup_button'),
            // Opens whichever check holds the most space. `_ScanFindings` is
            // only built for a non-empty result, but read defensively so a
            // future caller cannot trip over an empty list.
            onPressed: biggest == null
                ? null
                : () => _openTool(context, biggest.category),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Review Cleanup'),
          ),
        ),
        const SizedBox(height: 24),
        Text('Biggest items', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        for (final ScannedFile file in result.uniqueFiles.take(5))
          ScannedFileTile(file: file),
      ],
    );
  }
}

/// The "Potentially Recoverable" panel.
///
/// One row per check, each showing its label and size, exactly as the phase
/// spec lays it out.
class _RecoverableCard extends StatelessWidget {
  const _RecoverableCard({required this.result, required this.onOpenTool});

  final SmartScanResult result;
  final ValueChanged<SmartScanCategory> onOpenTool;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('smart_scan_total_card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Potentially Recoverable',
              key: const Key('smart_scan_heading'),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              ByteFormatter.format(result.totalBytes),
              key: const Key('smart_scan_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: HomeUpperStyle.orange,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'across ${result.totalFiles} '
              '${result.totalFiles == 1 ? 'file' : 'files'}',
              key: const Key('smart_scan_total_files'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            for (final SmartScanCategory category in SmartScanCategory.values)
              _RecoverableRow(
                group: result.groupFor(category),
                onOpen: () => onOpenTool(category),
              ),
            if (result.hasOverlap) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Some files match more than one check and are counted once '
                'in the total.',
                key: const Key('smart_scan_overlap_note'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// One line: `Large Files       4.2 GB`.
class _RecoverableRow extends StatelessWidget {
  const _RecoverableRow({required this.group, required this.onOpen});

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

    return InkWell(
      key: Key('smart_group_${group.category.name}'),
      // An empty check has nothing to review.
      onTap: empty ? null : onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(
              _icon,
              size: 20,
              color: empty ? colors.onSurfaceVariant : colors.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                group.category.label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: empty ? colors.onSurfaceVariant : colors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              empty ? 'None' : ByteFormatter.format(group.totalBytes),
              key: Key('smart_group_size_${group.category.name}'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: empty ? colors.onSurfaceVariant : colors.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: empty ? Colors.transparent : colors.onSurfaceVariant,
            ),
          ],
        ),
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
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
