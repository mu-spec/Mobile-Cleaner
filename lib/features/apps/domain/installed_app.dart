import 'package:flutter/services.dart';

/// One installed application, as far as Android will describe it.
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.name,
    required this.apkBytes,
    this.appBytes,
    this.dataBytes,
    this.cacheBytes,
    this.isSystemApp = false,
    this.canOpen = true,
    this.versionName,
    this.versionCode,
    this.installedAt,
    this.updatedAt,
    this.icon,
  });

  /// Unique package id, e.g. `com.example.app`.
  final String packageName;

  /// Display label shown in the launcher.
  final String name;

  /// Installed APK size, including split APKs. Always available.
  final int apkBytes;

  /// Code size reported by `StorageStatsManager`, when Usage Access is on.
  final int? appBytes;

  /// User data size, when Usage Access is on.
  final int? dataBytes;

  /// Cache size, when Usage Access is on.
  final int? cacheBytes;

  /// True for apps shipped with the device or updates to them.
  ///
  /// Surfaced because Android usually refuses to uninstall them, so offering
  /// the action without warning would set the user up to fail.
  final bool isSystemApp;

  /// True when the app has a launcher intent, so Open will actually work.
  final bool canOpen;

  /// Human-readable version declared by the installed package.
  final String? versionName;

  /// Monotonic package version code, when Android reports it.
  final int? versionCode;

  final DateTime? installedAt;
  final DateTime? updatedAt;

  /// Launcher icon as PNG bytes, or null when it could not be rasterised.
  final Uint8List? icon;

  /// True when Android gave a full app + data + cache breakdown.
  ///
  /// When false the only honest figure is [apkBytes], and the UI must label it
  /// as the app size rather than the total footprint.
  bool get hasDetailedSize => appBytes != null && dataBytes != null;

  /// Everything the app occupies, when known.
  ///
  /// Null rather than a partial sum: a total that silently omitted data or
  /// cache would understate the real footprint, and the user would compare it
  /// against system Settings and find it wrong.
  int? get totalBytes {
    if (!hasDetailedSize) {
      return null;
    }
    return appBytes! + dataBytes! + (cacheBytes ?? 0);
  }

  /// The best size figure available: the full footprint, else the APK.
  ///
  /// Used for sorting, so a device without Usage Access still gets a sensible
  /// biggest-first ordering rather than an arbitrary one.
  int get bestKnownBytes => totalBytes ?? apkBytes;

  /// Parses one platform row, returning null when unusable.
  static InstalledApp? fromPlatformMap(Map<Object?, Object?> map) {
    final String packageName = _readString(map['packageName']) ?? '';
    if (packageName.isEmpty) {
      return null;
    }

    // Fall back to the package name: an app with no readable label is still
    // worth listing, and hiding it would silently shrink the list.
    final String name = _readString(map['name']) ?? packageName;

    return InstalledApp(
      packageName: packageName,
      name: name,
      apkBytes: _readNonNegativeInt(map['apkBytes']) ?? 0,
      appBytes: _readNonNegativeInt(map['appBytes']),
      dataBytes: _readNonNegativeInt(map['dataBytes']),
      cacheBytes: _readNonNegativeInt(map['cacheBytes']),
      isSystemApp: map['isSystemApp'] == true,
      // Absent means openable, matching the platform default.
      canOpen: map['canOpen'] != false,
      versionName: _readString(map['versionName']),
      versionCode: _readNonNegativeInt(map['versionCode']),
      installedAt: _readDate(map['installedAtMillis']),
      updatedAt: _readDate(map['updatedAtMillis']),
      icon: _readBytes(map['icon']),
    );
  }

  static String? _readString(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static int? _readNonNegativeInt(Object? value) {
    if (value is int) {
      return value < 0 ? null : value;
    }
    if (value is num) {
      final int parsed = value.toInt();
      return parsed < 0 ? null : parsed;
    }
    return null;
  }

  static DateTime? _readDate(Object? value) {
    final int? millis = _readNonNegativeInt(value);
    if (millis == null || millis <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static Uint8List? _readBytes(Object? value) {
    if (value is Uint8List && value.isNotEmpty) {
      return value;
    }
    if (value is List<int> && value.isNotEmpty) {
      return Uint8List.fromList(value);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstalledApp && other.packageName == packageName);

  @override
  int get hashCode => packageName.hashCode;

  @override
  String toString() => 'InstalledApp($packageName, $apkBytes bytes)';
}
