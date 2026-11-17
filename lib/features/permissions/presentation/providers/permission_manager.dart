import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_storage_cleaner/features/files/data/storage_access_repository.dart';
import 'package:phone_storage_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';

final permissionManagerProvider =
    NotifierProvider<PermissionManager, AsyncValue<PermissionSnapshot>>(
      PermissionManager.new,
    );

/// Session UI state, never proof of access: entry checks always refresh Android.
/// Runtime dialogs and folder pickers are user initiated and single-flight.
class PermissionManager extends Notifier<AsyncValue<PermissionSnapshot>>
    with WidgetsBindingObserver {
  Future<PermissionSnapshot>? _reading;
  Future<PermissionSnapshot>? _requesting;
  bool _disposed = false;

  @override
  AsyncValue<PermissionSnapshot> build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
    });
    return const AsyncValue<PermissionSnapshot>.loading();
  }

  Future<PermissionSnapshot> refresh() {
    return _requesting ?? _readOnce();
  }

  Future<PermissionSnapshot> _readOnce() {
    return _reading ??= _load().whenComplete(() => _reading = null);
  }

  Future<PermissionSnapshot> _load() async {
    try {
      final PermissionSnapshot runtime = await ref
          .read(permissionGatewayProvider)
          .readPermissions();
      final List<GrantedFolder> folders = await ref
          .read(storageAccessRepositoryProvider)
          .grantedFolders();
      final PermissionSnapshot snapshot = PermissionSnapshot(
        sdkInt: runtime.sdkInt,
        statuses: runtime.statuses,
        folderUris: folders.map((GrantedFolder folder) => folder.uri).toSet(),
      );
      if (!_disposed) {
        state = AsyncValue<PermissionSnapshot>.data(snapshot);
      }
      return snapshot;
    } catch (error, stackTrace) {
      if (!_disposed) {
        state = AsyncValue<PermissionSnapshot>.error(error, stackTrace);
      }
      rethrow;
    }
  }

  Future<PermissionSnapshot> request(PermissionFeature feature) {
    return _requesting ??= _request(feature)
        .whenComplete(() => _requesting = null);
  }

  Future<PermissionSnapshot> _request(PermissionFeature feature) async {
    if (_reading != null) {
      await _reading;
    }
    final PermissionSnapshot current = await _load();
    if (current.allowsFeature(feature)) {
      return current;
    }
    final Set<PermissionKind> requestable = <PermissionKind>{
      for (final PermissionKind kind in current.missingFor(feature))
        if (current.statusOf(kind) == AppPermissionStatus.denied) kind,
    };
    if (requestable.isEmpty || _disposed) {
      return current;
    }
    await ref.read(permissionGatewayProvider).requestPermissions(requestable);
    // Re-read the OS, rather than trusting a local flag or dialog return value.
    return _load();
  }

  Future<PermissionSnapshot> requestFolderAccess() {
    return _requesting ??= _chooseFolder().whenComplete(
      () => _requesting = null,
    );
  }

  Future<PermissionSnapshot> _chooseFolder() async {
    if (_reading != null) {
      await _reading;
    }
    await ref
        .read(storageAccessRepositoryProvider)
        .requestFolderAccess(initialDir: 'Documents');
    return _load();
  }

  Future<bool> openSettings() async {
    try {
      return await ref.read(permissionGatewayProvider).openSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed) {
      unawaited(_refreshOnResume());
    }
  }

  Future<void> _refreshOnResume() async {
    try {
      await refresh();
    } catch (_) {
      // State exposes the error. A lifecycle callback must not crash the app.
    }
  }
}
