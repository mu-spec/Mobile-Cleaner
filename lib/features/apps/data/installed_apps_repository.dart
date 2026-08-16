import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/apps/domain/installed_app.dart';

/// What one read of the installed-app list returned.
class InstalledAppsSnapshot {
  const InstalledAppsSnapshot({
    required this.apps,
    this.hasUsageAccess = false,
    this.sizeDetailSupported = true,
  });

  static const InstalledAppsSnapshot empty = InstalledAppsSnapshot(
    apps: <InstalledApp>[],
  );

  final List<InstalledApp> apps;

  /// Whether `PACKAGE_USAGE_STATS` is granted, so sizes are detailed.
  final bool hasUsageAccess;

  /// False below Android 8, where `StorageStatsManager` does not exist.
  final bool sizeDetailSupported;
}

/// Reads installed applications and routes the per-app actions to Android.
///
/// Every action is a handoff: Open, App Settings, and Uninstall all start a
/// platform intent. This app never removes a package itself.
abstract interface class InstalledAppsRepository {
  Future<InstalledAppsSnapshot> getInstalledApps({bool includeIcons = true});

  /// True when Usage Access is granted.
  Future<bool> hasUsageAccess();

  /// Opens the system Usage Access screen. There is no runtime dialog for it.
  Future<bool> openUsageAccessSettings();

  Future<bool> openApp(String packageName);

  Future<bool> openAppSettings(String packageName);

  /// Shows Android's own uninstall confirmation.
  Future<bool> requestUninstall(String packageName);

  /// True when the package is still present, used to confirm an uninstall.
  Future<bool> isInstalled(String packageName);
}

final Provider<InstalledAppsRepository> installedAppsRepositoryProvider =
    Provider<InstalledAppsRepository>(
      (ref) => PlatformInstalledAppsRepository(),
    );

class PlatformInstalledAppsRepository implements InstalledAppsRepository {
  PlatformInstalledAppsRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.mobilecleaner.app/installed_apps';

  final MethodChannel _channel;

  @override
  Future<InstalledAppsSnapshot> getInstalledApps({
    bool includeIcons = true,
  }) async {
    try {
      final Map<Object?, Object?>? payload = await _channel
          .invokeMapMethod<Object?, Object?>(
            'getInstalledApps',
            <String, Object>{'includeIcons': includeIcons},
          );
      return parseSnapshot(payload);
    } on PlatformException {
      return InstalledAppsSnapshot.empty;
    } on MissingPluginException {
      return InstalledAppsSnapshot.empty;
    }
  }

  @override
  Future<bool> hasUsageAccess() => _invokeBool('hasUsageAccess');

  @override
  Future<bool> openUsageAccessSettings() =>
      _invokeBool('openUsageAccessSettings');

  @override
  Future<bool> openApp(String packageName) =>
      _invokeBool('openApp', packageName);

  @override
  Future<bool> openAppSettings(String packageName) =>
      _invokeBool('openAppSettings', packageName);

  @override
  Future<bool> requestUninstall(String packageName) =>
      _invokeBool('uninstallApp', packageName);

  @override
  Future<bool> isInstalled(String packageName) =>
      _invokeBool('isInstalled', packageName);

  /// Calls a boolean method, treating any failure as `false`.
  ///
  /// A failed handoff must surface as "that did not work" in the UI rather
  /// than as an unhandled exception.
  Future<bool> _invokeBool(String method, [String? packageName]) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        method,
        packageName == null ? null : <String, Object>{'package': packageName},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Parses the platform payload, dropping malformed rows.
  ///
  /// Exposed for testing.
  static InstalledAppsSnapshot parseSnapshot(Map<Object?, Object?>? payload) {
    if (payload == null) {
      return InstalledAppsSnapshot.empty;
    }

    final Object? rawApps = payload['apps'];
    final List<InstalledApp> apps = <InstalledApp>[];
    if (rawApps is List<Object?>) {
      for (final Object? row in rawApps) {
        if (row is! Map<Object?, Object?>) {
          continue;
        }
        final InstalledApp? app = InstalledApp.fromPlatformMap(row);
        if (app != null) {
          apps.add(app);
        }
      }
    }

    return InstalledAppsSnapshot(
      apps: apps,
      hasUsageAccess: payload['hasUsageAccess'] == true,
      // Absent means supported, matching modern devices.
      sizeDetailSupported: payload['sizeDetailSupported'] != false,
    );
  }
}
