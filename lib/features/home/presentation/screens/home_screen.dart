import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/features/history/presentation/widgets/cleanup_history_card.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/quick_tools_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/recommendations_card.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/smart_scan_cta.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/storage_overview_card.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';

/// Home.
///
/// ## Order, and why
///
/// 1. **Storage** — the question the user opened the app to answer.
/// 2. **Smart Scan** — the single primary action, with the privacy note.
/// 3. **Recommended for you** — real findings from real scans, so it earns
///    its place above the generic tools.
/// 4. **Quick tools** — secondary, compact, always available.
/// 5. **Cleanup history** — context, and only once something has happened.
///
/// The page-level heading and its blurb were removed. They restated the app
/// name and took the whole top of the screen to say nothing the storage card
/// does not say better with real numbers.
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
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.auto_awesome_rounded),
            SizedBox(width: 10),
            Flexible(
              child: Text('Mobile Cleaner', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('home_settings_button'),
            tooltip: 'Settings',
            onPressed: () => context.go(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              const StorageOverviewCard(),
              const SizedBox(height: 20),

              // The one primary action, given the most visual weight.
              //
              // The heading names the feature ("Smart Scan") while the button
              // states the action ("Scan now") — clearer than a button that
              // repeats a product name, and it keeps the feature discoverable
              // by name on the Home screen.
              const HomeSectionHeader(
                title: 'Smart Scan',
                caption: 'Check the whole device for recoverable space.',
              ),
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

              // Renders nothing until a cleanup has actually happened.
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
