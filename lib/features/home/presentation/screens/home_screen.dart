import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/features/history/presentation/widgets/cleanup_history_card.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/quick_tools_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/recommendations_card.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/smart_scan_cta.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/storage_overview_card.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';

/// Home (UI V2.1).
///
/// ## Order, and why
///
/// 1. **Compact header** — identity and Settings, nothing oversized.
/// 2. **Storage Overview** — the question the user opened the app to answer.
/// 3. **Smart Scan hero** — the single primary action, with the privacy note.
/// 4. **Recommended for you** — real findings from real scans.
/// 5. **Quick Tools** — secondary, compact, always available.
/// 6. **Cleanup summary** — real history, or an honest empty state.
///
/// This screen only reports and routes. No storage calculation, scan, or
/// destination changed.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Sends each recommendation to the tool that owns it.
  ///
  /// Home only routes: the destination screen does the reviewing and, if the
  /// user confirms there, the deleting.
  static void _openRecommendation(
    BuildContext context,
    RecommendationKind kind,
  ) {
    final String route = switch (kind) {
      RecommendationKind.screenshotReview => AppRoutes.screenshotCleaner,
      RecommendationKind.duplicateCleanup => AppRoutes.duplicates,
      RecommendationKind.largeVideoReview => AppRoutes.videos,
    };
    context.push(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: AppSpacing.md,
        title: const _HomeHeaderTitle(),
        actions: <Widget>[
          _HeaderIconButton(
            buttonKey: const Key('home_settings_button'),
            tooltip: 'Settings',
            icon: Icons.settings_outlined,
            onTap: () => context.go(AppRoutes.settings),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(storageOverviewProvider);
            refreshRecommendations(ref);
            await ref.read(storageOverviewProvider.future);
          },
          child: ListView(
            key: const Key('home_dashboard'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xxs,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: <Widget>[
              const StorageOverviewCard(),
              const SizedBox(height: HomeMetrics.sectionGap),

              // The one primary action, given the most visual weight.
              SmartScanCta(onScan: () => context.go(AppRoutes.clean)),
              const SizedBox(height: HomeMetrics.sectionGap),

              // Real findings first: this section is empty-by-default and
              // only appears with something concrete to say.
              RecommendationsCard(
                onScan: () => context.go(AppRoutes.clean),
                onOpen: (RecommendationKind kind) =>
                    _openRecommendation(context, kind),
              ),
              const SizedBox(height: HomeMetrics.sectionGap),

              QuickToolsSection(
                onPhotos: () => context.go(AppRoutes.photos),
                onFiles: () => context.push(AppRoutes.largeFiles),
                onApps: () => context.go(AppRoutes.apps),
                onPermissions: () => context.push(AppRoutes.permissions),
              ),
              const SizedBox(height: HomeMetrics.sectionGap),

              // Real history when it exists, an honest empty state before.
              CleanupHistoryCard(
                onOpen: () => context.push(AppRoutes.history),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact identity: a small polished mark, the app name, and one quiet
/// tagline underneath. Deliberately not oversized — the storage card below
/// says everything else with real numbers.
class _HomeHeaderTitle extends StatelessWidget {
  const _HomeHeaderTitle();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[AppColors.primary, AppColors.primaryDeep],
            ),
            borderRadius: BorderRadius.circular(AppRadius.tile),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Mobile Cleaner',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Clean more. Save more. Do more.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A header action inside a subtle rounded surface, matching the card
/// language rather than floating as a bare icon.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: InkWell(
          key: buttonKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.tile),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppColors.border,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
