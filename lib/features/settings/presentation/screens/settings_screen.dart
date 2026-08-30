import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/navigation/root_back_button.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/core/constants/app_constants.dart';
import 'package:mobile_cleaner/features/files/domain/download_age_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';
import 'package:mobile_cleaner/features/onboarding/data/onboarding_preferences.dart';
import 'package:mobile_cleaner/features/settings/domain/app_settings.dart';
import 'package:mobile_cleaner/features/settings/presentation/providers/settings_provider.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

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
      backgroundColor: _SettingsStyle.background(context),
      appBar: AppBar(
        backgroundColor: _SettingsStyle.background(context),
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 60,
        leading: const RootBackButton(buttonKey: Key('settings_back_button')),
        title: Text(
          'Settings',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('settings_list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
          children: <Widget>[
            const _SectionHeading(label: 'Appearance'),
            _SettingsGroup(children: <Widget>[_ThemeTile(settings: settings)]),
            const _SectionHeading(label: 'Cleanup defaults'),
            _SettingsGroup(
              footer: Text(
                'Each cleanup tool can still be adjusted while you use it.',
                key: const Key('settings_defaults_note'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              children: <Widget>[
                _ChoiceTile<LargeFileFilter>(
                  tileKey: const Key('setting_large_file_threshold'),
                  valueKey: const Key('setting_large_file_threshold_value'),
                  icon: PhosphorIconsDuotone.gauge,
                  title: 'Large-file threshold',
                  value: settings.largeFileFilter,
                  options: LargeFileFilter.values,
                  labelOf: (LargeFileFilter v) => v.label,
                  onChanged: (LargeFileFilter v) =>
                      saveSettings(ref, settings.copyWith(largeFileFilter: v)),
                ),
                _ChoiceTile<ScreenshotGroup>(
                  tileKey: const Key('setting_screenshot_age'),
                  valueKey: const Key('setting_screenshot_age_value'),
                  icon: PhosphorIconsDuotone.deviceMobileCamera,
                  title: 'Screenshot age',
                  value: settings.screenshotGroup,
                  options: ScreenshotGroup.values,
                  labelOf: (ScreenshotGroup v) => v.label,
                  onChanged: (ScreenshotGroup v) =>
                      saveSettings(ref, settings.copyWith(screenshotGroup: v)),
                ),
                _ChoiceTile<DownloadAgeFilter>(
                  tileKey: const Key('setting_download_age'),
                  valueKey: const Key('setting_download_age_value'),
                  icon: PhosphorIconsDuotone.downloadSimple,
                  title: 'Download age',
                  value: settings.downloadAgeFilter,
                  options: DownloadAgeFilter.values,
                  labelOf: (DownloadAgeFilter v) => v.label,
                  onChanged: (DownloadAgeFilter v) => saveSettings(
                    ref,
                    settings.copyWith(downloadAgeFilter: v),
                  ),
                ),
              ],
            ),
            const _SectionHeading(label: 'Advanced'),
            _SettingsGroup(
              children: <Widget>[
                _ActionTile(
                  tileKey: const Key('open_cleanup_history'),
                  icon: PhosphorIconsDuotone.clockCounterClockwise,
                  title: 'Cleanup history',
                  onTap: () => context.push(AppRoutes.history),
                ),
                _ActionTile(
                  tileKey: const Key('replay_onboarding'),
                  icon: PhosphorIconsDuotone.presentation,
                  title: 'Replay onboarding',
                  onTap: () => _replayOnboarding(context),
                ),
              ],
            ),
            const _SectionHeading(label: 'Privacy & data'),
            _SettingsGroup(
              children: <Widget>[
                _ActionTile(
                  tileKey: const Key('manage_permissions'),
                  icon: PhosphorIconsDuotone.folderLock,
                  title: 'Storage & media access',
                  onTap: () => context.push(AppRoutes.permissions),
                ),
                _ActionTile(
                  tileKey: const Key('open_privacy_policy'),
                  icon: PhosphorIconsDuotone.shieldCheck,
                  title: 'Privacy policy',
                  onTap: () => showPrivacyPolicy(context),
                ),
              ],
            ),
            const _SectionHeading(label: 'About'),
            _SettingsGroup(
              children: <Widget>[
                _ActionTile(
                  tileKey: const Key('open_about'),
                  icon: PhosphorIconsDuotone.info,
                  title: 'About Mobile Cleaner',
                  value: AppConstants.appVersion,
                  valueKey: const Key('setting_app_version'),
                  onTap: () => showAboutSheet(context),
                ),
              ],
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

abstract final class _SettingsStyle {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color background(BuildContext context) =>
      isDark(context) ? AppColors.darkBackground : HomeUpperStyle.background;

  static Color surface(BuildContext context) =>
      isDark(context) ? AppColors.darkSurfaceElevated : HomeUpperStyle.card;

  static Color border(BuildContext context) =>
      isDark(context) ? AppColors.darkBorder : HomeUpperStyle.border;

  static Color blue(BuildContext context) =>
      isDark(context) ? AppColors.darkPrimary : HomeUpperStyle.primaryBlue;

  static Color orange(BuildContext context) =>
      isDark(context) ? AppColors.darkOrange : HomeUpperStyle.orange;
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children, this.footer});

  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final bool dark = _SettingsStyle.isDark(context);
    final Color border = _SettingsStyle.border(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _SettingsStyle.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
        boxShadow: dark
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: HomeUpperStyle.navy.withValues(alpha: 0.045),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        children: <Widget>[
          for (int index = 0; index < children.length; index++) ...<Widget>[
            children[index],
            if (index != children.length - 1)
              Divider(height: 1, indent: 62, color: border),
          ],
          if (footer != null) ...<Widget>[
            Divider(height: 1, indent: 62, color: border),
            Padding(
              padding: const EdgeInsets.fromLTRB(62, 10, 16, 13),
              child: footer!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.valueKey,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: tileKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          child: Row(
            children: <Widget>[
              _SettingIcon(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (value != null)
                Text(
                  value!,
                  key: valueKey,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(width: 7),
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _SettingsStyle.isDark(context)
            ? AppColors.darkInfoSurface
            : HomeUpperStyle.softBlue,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(
        child: PhosphorIcon(
          icon,
          size: 21,
          color: _SettingsStyle.blue(context),
          duotoneSecondaryColor: _SettingsStyle.orange(context),
          duotoneSecondaryOpacity: 0.85,
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: _SettingsStyle.blue(context),
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}

/// Compact theme row matching the reference; choices open only when needed.
class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({required this.settings});

  final AppSettings settings;

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final ThemeMode? chosen = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      backgroundColor: _SettingsStyle.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Choose theme',
                style: Theme.of(sheetContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              SegmentedButton<ThemeMode>(
                key: const Key('setting_theme_mode_control'),
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
                  if (selection.isNotEmpty) {
                    Navigator.of(sheetContext).pop(selection.first);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen != null && chosen != settings.themeMode) {
      await saveSettings(ref, settings.copyWith(themeMode: chosen));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ActionTile(
      tileKey: const Key('setting_theme_mode'),
      icon: PhosphorIconsDuotone.palette,
      title: 'Theme',
      value: settings.themeLabel,
      valueKey: const Key('setting_theme_mode_value'),
      onTap: () => _pickTheme(context, ref),
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
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  Future<void> _pick(BuildContext context) async {
    final T? chosen = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      backgroundColor: _SettingsStyle.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  title,
                  style: Theme.of(sheetContext).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              for (final T option in options)
                ListTile(
                  key: Key('option_${option.name}'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(
                    labelOf(option),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: option == value
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: _SettingsStyle.blue(sheetContext),
                        )
                      : null,
                  selected: option == value,
                  selectedTileColor: _SettingsStyle.blue(sheetContext)
                      .withValues(alpha: 0.08),
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
            ],
          ),
        ),
      ),
    );

    if (chosen != null && chosen != value) {
      onChanged(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: tileKey,
        onTap: () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          child: Row(
            children: <Widget>[
              _SettingIcon(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Text(
                labelOf(value),
                key: valueKey,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _SettingsStyle.blue(context),
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
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
