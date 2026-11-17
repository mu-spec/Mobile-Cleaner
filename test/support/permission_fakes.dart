import 'dart:async';

import 'package:phone_storage_cleaner/features/files/data/storage_access_repository.dart';
import 'package:phone_storage_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';

class FakePermissionGateway implements AppPermissionGateway {
  FakePermissionGateway({
    this.sdkInt = 34,
    AppPermissionStatus initial = AppPermissionStatus.denied,
  }) : statuses = <PermissionKind, AppPermissionStatus>{
         for (final PermissionKind kind in PermissionKind.values) kind: initial,
       };

  final int sdkInt;
  final Map<PermissionKind, AppPermissionStatus> statuses;
  int reads = 0;
  int settingsOpened = 0;
  final List<Set<PermissionKind>> requests = <Set<PermissionKind>>[];
  AppPermissionStatus response = AppPermissionStatus.granted;
  Completer<void>? requestGate;
  bool failReads = false;

  @override
  Future<PermissionSnapshot> readPermissions() async {
    reads++;
    if (failReads) {
      throw StateError('Android status unavailable');
    }
    return PermissionSnapshot(sdkInt: sdkInt, statuses: statuses);
  }

  @override
  Future<void> requestPermissions(Set<PermissionKind> kinds) async {
    requests.add(Set<PermissionKind>.of(kinds));
    if (requestGate != null) {
      await requestGate!.future;
    }
    for (final PermissionKind kind in kinds) {
      statuses[kind] = response;
    }
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

class FakeFolderAccess implements StorageAccessRepository {
  List<GrantedFolder> folders = <GrantedFolder>[];
  int reads = 0;
  int pickerRequests = 0;

  @override
  Future<List<GrantedFolder>> grantedFolders() async {
    reads++;
    return List<GrantedFolder>.of(folders);
  }

  @override
  Future<bool> isAccessRequired() async => true;

  @override
  Future<List<GrantedFolder>> requestFolderAccess({String? initialDir}) async {
    pickerRequests++;
    folders = <GrantedFolder>[
      const GrantedFolder(
        uri: 'content://documents/tree/primary%3ADocuments',
        label: 'Documents',
      ),
    ];
    return folders;
  }

  @override
  Future<List<GrantedFolder>> releaseFolder(String uri) async {
    folders.removeWhere((GrantedFolder folder) => folder.uri == uri);
    return folders;
  }
}
