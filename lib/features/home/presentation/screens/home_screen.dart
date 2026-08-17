import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/quick_tools_section.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/recommendations_card.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/storage_overview_card.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';

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
    final ColorScheme colors = Theme.of(context).colorScheme;
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: <Widget>[
              Text(
                'Your storage at a glance',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Understand what is using space, then choose what to review.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              const StorageOverviewCard(),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('smart_scan_button'),
                  onPressed: () => context.go(AppRoutes.clean),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Smart Scan'),
                ),
              ),
              const SizedBox(height: 30),
              QuickToolsSection(
                onPhotos: () => context.go(AppRoutes.photos),
                onFiles: () => context.push(AppRoutes.largeFiles),
                onApps: () => context.go(AppRoutes.apps),
                onPermissions: () => context.push(AppRoutes.permissions),
              ),
              const SizedBox(height: 30),
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
