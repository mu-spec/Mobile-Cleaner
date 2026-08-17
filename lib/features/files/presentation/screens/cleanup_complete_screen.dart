import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/core/ui/success_check.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';

/// Shown after files have actually been removed.
///
/// Reports three things: how many files went, how much space that recovered,
/// and how much free space the device has now. The last figure is read fresh
/// from the platform — the delete flow invalidates the storage provider before
/// pushing this screen, so it reflects the device after the deletion rather
/// than a cached value from before it.
class CleanupCompleteScreen extends ConsumerWidget {
  const CleanupCompleteScreen({required this.result, super.key});

  final DeleteResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AsyncValue<StorageInfo> storage = ref.watch(storageOverviewProvider);

    return Scaffold(
      key: const Key('cleanup_complete_screen'),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                children: <Widget>[
                  const Center(child: SuccessCheck()),
                  const SizedBox(height: 24),
                  Text(
                    'Cleanup Complete',
                    key: const Key('cleanup_title'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your phone has a little more room.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _StatCard(
                    statKey: const Key('cleanup_files_deleted'),
                    icon: Icons.delete_outline_rounded,
                    label: 'Files deleted',
                    value: '${result.deletedCount}',
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    statKey: const Key('cleanup_storage_recovered'),
                    icon: Icons.cleaning_services_rounded,
                    label: 'Storage recovered',
                    value: ByteFormatter.format(result.freedBytes),
                    highlight: true,
                  ),
                  const SizedBox(height: 12),
                  _FreeStorageCard(storage: storage),
                  if (result.failureCount > 0) ...<Widget>[
                    const SizedBox(height: 18),
                    _PartialNotice(result: result),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('cleanup_done'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.statKey,
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final Key statKey;
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 22, color: colors.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              key: statKey,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: highlight ? colors.primary : colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Free space on the device, read fresh after the deletion.
class _FreeStorageCard extends StatelessWidget {
  const _FreeStorageCard({required this.storage});

  final AsyncValue<StorageInfo> storage;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.sd_storage_outlined,
              size: 22,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Free storage now',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: 12),
            storage.when(
              loading: () => const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              // A storage read failure must not spoil a successful cleanup.
              error: (Object error, StackTrace stackTrace) => Text(
                'Unavailable',
                key: const Key('cleanup_free_storage'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              data: (StorageInfo info) => Text(
                ByteFormatter.format(info.freeBytes),
                key: const Key('cleanup_free_storage'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when some files survived, so the screen never overstates the result.
class _PartialNotice extends StatelessWidget {
  const _PartialNotice({required this.result});

  final DeleteResult result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      key: const Key('cleanup_partial_notice'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: colors.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${result.failureCount} '
                  '${result.failureCount == 1 ? 'file' : 'files'} could not '
                  'be removed.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.failures.first.reason,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
