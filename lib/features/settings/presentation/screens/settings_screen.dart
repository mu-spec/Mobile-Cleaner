import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/navigation/root_back_button.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/constants/app_constants.dart';
import 'package:mobile_cleaner/features/files/domain/download_age_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/onboarding/data/onboarding_preferences.dart';
import 'package:mobile_cleaner/features/settings/domain/app_settings.dart';
import 'package:mobile_cleaner/features/settings/presentation/providers/settings_provider.dart';

/// Settings.
///
/// The three threshold settings are *starting points*, not locks: each tool
/// still shows its own chips, and changing them there affects only that visit.
/// This decides what a tool opens on.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Falls back to defaults while loading, so Settings is never blank and
    // never shows a spinner for values that arrive in milliseconds.
    final AppSettings settings =
        ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return Scaffold(
      appBar: AppBar(
        leading: const RootBackButton(buttonKey: Key('settings_back_button')),
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('settings_list'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: <Widget>[
            _SectionHeading(label: 'Appearance'),
            _ThemeTile(settings: settings),
            const Divider(),

            _SectionHeading(label: 'Cleanup defaults'),
            _ChoiceTile<LargeFileFilter>(
              tileKey: const Key('setting_large_file_threshold'),
              valueKey: const Key('setting_large_file_threshold_value'),
              icon: Icons.data_usage_rounded,
              title: 'Large-file threshold',
              subtitle: 'Files at least ${settings.largeFileFilter.threshold}',
              value: settings.largeFileFilter,
              options: LargeFileFilter.values,
              labelOf: (LargeFileFilter v) => v.label,
              onChanged: (LargeFileFilter v) =>
                  saveSettings(ref, settings.copyWith(largeFileFilter: v)),
            ),
            _ChoiceTile<ScreenshotGroup>(
              tileKey: const Key('setting_screenshot_age'),
              valueKey: const Key('setting_screenshot_age_value'),
              icon: Icons.screenshot_rounded,
              title: 'Screenshot age',
              subtitle: settings.screenshotGroup.description,
              value: settings.screenshotGroup,
              options: ScreenshotGroup.values,
              labelOf: (ScreenshotGroup v) => v.label,
              onChanged: (ScreenshotGroup v) =>
                  saveSettings(ref, settings.copyWith(screenshotGroup: v)),
            ),
            _ChoiceTile<DownloadAgeFilter>(
              tileKey: const Key('setting_download_age'),
              valueKey: const Key('setting_download_age_value'),
              icon: Icons.download_rounded,
              title: 'Download age',
              subtitle:
                  'Downloads untouched for '
                  '${settings.downloadAgeFilter.threshold}',
              value: settings.downloadAgeFilter,
              options: DownloadAgeFilter.values,
              labelOf: (DownloadAgeFilter v) => v.label,
              onChanged: (DownloadAgeFilter v) =>
                  saveSettings(ref, settings.copyWith(downloadAgeFilter: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Each tool still lets you change this while you are in it.',
                key: const Key('settings_defaults_note'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 28),

            _SectionHeading(label: 'Privacy and data'),
            ListTile(
              key: const Key('manage_permissions'),
              leading: const Icon(Icons.folder_shared_rounded),
              title: const Text('Media and storage access'),
              subtitle: const Text('Review or update permissions'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.permissions),
            ),
            ListTile(
              key: const Key('open_cleanup_history'),
              leading: const Icon(Icons.history_rounded),
              title: const Text('Cleanup history'),
              subtitle: const Text('What you have removed, and when'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(AppRoutes.history),
            ),
            ListTile(
              key: const Key('open_privacy_policy'),
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              subtitle: const Text('What this app does with your data'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showPrivacyPolicy(context),
            ),
            const Divider(height: 28),

            _SectionHeading(label: 'About'),
            ListTile(
              key: const Key('replay_onboarding'),
              leading: const Icon(Icons.slideshow_rounded),
              title: const Text('Replay onboarding'),
              subtitle: const Text('View the introduction again'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _replayOnboarding(context),
            ),
            ListTile(
              key: const Key('open_about'),
              leading: const Icon(Icons.help_outline_rounded),
              title: const Text('About Mobile Cleaner'),
              subtitle: const Text('How it works, and what it will not do'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showAboutSheet(context),
            ),
            const ListTile(
              key: Key('setting_app_version'),
              leading: Icon(Icons.info_outline_rounded),
              title: Text('App version'),
              subtitle: Text(AppConstants.appVersion),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _replayOnboarding(BuildContext context) async {
    await OnboardingPreferences.reset();
    if (context.mounted) {
      context.go(AppRoutes.onboarding);
    }
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// System / Light / Dark, as a segmented control.
///
/// Shown inline rather than behind a dialog: it is the one setting people
/// change to see an immediate effect, and the effect is visible instantly.
class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.brightness_6_outlined, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Theme',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            key: const Key('setting_theme_mode'),
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto_rounded, size: 17),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_rounded, size: 17),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_rounded, size: 17),
              ),
            ],
            selected: <ThemeMode>{settings.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (Set<ThemeMode> selection) {
              if (selection.isEmpty) {
                return;
              }
              saveSettings(ref, settings.copyWith(themeMode: selection.first));
            },
          ),
        ],
      ),
    );
  }
}

/// A setting whose value is picked from a short list of enum options.
class _ChoiceTile<T extends Enum> extends StatelessWidget {
  const _ChoiceTile({
    required this.tileKey,
    required this.valueKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  final Key tileKey;

  /// Key on the trailing value text, passed explicitly rather than derived
  /// from [tileKey] — casting a Key back to a `ValueKey<String>` would throw
  /// if a caller ever passed a different Key subtype.
  final Key valueKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  Future<void> _pick(BuildContext context) async {
    final T? chosen = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                title,
                style: Theme.of(sheetContext).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            // Plain ListTiles with a check mark rather than RadioListTile:
            // `groupValue` and `onChanged` were deprecated on the radio
            // widgets after Flutter 3.32 in favour of a RadioGroup ancestor,
            // and a simple selected-tile list avoids the whole question.
            for (final T option in options)
              ListTile(
                key: Key('option_${option.name}'),
                title: Text(labelOf(option)),
                trailing: option == value
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(sheetContext).colorScheme.primary,
                      )
                    : null,
                selected: option == value,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (chosen != null && chosen != value) {
      onChanged(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: tileKey,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        labelOf(value),
        key: valueKey,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      onTap: () => _pick(context),
    );
  }
}

/// The privacy policy, shown in-app.
///
/// Held in the app rather than behind a link: the policy describes behaviour
/// that is verifiable in this build, and a web page could change independently
/// of the code it describes. It also means the policy is readable offline,
/// which matters for an app that requests storage access.
void showPrivacyPolicy(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) => ListView(
        key: const Key('privacy_policy_sheet'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: const <Widget>[
          _PolicyTitle('Privacy Policy'),
          _PolicySection(
            heading: 'Nothing leaves your device',
            body:
                'Mobile Cleaner has no internet permission. Your files, '
                'file names, photos, thumbnails, and the results of every '
                'scan stay on this phone. Nothing is uploaded, shared, or '
                'sent to any server.',
          ),
          _PolicySection(
            heading: 'No accounts, no tracking',
            body:
                'There is no sign-in, no analytics, no advertising, and '
                'no third-party tracking. The app does not collect a '
                'device identifier.',
          ),
          _PolicySection(
            heading: 'What is stored on this phone',
            body:
                'Your settings, and a cleanup history holding only a '
                'date, a file count, and a size for each cleanup. No file '
                'names are recorded. Clearing the history in Cleanup '
                'History removes it.',
          ),
          _PolicySection(
            heading: 'Why permissions are requested',
            body:
                'Media and storage access is what lets the app list your '
                'files and calculate their sizes. Usage Access, if you '
                'grant it, is used only to read app sizes. Both are '
                'optional, and the app tells you what it cannot do '
                'without them.',
          ),
          _PolicySection(
            heading: 'Deleting is always your decision',
            body:
                'Nothing is deleted automatically. Every removal is shown '
                'to you first, requires an explicit confirmation, and may '
                'ask for a second confirmation from Android itself. '
                'Deletion is permanent and is not recoverable from this '
                'app.',
          ),
        ],
      ),
    ),
  );
}

/// What the app does, and what it will not do.
void showAboutSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) => ListView(
        key: const Key('about_sheet'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: const <Widget>[
          _PolicyTitle(AppConstants.appName),
          _PolicySection(
            heading: 'What it does',
            body:
                'Finds what is using space on your phone — large files, '
                'old downloads, leftover installers, screenshots, '
                'duplicate and similar photos, big videos, and installed '
                'apps — and helps you review it.',
          ),
          _PolicySection(
            heading: 'What it will not do',
            body:
                'It will not delete anything on its own, will not promise '
                'space it cannot actually free, and will not claim to '
                'clean things Android does not let any app touch, such as '
                'other apps\u2019 private data.',
          ),
          _PolicySection(
            heading: 'How suggestions work',
            body:
                'Recommendations come from fixed rules over your real '
                'scan results, and each one shows the numbers it is based '
                'on. Duplicate and similar photo detection runs entirely '
                'on this device.',
          ),
          _PolicySection(heading: 'Version', body: AppConstants.appVersion),
        ],
      ),
    ),
  );
}

class _PolicyTitle extends StatelessWidget {
  const _PolicyTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.heading, required this.body});

  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            heading,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
