import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/features/cleaner/domain/scan_launch_target.dart';
import 'package:mobile_cleaner/features/history/presentation/providers/cleanup_history_provider.dart';
import 'package:mobile_cleaner/features/history/presentation/widgets/cleanup_history_card.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/quick_tools_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/smart_scan_cta.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/storage_overview_card.dart';
import 'package:mobile_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:mobile_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';

/// UI V2.1 Home.
///
/// The required hierarchy is Header → Storage → Smart Scan → Cleanup
/// Summary → Recommended for you. Quick Tools and the in-header Settings
/// button were removed for a cleaner, less crowded premium Home; Settings
/// remains reachable from bottom navigation. This widget only reads real
/// providers and routes to existing destinations.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static Future<void> _launchScan(
    BuildContext context,
    WidgetRef ref,
    ScanLaunchTarget target,
  ) async {
    AppPermissionStatus status;
    try {
      status = await ref.read(permissionGatewayProvider).checkMediaAndStorage();
    } catch (_) {
      status = AppPermissionStatus.denied;
    }
    if (!context.mounted) {
      return;
    }
    final String route = status == AppPermissionStatus.granted
        ? AppRoutes.progressForScan(target)
        : AppRoutes.permissionsForScan(target);
    context.push(route);
  }

  static ScanLaunchTarget _targetForRecommendation(RecommendationKind kind) {
    return switch (kind) {
      RecommendationKind.screenshotReview => ScanLaunchTarget.screenshots,
      RecommendationKind.duplicateCleanup => ScanLaunchTarget.duplicates,
      RecommendationKind.largeVideoReview => ScanLaunchTarget.largeVideos,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    final double headerHeight = (48 + (textScale - 1) * 48)
        .clamp(48.0, 116.0)
        .toDouble();

    return Scaffold(
      backgroundColor: isDark
          ? theme.scaffoldBackgroundColor
          : HomeUpperStyle.background,
      appBar: AppBar(
        toolbarHeight: headerHeight,
        titleSpacing: AppSpacing.md,
        title: const _HomeHeaderTitle(),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(storageOverviewProvider);
            ref.invalidate(cleanupHistoryProvider);
            refreshRecommendations(ref);
            await ref.read(storageOverviewProvider.future);
          },
          child: SingleChildScrollView(
            key: const Key('home_dashboard'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xxs,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const StorageOverviewCard(),
                const SizedBox(height: HomeMetrics.sectionGap),
                SmartScanCta(
                  onScan: () {
                    _launchScan(context, ref, ScanLaunchTarget.smartScan);
                  },
                  onOpen: (RecommendationKind kind) {
                    _launchScan(context, ref, _targetForRecommendation(kind));
                  },
                ),
                const SizedBox(height: HomeMetrics.sectionGap),
                QuickToolsSection(
                  onPhotos: () => context.go(AppRoutes.photos),
                  onFiles: () => context.push(AppRoutes.largeFiles),
                  onApps: () => context.go(AppRoutes.apps),
                  onPermissions: () => context.push(AppRoutes.permissions),
                ),
                const SizedBox(height: HomeMetrics.sectionGap),
                const _CompactHomeSectionLabel(title: 'Cleanup Summary'),
                CleanupHistoryCard(
                  onOpen: () => context.push(AppRoutes.history),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactHomeSectionLabel extends StatelessWidget {
  const _CompactHomeSectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: HomeMetrics.headingGap),
      child: Semantics(
        header: true,
        child: Text(
          key: const Key('cleanup_summary_title'),
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark ? theme.colorScheme.onSurface : AppColors.navy,
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
    final bool isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Mobile Cleaner',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: isDark
                ? theme.colorScheme.onSurface
                : HomeUpperStyle.textPrimary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          'Clean smarter. Keep what matters.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10.5,
            color: isDark
                ? theme.colorScheme.onSurfaceVariant
                : HomeUpperStyle.textSecondary,
          ),
        ),
      ],
    );
  }
}
