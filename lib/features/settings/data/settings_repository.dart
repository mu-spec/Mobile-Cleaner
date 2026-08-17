import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/download_age_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores user preferences on this device.
abstract interface class SettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
      (ref) => const PreferencesSettingsRepository(),
    );

class PreferencesSettingsRepository implements SettingsRepository {
  const PreferencesSettingsRepository();

  static const String themeKey = 'settings_theme_mode';
  static const String largeFileKey = 'settings_large_file_filter';
  static const String screenshotKey = 'settings_screenshot_group';
  static const String downloadKey = 'settings_download_age';

  @override
  Future<AppSettings> load() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();

    // Every field falls back independently, so one unreadable value cannot
    // reset the others.
    return AppSettings(
      themeMode: AppSettings.decodeThemeMode(preferences.getString(themeKey)),
      largeFileFilter: AppSettings.decodeByName(
        preferences.getString(largeFileKey),
        LargeFileFilter.values,
        LargeFileFilter.defaultFilter,
      ),
      screenshotGroup: AppSettings.decodeByName(
        preferences.getString(screenshotKey),
        ScreenshotGroup.values,
        ScreenshotGroup.defaultGroup,
      ),
      downloadAgeFilter: AppSettings.decodeByName(
        preferences.getString(downloadKey),
        DownloadAgeFilter.values,
        DownloadAgeFilter.defaultFilter,
      ),
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();

    await preferences.setString(
      themeKey,
      AppSettings.encodeThemeMode(settings.themeMode),
    );
    // Names, never indexes: reordering an enum must not change a stored
    // choice into a different one.
    await preferences.setString(
      largeFileKey,
      settings.largeFileFilter.name,
    );
    await preferences.setString(
      screenshotKey,
      settings.screenshotGroup.name,
    );
    await preferences.setString(
      downloadKey,
      settings.downloadAgeFilter.name,
    );
  }
}
