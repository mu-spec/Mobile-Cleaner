import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';

abstract interface class AppPermissionGateway {
  Future<PermissionSnapshot> readPermissions();
  Future<void> requestPermissions(Set<PermissionKind> kinds);
  Future<bool> openSettings();
}

final Provider<AppPermissionGateway> permissionGatewayProvider =
    Provider<AppPermissionGateway>((ref) => PermissionGateway());

/// The only runtime-permission transport. It never requests all-files access.
class PermissionGateway implements AppPermissionGateway {
  PermissionGateway({bool? isAndroid, Future<int> Function()? androidSdk})
    : _isAndroid = isAndroid ?? Platform.isAndroid,
      _androidSdk = androidSdk ?? _readSdk;

  final bool _isAndroid;
  final Future<int> Function() _androidSdk;

  static Future<int> _readSdk() async =>
      (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  static Permission _platformPermission(PermissionKind kind) => switch (kind) {
    PermissionKind.storage => Permission.storage,
    PermissionKind.photos => Permission.photos,
    PermissionKind.videos => Permission.videos,
    PermissionKind.audio => Permission.audio,
  };

  @override
  Future<PermissionSnapshot> readPermissions() async {
    if (!_isAndroid) {
      // Non-Android hosts have no Android runtime dialog. SAF remains separate.
      return PermissionSnapshot(
        sdkInt: 0,
        statuses: <PermissionKind, AppPermissionStatus>{
          for (final PermissionKind kind in PermissionKind.values)
            kind: AppPermissionStatus.granted,
        },
      );
    }
    final int sdk = await _androidSdk();
    final Iterable<PermissionKind> applicable = sdk >= 33
        ? <PermissionKind>[
            PermissionKind.photos,
            PermissionKind.videos,
            PermissionKind.audio,
          ]
        : <PermissionKind>[PermissionKind.storage];
    final Map<PermissionKind, AppPermissionStatus> statuses =
        <PermissionKind, AppPermissionStatus>{};
    for (final PermissionKind kind in applicable) {
      statuses[kind] = _mapStatus(await _platformPermission(kind).status);
    }
    return PermissionSnapshot(sdkInt: sdk, statuses: statuses);
  }

  @override
  Future<void> requestPermissions(Set<PermissionKind> kinds) async {
    if (!_isAndroid || kinds.isEmpty) {
      return;
    }
    final int sdk = await _androidSdk();
    final List<Permission> permissions = <Permission>[
      for (final PermissionKind kind in kinds)
        if ((sdk >= 33 && kind != PermissionKind.storage) ||
            (sdk < 33 && kind == PermissionKind.storage))
          _platformPermission(kind),
    ];
    if (permissions.isNotEmpty) {
      await permissions.request();
    }
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  static AppPermissionStatus _mapStatus(PermissionStatus status) =>
      switch (status) {
        PermissionStatus.granted => AppPermissionStatus.granted,
        PermissionStatus.limited => AppPermissionStatus.limited,
        PermissionStatus.permanentlyDenied =>
          AppPermissionStatus.permanentlyDenied,
        PermissionStatus.restricted => AppPermissionStatus.restricted,
        PermissionStatus.denied ||
        PermissionStatus.provisional => AppPermissionStatus.denied,
      };
}
