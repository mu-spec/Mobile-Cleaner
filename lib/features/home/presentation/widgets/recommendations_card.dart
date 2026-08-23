import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/ui/app_visuals.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';

/// Home's recommendations: fixed rules over the real scan results.
///
/// Renders whatever the engine found. It holds no thresholds of its own, so
/// the rules live in exactly one place and cannot drift from what is shown.
///
/// Advice only — every action opens the tool that owns it, where the normal
/// review-and-confirm flow applies. Nothing here deletes.
class RecommendationsCard extends ConsumerWidget {
  const RecommendationsCard({
    required this.onScan,
    required this.onOpen,
    super.key,
  });

  /// Fallback when there is nothing to suggest yet.
  final VoidCallback onScan;

  /// Opens the tool that owns a recommendation.
  final ValueChanged<RecommendationKind> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Recommendation>> advice = ref.watch(
      recommendationsProvider,
    );

    // The section identity is stable across loading, empty, error, and data
    // states. No recommendations are fabricated when [found] is empty; only
    // the established section container remains present.
    return Column(
      key: const Key('recommendations_section'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        advice.when(
          // Home must stay usable while scans run, so loading and failure both
          // fall back to the plain card rather than a spinner or an error.
          loading: () => _IdleCard(
            onScan: onScan,
            message: 'Checking your storage for cleanup suggestions…',
            showAction: false,
          ),
          error: (Object error, StackTrace stackTrace) => _IdleCard(
            onScan: onScan,
            message: 'Run Smart Scan to get safe, personalized cleanup '
                'suggestions.',
          ),
          data: (List<Recommendation> found) {
            if (found.isEmpty) {
              return _IdleCard(
                onScan: onScan,
                message:
                    'Nothing needs attention right now. Your storage looks '
                    'tidy.',
                icon: Icons.check_circle_outline_rounded,
              );
            }
            return _AdviceCard(recommendations: found, onOpen: onOpen);
          },
        ),
      ],
    );
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.recommendations, required this.onOpen});

  final List<Recommendation> recommendations;
  final ValueChanged<RecommendationKind> onOpen;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xxs,
            bottom: HomeMetrics.headingGap,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        'Recommended for you',
                        key: const Key('recommendations_title'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Based on what is actually on your device.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // A real count of real findings, never a badge for its own sake.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  '${recommendations.length}',
                  key: const Key('recommendations_count'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < recommendations.length; i++)
                _AdviceRow(
                  item: recommendations[i],
                  onOpen: () => onOpen(recommendations[i].kind),
                  showDivider: i < recommendations.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One suggestion: what, why, and where to go.
class _AdviceRow extends StatelessWidget {
  const _AdviceRow({
    required this.item,
    required this.onOpen,
    this.showDivider = true,
  });

  final Recommendation item;
  final VoidCallback onOpen;
  final bool showDivider;

  IconData get _icon => switch (item.kind) {
    RecommendationKind.screenshotReview => Icons.screenshot_rounded,
    RecommendationKind.duplicateCleanup => Icons.copy_all_rounded,
    RecommendationKind.largeVideoReview => Icons.movie_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool high = item.priority == RecommendationPriority.high;

    return Column(
      children: <Widget>[
        InkWell(
          key: Key('recommendation_${item.kind.name}'),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppIconContainer(
                  icon: _icon,
                  backgroundColor: high
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  foregroundColor: high
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        item.title,
                        key: Key('recommendation_title_${item.kind.name}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      // The numbers the rule fired on, so the advice is
                      // checkable rather than something to take on trust.
                      Text(
                        item.detail,
                        key: Key(
                          'recommendation_detail_${item.kind.name}',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: HomeMetrics.rowIconSize,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 70, color: colors.outlineVariant),
      ],
    );
  }
}

/// Shown while scanning, on failure, and when nothing crossed a threshold.
class _IdleCard extends StatelessWidget {
  const _IdleCard({
    required this.onScan,
    required this.message,
    this.icon = Icons.lightbulb_rounded,
    this.showAction = true,
  });

  final VoidCallback onScan;
  final String message;
  final IconData icon;
  final bool showAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppIconContainer(
              icon: icon,
              backgroundColor: colors.secondaryContainer,
              foregroundColor: colors.onSecondaryContainer,
              size: 48,
              iconSize: 24,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Recommended for you',
                    key: const Key('recommendations_title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    message,
                    key: const Key('recommendations_message'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (showAction) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      key: const Key('recommendations_scan'),
                      onPressed: onScan,
                      child: const Text('Scan now'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
