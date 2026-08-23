import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/ui/app_card.dart';
import 'package:mobile_cleaner/core/ui/app_visuals.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_entry.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_history.dart';
import 'package:mobile_cleaner/features/history/presentation/providers/cleanup_history_provider.dart';

/// Compact Home summary of the persisted cleanup history.
///
/// Every number comes directly from [cleanupHistoryProvider]. Loading and
/// failure are represented explicitly, and an empty log is never turned into
/// a made-up cleanup amount.
class CleanupHistoryCard extends ConsumerWidget {
  const CleanupHistoryCard({required this.onOpen, super.key});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CleanupHistory> history = ref.watch(
      cleanupHistoryProvider,
    );

    return history.when(
      loading: () => const _LoadingHistoryCard(),
      error: (Object error, StackTrace stackTrace) => _HistoryErrorCard(
        onRetry: () => ref.invalidate(cleanupHistoryProvider),
      ),
      data: (CleanupHistory data) {
        if (data.isEmpty) {
          return const _EmptyHistoryCard();
        }
        return _HistorySummaryCard(history: data, onOpen: onOpen);
      },
    );
  }
}

class _HistorySummaryCard extends StatelessWidget {
  const _HistorySummaryCard({required this.history, required this.onOpen});

  final CleanupHistory history;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final CleanupEntry? latest = history.mostRecent;
    final String latestLabel = latest == null
        ? 'View your cleanup history'
        : 'Last cleanup ${DateFormatter.relative(latest.day).toLowerCase()}';

    return AppCard(
      cardKey: const Key('home_history_card'),
      onTap: onOpen,
      child: Row(
        children: <Widget>[
          const AppIconContainer(
            icon: Icons.history_rounded,
            accent: AppColors.success,
            size: 44,
            iconSize: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  ByteFormatter.format(history.totalBytesRecovered),
                  key: const Key('home_history_total'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Cleaned so far',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  latestLabel,
                  key: const Key('home_history_latest'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_rounded,
            color: colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return AppCard(
      cardKey: const Key('home_history_empty'),
      child: Row(
        children: <Widget>[
          AppIconContainer(
            icon: Icons.history_rounded,
            accent: colors.onSurfaceVariant,
            size: 44,
            iconSize: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'No cleanups yet',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Space you free up will be tracked here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
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

class _LoadingHistoryCard extends StatelessWidget {
  const _LoadingHistoryCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      cardKey: Key('home_history_loading'),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(child: Text('Loading cleanup summary…')),
        ],
      ),
    );
  }
}

class _HistoryErrorCard extends StatelessWidget {
  const _HistoryErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return AppCard(
      cardKey: const Key('home_history_error'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppIconContainer(
            icon: Icons.history_toggle_off_rounded,
            accent: colors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Cleanup summary is unavailable'),
                const SizedBox(height: AppSpacing.xxs),
                TextButton(
                  key: const Key('home_history_retry'),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
