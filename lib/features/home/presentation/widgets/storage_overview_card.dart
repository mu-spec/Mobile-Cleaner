import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';
import 'package:mobile_cleaner/features/storage/presentation/widgets/storage_indicator.dart';

class StorageOverviewCard extends ConsumerWidget {
  const StorageOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StorageInfo> storage = ref.watch(storageOverviewProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Storage overview',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        Center(
          child: StorageIndicator(
            usedFraction: info.usedFraction,
            usedPercentage: info.usedPercentage,
          ),
        ),
        const SizedBox(height: 26),
        _StorageRow(
          key: const Key('total_storage'),
          label: 'Total storage',
          value: ByteFormatter.format(info.totalBytes),
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 14),
        _StorageRow(
          key: const Key('used_storage'),
          label: 'Used storage',
          value: ByteFormatter.format(info.usedBytes),
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(height: 14),
        _StorageRow(
          key: const Key('free_storage'),
          label: 'Free storage',
          value: ByteFormatter.format(info.freeBytes),
          // Theme colour, so it adapts in dark mode instead of staying a
          // fixed light-mode green.
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }

}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
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
