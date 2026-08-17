import 'package:flutter/material.dart';
import 'package:mobile_cleaner/features/files/domain/download_age_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';

/// Every user preference, in one immutable value.
///
/// The three filter settings are *starting points*, not locks: a tool still
/// shows its own chips, and changing them there affects only that visit. This
/// setting decides what the tool opens on.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.largeFileFilter = LargeFileFilter.defaultFilter,
    this.screenshotGroup = ScreenshotGroup.defaultGroup,
    this.downloadAgeFilter = DownloadAgeFilter.defaultFilter,
  });

  /// The defaults a fresh install starts with.
  static const AppSettings defaults = AppSettings();

  /// System, light, or dark.
  final ThemeMode themeMode;

  /// Size a file must reach before Large Files lists it.
  final LargeFileFilter largeFileFilter;

  /// Age bucket the Screenshot cleaner opens on.
  final ScreenshotGroup screenshotGroup;

  /// Age a download must reach before the Downloads cleaner lists it.
  final DownloadAgeFilter downloadAgeFilter;

  AppSettings copyWith({
    ThemeMode? themeMode,
    LargeFileFilter? largeFileFilter,
    ScreenshotGroup? screenshotGroup,
    DownloadAgeFilter? downloadAgeFilter,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      largeFileFilter: largeFileFilter ?? this.largeFileFilter,
      screenshotGroup: screenshotGroup ?? this.screenshotGroup,
      downloadAgeFilter: downloadAgeFilter ?? this.downloadAgeFilter,
    );
  }

  /// Human label for the current theme choice.
  String get themeLabel => switch (themeMode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  /// Stable string for [ThemeMode], so stored values survive a Flutter
  /// upgrade that reorders the enum.
  ///
  /// Enum *indexes* must never be persisted for the same reason.
  static String encodeThemeMode(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
  };

  static ThemeMode decodeThemeMode(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    // Anything unrecognised falls back to following the device.
    _ => ThemeMode.system,
  };

  /// Looks up an enum value by name, falling back when it is missing or
  /// unrecognised.
  ///
  /// Names are stored rather than indexes so that adding or reordering a
  /// threshold cannot silently change what a user already chose.
  static T decodeByName<T extends Enum>(
    String? raw,
    List<T> values,
    T fallback,
  ) {
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    for (final T value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettings &&
          other.themeMode == themeMode &&
          other.largeFileFilter == largeFileFilter &&
          other.screenshotGroup == screenshotGroup &&
          other.downloadAgeFilter == downloadAgeFilter);

  @override
  int get hashCode => Object.hash(
    themeMode,
    largeFileFilter,
    screenshotGroup,
    downloadAgeFilter,
  );
}
