import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';
import 'package:mobile_cleaner/features/storage/presentation/widgets/storage_indicator.dart';

/// Storage status: the first and most important thing on Home.
///
/// ## Wording
///
/// "Internal storage" rather than "Total storage". What Android reports is the
/// usable internal partition, which is always smaller than the number printed
/// on the box — a 128 GB phone reports about 118 GB. Calling that "Total"
/// invites the user to think the app is miscounting.
///
/// Used and available are the two figures a person actually acts on, so they
/// are given equal visual weight and sit side by side. Internal storage is
/// reported underneath as context, not as a headline.
///
/// No calculation changed: every figure still comes straight from
/// [StorageInfo].
class StorageOverviewCard extends ConsumerWidget {
  const StorageOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StorageInfo> storage = ref.watch(storageOverviewProvider);

    return Card(
      child: Padding(
        padding: HomeMetrics.cardPadding,
        child: storage.when(
          loading: () => const _LoadingStorage(),
          error: (Object error, StackTrace stackTrace) => _StorageError(
            onRetry: () => ref.invalidate(storageOverviewProvider),
          ),
          data: (StorageInfo info) => _StorageDetails(info: info),
        ),
      ),
    );
  }
}

class _StorageDetails extends StatelessWidget {
  const _StorageDetails({required this.info});

  final StorageInfo info;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Center(
          child: StorageIndicator(
            usedFraction: info.usedFraction,
            usedPercentage: info.usedPercentage,
          ),
        ),
        const SizedBox(height: 22),
        // The two figures people act on, side by side and equally weighted.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _StorageFigure(
                figureKey: const Key('used_storage'),
                label: 'Used',
                value: ByteFormatter.format(info.usedBytes),
                color: colors.tertiary,
              ),
            ),
            Container(
              width: 1,
              height: 42,
              color: colors.outlineVariant,
              margin: const EdgeInsets.symmetric(horizontal: 16),
            ),
            Expanded(
              child: _StorageFigure(
                figureKey: const Key('free_storage'),
                label: 'Available',
                value: ByteFormatter.format(info.freeBytes),
                color: colors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Row(
          key: const Key('total_storage'),
          children: <Widget>[
            Icon(
              Icons.smartphone_rounded,
              size: 15,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Internal storage',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              ByteFormatter.format(info.totalBytes),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One headline figure: a coloured label above a large value.
class _StorageFigure extends StatelessWidget {
  const _StorageFigure({
    required this.figureKey,
    required this.label,
    required this.value,
    required this.color,
  });

  final Key figureKey;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      key: figureKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _LoadingStorage extends StatelessWidget {
  const _LoadingStorage();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 250,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _StorageError extends StatelessWidget {
  const _StorageError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.storage_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          const Text(
            'Storage information is unavailable',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
