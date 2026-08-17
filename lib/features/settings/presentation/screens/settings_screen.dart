import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/constants/app_constants.dart';
import 'package:mobile_cleaner/features/onboarding/data/onboarding_preferences.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const ListTile(
            leading: Icon(Icons.brightness_6_outlined),
            title: Text('Appearance'),
            subtitle: Text('Uses your device theme'),
          ),
          const Divider(),
          ListTile(
            key: const Key('manage_permissions'),
            leading: const Icon(Icons.folder_shared_rounded),
            title: const Text('Media and storage access'),
            subtitle: const Text('Review or update permissions'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(AppRoutes.permissions),
          ),
          const Divider(),
          ListTile(
            key: const Key('open_cleanup_history'),
            leading: const Icon(Icons.history_rounded),
            title: const Text('Cleanup history'),
            subtitle: const Text('What you have removed, and when'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(AppRoutes.history),
          ),
          const Divider(),
          ListTile(
            key: const Key('replay_onboarding'),
            leading: const Icon(Icons.slideshow_rounded),
            title: const Text('Replay onboarding'),
            subtitle: const Text('View the introduction again'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _replayOnboarding(context),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('App version'),
            subtitle: Text(AppConstants.appVersion),
          ),
        ],
      ),
    );
  }

  Future<void> _replayOnboarding(BuildContext context) async {
    await OnboardingPreferences.reset();
    if (context.mounted) {
      context.go(AppRoutes.onboarding);
    }
  }
}
