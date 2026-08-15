import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:permission_handler/permission_handler.dart';

abstract interface class AppPermissionGateway {
  Future<AppPermissionStatus> checkMediaAndStorage();

  Future<AppPermissionStatus> requestMediaAndStorage();

  Future<bool> openSettings();
}

final Provider<AppPermissionGateway> permissionGatewayProvider =
    Provider<AppPermissionGateway>((ref) => PermissionGateway());

class PermissionGateway implements AppPermissionGateway {
  @override
  Future<AppPermissionStatus> checkMediaAndStorage() async {
    if (!Platform.isAndroid) {
      return AppPermissionStatus.granted;
    }
    final List<Permission> permissions = await _requiredPermissions();
    final List<PermissionStatus> statuses = await Future.wait(
      permissions.map((Permission permission) => permission.status),
    );
    return _combine(statuses);
  }

  @override
  Future<AppPermissionStatus> requestMediaAndStorage() async {
    if (!Platform.isAndroid) {
      return AppPermissionStatus.granted;
    }
    final List<Permission> permissions = await _requiredPermissions();
    final Map<Permission, PermissionStatus> statuses =
        await permissions.request();
    return _combine(statuses.values);
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  Future<List<Permission>> _requiredPermissions() async {
    final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
    if (info.version.sdkInt >= 33) {
      return <Permission>[
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ];
    }
    return <Permission>[Permission.storage];
  }

  AppPermissionStatus _combine(Iterable<PermissionStatus> statuses) {
    if (statuses.any((PermissionStatus status) => status.isPermanentlyDenied)) {
      return AppPermissionStatus.permanentlyDenied;
    }
    if (statuses.every(
      (PermissionStatus status) => status.isGranted || status.isLimited,
    )) {
      return AppPermissionStatus.granted;
    }
    return AppPermissionStatus.denied;
  }
}
