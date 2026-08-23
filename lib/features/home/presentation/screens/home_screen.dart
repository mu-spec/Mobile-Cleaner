import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/ui/app_visuals.dart';
import 'package:mobile_cleaner/features/history/presentation/providers/cleanup_history_provider.dart';
import 'package:mobile_cleaner/features/history/presentation/widgets/cleanup_history_card.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/quick_tools_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/recommendations_card.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/smart_scan_cta.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/storage_overview_card.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';

/// UI V2.1 Home.
///
/// The required hierarchy is Header → Storage → Smart Scan → Quick Tools →
/// Cleanup Summary. Existing recommendations remain available after the new
/// primary Home flow so no feature is removed. This widget only reads real
/// providers and routes to existing destinations.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    final double headerHeight = (64 + (textScale - 1) * AppSpacing.xxl)
        .clamp(64.0, 112.0)
        .toDouble();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: headerHeight,
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
            ref.invalidate(cleanupHistoryProvider);
            refreshRecommendations(ref);
            await ref.read(storageOverviewProvider.future);
          },
          child: ListView(
            key: const Key('home_dashboard'),
            // Home is a short dashboard rather than an unbounded feed. Keep
            // its lower cards mounted when responsive sections grow, so the
            // dashboard remains stable as the user scrolls between them.
            cacheExtent: 2000,
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
              SmartScanCta(onScan: () => context.go(AppRoutes.clean)),
              const SizedBox(height: HomeMetrics.sectionGap),
              QuickToolsSection(
                onPhotos: () => context.go(AppRoutes.photos),
                onFiles: () => context.push(AppRoutes.largeFiles),
                onApps: () => context.go(AppRoutes.apps),
                onPermissions: () => context.push(AppRoutes.permissions),
              ),
              const SizedBox(height: HomeMetrics.sectionGap),
              const AppSectionHeader(title: 'Cleanup Summary'),
              CleanupHistoryCard(
                onOpen: () => context.push(AppRoutes.history),
              ),
              const SizedBox(height: HomeMetrics.sectionGap),
              // Preserved from the existing Home feature. It remains based
              // entirely on real scan findings and opens existing tools.
              RecommendationsCard(
                onScan: () => context.go(AppRoutes.clean),
                onOpen: (RecommendationKind kind) =>
                    _openRecommendation(context, kind),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeaderTitle extends StatelessWidget {
  const _HomeHeaderTitle();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Mobile Cleaner',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Clean more. Save more. Do more.',
          maxLines: 2,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

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
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: isDark
              ? theme.colorScheme.surfaceContainerHigh
              : Colors.white,
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
      ),
    );
  }
}
