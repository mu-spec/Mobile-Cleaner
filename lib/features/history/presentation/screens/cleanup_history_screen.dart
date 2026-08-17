import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/features/history/data/cleanup_history_repository.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_history.dart';
import 'package:mobile_cleaner/features/history/presentation/providers/cleanup_history_provider.dart';

/// Cleanup History: what has been removed, and when.
///
/// Read-only. Nothing here deletes anything or acts on the device; it reports
/// what already happened.
///
/// Stored locally only, and deliberately without file names — a record of
/// exactly which files someone deleted is far more sensitive than a count, and
/// answering "how much have I cleaned" does not need it.
class CleanupHistoryScreen extends ConsumerWidget {
  const CleanupHistoryScreen({super.key});

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            key: const Key('history_clear_dialog'),
            title: const Text('Clear history?'),
            content: const Text(
              'This removes the record of past cleanups. Your files are not '
              'affected.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const Key('history_clear_confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }
    await ref.read(cleanupHistoryRepositoryProvider).clear();
    ref.invalidate(cleanupHistoryProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CleanupHistory> history = ref.watch(
      cleanupHistoryProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cleanup History'),
        actions: <Widget>[
          if (history.value?.isEmpty == false)
            IconButton(
              key: const Key('history_clear'),
              tooltip: 'Clear history',
              onPressed: () => _confirmClear(context, ref),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stackTrace) =>
              const _NoHistory(failed: true),
          data: (CleanupHistory data) =>
              data.isEmpty ? const _NoHistory() : _HistoryList(history: data),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.history});

  final CleanupHistory history;

  @override
  Widget build(BuildContext context) {
    final List<CleanupDay> days = history.byDay;
    const int headerCount = 1;

    return ListView.builder(
      key: const Key('history_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: days.length + headerCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return _TotalCard(history: history);
        }
        return _DayRow(day: days[index - headerCount]);
      },
    );
  }
}

/// One day: `Today` / `August 11`, then what was cleaned.
class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final CleanupDay day;

  /// Key built from the calendar day, so a test can target a known row.
  String get _dayKey =>
      '${day.day.year}-${day.day.month.toString().padLeft(2, '0')}-'
      '${day.day.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int fileCount = day.filesRemoved;
    final String fileNoun = fileCount == 1 ? 'file' : 'files';
    // Only worth mentioning when a day held more than one cleanup.
    final String cleanupSuffix = day.cleanupCount > 1
        ? ' · ${day.cleanupCount} cleanups'
        : '';

    return Card(
      key: Key('history_day_$_dayKey'),
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.cleaning_services_rounded,
                size: 19,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    // `Today`, `Yesterday`, then a plain date.
                    DateFormatter.relative(day.day),
                    key: Key('history_date_$_dayKey'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$fileCount $fileNoun removed$cleanupSuffix',
                    key: Key('history_files_$_dayKey'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${ByteFormatter.format(day.bytesRecovered)} cleaned',
              key: Key('history_bytes_$_dayKey'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lifetime totals.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.history});

  final CleanupHistory history;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('history_total_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Recovered in total',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ByteFormatter.format(history.totalBytesRecovered),
              key: const Key('history_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${history.totalFilesRemoved} '
              '${history.totalFilesRemoved == 1 ? 'file' : 'files'} across '
              '${history.cleanupCount} '
              '${history.cleanupCount == 1 ? 'cleanup' : 'cleanups'}',
              key: const Key('history_total_files'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.phone_android_rounded,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kept on this device only. No file names are stored.',
                    key: const Key('history_privacy_note'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoHistory extends StatelessWidget {
  const _NoHistory({this.failed = false});

  /// True when the log could not be read, as opposed to being genuinely empty.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('history_empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 60),
        Icon(Icons.history_rounded, size: 56, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          failed ? 'History unavailable' : 'No cleanups yet',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          failed
              ? 'The saved history could not be read.'
              : 'Once you remove files, each cleanup is recorded here.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
