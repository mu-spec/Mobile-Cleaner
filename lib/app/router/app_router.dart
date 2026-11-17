import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_storage_cleaner/app/route_observer.dart';
import 'package:phone_storage_cleaner/app/router/permission_policy.dart';
import 'package:phone_storage_cleaner/app/shell/app_shell.dart';
import 'package:phone_storage_cleaner/features/apps/presentation/screens/apps_screen.dart';
import 'package:phone_storage_cleaner/features/cleaner/domain/scan_launch_target.dart';
import 'package:phone_storage_cleaner/features/cleaner/presentation/screens/clean_screen.dart';
import 'package:phone_storage_cleaner/features/cleaner/presentation/screens/scan_progress_screen.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_category.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/apk_cleaner_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/category_files_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/downloads_cleaner_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/duplicates_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/files_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/large_files_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/large_photos_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/photo_duplicates_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/screenshot_cleaner_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/similar_photos_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/videos_screen.dart';
import 'package:phone_storage_cleaner/features/history/presentation/screens/cleanup_history_screen.dart';
import 'package:phone_storage_cleaner/features/home/presentation/screens/home_screen.dart';
import 'package:phone_storage_cleaner/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';
import 'package:phone_storage_cleaner/features/permissions/presentation/providers/permission_manager.dart';
import 'package:phone_storage_cleaner/features/permissions/presentation/screens/permission_education_screen.dart';
import 'package:phone_storage_cleaner/features/photos/presentation/screens/photos_screen.dart';
import 'package:phone_storage_cleaner/features/settings/presentation/screens/settings_screen.dart';
import 'package:phone_storage_cleaner/features/splash/presentation/screens/splash_screen.dart';

abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String permissions = '/permissions';
  static const String scanProgress = '/scan-progress';
  static const String home = '/home';
  static const String clean = '/clean';
  static const String photos = '/photos';
  static const String files = '/files';
  static const String fileCategory = '/file-category';

  static String forFileCategory(FileCategory category) => Uri(
    path: fileCategory,
    queryParameters: {'category': category.key},
  ).toString();
  static const String largeFiles = '/large-files';
  static const String downloadsCleaner = '/downloads-cleaner';
  static const String apkCleaner = '/apk-cleaner';
  static const String screenshotCleaner = '/screenshot-cleaner';
  static const String largePhotos = '/large-photos';
  static const String duplicates = '/duplicates';
  static const String photoDuplicates = '/photo-duplicates';
  static const String similarPhotos = '/similar-photos';
  static const String videos = '/videos';
  static const String history = '/history';
  static const String apps = '/apps';
  static const String settings = '/settings';

  static String permissionsForLocation(String location) => Uri(
    path: permissions,
    queryParameters: <String, String>{'next': location},
  ).toString();

  static String permissionsForScan(ScanLaunchTarget target) {
    return Uri(
      path: permissions,
      queryParameters: <String, String>{'scan': target.routeValue},
    ).toString();
  }

  static String progressForScan(ScanLaunchTarget target) {
    return Uri(
      path: scanProgress,
      queryParameters: <String, String>{'scan': target.routeValue},
    ).toString();
  }
}

final GoRouter appRouter = GoRouter(
  observers: <NavigatorObserver>[storageRouteObserver],
  initialLocation: AppRoutes.splash,
  redirect: _permissionRedirect,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.permissions,
      builder: (context, state) => PermissionEducationScreen(
        destination: permissionDestination(state.uri.queryParameters['next']),
        scanTarget: ScanLaunchTarget.fromRouteValue(
          state.uri.queryParameters['scan'],
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.scanProgress,
      builder: (context, state) => ScanProgressScreen(
        target:
            ScanLaunchTarget.fromRouteValue(
              state.uri.queryParameters['scan'],
            ) ??
            ScanLaunchTarget.smartScan,
      ),
    ),
    GoRoute(
      path: AppRoutes.fileCategory,
      builder: (context, state) => CategoryFilesScreen(
        category: FileCategory.fromKey(state.uri.queryParameters['category']),
      ),
    ),
    GoRoute(
      path: AppRoutes.largeFiles,
      builder: (context, state) => const LargeFilesScreen(),
    ),
    GoRoute(
      path: AppRoutes.downloadsCleaner,
      builder: (context, state) => const DownloadsCleanerScreen(),
    ),
    GoRoute(
      path: AppRoutes.apkCleaner,
      builder: (context, state) => const ApkCleanerScreen(),
    ),
    GoRoute(
      path: AppRoutes.screenshotCleaner,
      builder: (context, state) => const ScreenshotCleanerScreen(),
    ),
    GoRoute(
      path: AppRoutes.largePhotos,
      builder: (context, state) => const LargePhotosScreen(),
    ),
    GoRoute(
      path: AppRoutes.duplicates,
      builder: (context, state) => const DuplicatesScreen(),
    ),
    GoRoute(
      path: AppRoutes.photoDuplicates,
      builder: (context, state) => const PhotoDuplicatesScreen(),
    ),
    GoRoute(
      path: AppRoutes.similarPhotos,
      builder: (context, state) => const SimilarPhotosScreen(),
    ),
    GoRoute(
      path: AppRoutes.videos,
      builder: (context, state) => const VideosScreen(),
    ),
    GoRoute(
      path: AppRoutes.history,
      builder: (context, state) => const CleanupHistoryScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppShell(navigationShell: navigationShell);
      },
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.clean,
              builder: (context, state) => const CleanScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.photos,
              builder: (context, state) => const PhotosScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.files,
              builder: (context, state) => const FilesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.apps,
              builder: (context, state) => const AppsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

FutureOr<String?> _permissionRedirect(
  BuildContext context,
  GoRouterState state,
) {
  final bool explaining = state.uri.path == AppRoutes.permissions;
  Uri? destination = explaining
      ? permissionDestination(state.uri.queryParameters['next'])
      : state.uri;
  if (explaining && destination == null) {
    final ScanLaunchTarget? target = ScanLaunchTarget.fromRouteValue(
      state.uri.queryParameters['scan'],
    );
    if (target != null) {
      destination = Uri.parse(AppRoutes.progressForScan(target));
    }
  }
  if (destination == null) {
    return null; // Explicit permissions/settings overview, not a feature gate.
  }
  final PermissionFeature? feature = permissionFeatureFor(destination);
  if (feature == null) {
    return null;
  }
  if (feature == PermissionFeature.none) {
    return explaining ? destination.toString() : null;
  }
  return _checkFeatureAccess(context, destination, feature, explaining);
}

Future<String?> _checkFeatureAccess(
  BuildContext context,
  Uri destination,
  PermissionFeature feature,
  bool explaining,
) async {
  bool sufficient = false;
  try {
    final PermissionSnapshot actual = await ProviderScope.containerOf(
      context,
      listen: false,
    ).read(permissionManagerProvider.notifier).refresh();
    sufficient = actual.allowsFeature(feature);
  } catch (_) {
    // Unknown access is never accepted as a grant.
  }
  if (sufficient) {
    return explaining ? destination.toString() : null;
  }
  if (explaining) {
    return null; // Never redirect the explanation back into itself.
  }
  return Uri(
    path: AppRoutes.permissions,
    queryParameters: <String, String>{
      'next': destination.toString(),
      if (destination.queryParameters['scan'] case final String scan)
        'scan': scan,
    },
  ).toString();
}

/// GoRouter.refresh rechecks the base URI, not necessarily an imperatively
/// pushed tool. Inspect the visible route so Settings revocation guards it too.
void guardVisibleFeature(PermissionSnapshot snapshot) {
  final Uri current = appRouter.state.uri;
  final PermissionFeature? feature = permissionFeatureFor(current);
  if (feature != null && !snapshot.allowsFeature(feature)) {
    appRouter.pushReplacement(
      AppRoutes.permissionsForLocation(current.toString()),
    );
  }
}
