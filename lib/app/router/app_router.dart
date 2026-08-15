import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/shell/app_shell.dart';
import 'package:mobile_cleaner/features/apps/presentation/screens/apps_screen.dart';
import 'package:mobile_cleaner/features/cleaner/presentation/screens/clean_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/apk_cleaner_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/downloads_cleaner_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/files_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/screenshot_cleaner_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/large_files_screen.dart';
import 'package:mobile_cleaner/features/home/presentation/screens/home_screen.dart';
import 'package:mobile_cleaner/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:mobile_cleaner/features/permissions/presentation/screens/permission_education_screen.dart';
import 'package:mobile_cleaner/features/photos/presentation/screens/photos_screen.dart';
import 'package:mobile_cleaner/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile_cleaner/features/splash/presentation/screens/splash_screen.dart';

abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String permissions = '/permissions';
  static const String home = '/home';
  static const String clean = '/clean';
  static const String photos = '/photos';
  static const String files = '/files';
  static const String largeFiles = '/large-files';
  static const String downloadsCleaner = '/downloads-cleaner';
  static const String apkCleaner = '/apk-cleaner';
  static const String screenshotCleaner = '/screenshot-cleaner';
  static const String apps = '/apps';
  static const String settings = '/settings';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
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
      builder: (context, state) => const PermissionEducationScreen(),
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
