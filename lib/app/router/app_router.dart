import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/features/home/presentation/screens/home_screen.dart';
import 'package:mobile_cleaner/features/settings/presentation/screens/settings_screen.dart';

abstract final class AppRoutes {
  static const String home = '/';
  static const String settings = '/settings';
}

final GoRouter appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
