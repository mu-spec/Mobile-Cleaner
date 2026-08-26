import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/route_observer.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_theme.dart';
import 'package:mobile_cleaner/core/constants/app_constants.dart';
import 'package:mobile_cleaner/features/settings/domain/app_settings.dart';
import 'package:mobile_cleaner/features/settings/presentation/providers/settings_provider.dart';

class MobileCleanerApp extends ConsumerWidget {
  const MobileCleanerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Falls back to following the device while preferences load. The splash
    // screen is on-screen for that moment, so a saved Light or Dark choice is
    // applied before the user sees any real content — no theme flash.
    final ThemeMode themeMode =
        ref.watch(settingsProvider).value?.themeMode ??
        AppSettings.defaults.themeMode;

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
      navigatorObservers: <NavigatorObserver>[storageRouteObserver],
    );
  }
}
