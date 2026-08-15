import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/constants/app_constants.dart';
import 'package:mobile_cleaner/features/onboarding/data/onboarding_preferences.dart';
import 'package:mobile_cleaner/features/permissions/data/permission_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _openApp();
  }

  Future<void> _openApp() async {
    final List<Object> results = await Future.wait(<Future<Object>>[
      Future<bool>.delayed(const Duration(milliseconds: 900), () => true),
      OnboardingPreferences.isCompleted(),
      PermissionPreferences.isEducationSeen(),
    ]);
    final bool hasCompletedOnboarding = results[1] as bool;
    final bool hasSeenPermissionEducation = results[2] as bool;
    if (!mounted) {
      return;
    }
    if (!hasCompletedOnboarding) {
      context.go(AppRoutes.onboarding);
    } else if (!hasSeenPermissionEducation) {
      context.go(AppRoutes.permissions);
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.primary,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: colors.onPrimary,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.cleaning_services_rounded,
                  size: 58,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                AppConstants.appName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Clean safely. Stay in control.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: colors.onPrimary.withValues(alpha: 0.85)),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: colors.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
