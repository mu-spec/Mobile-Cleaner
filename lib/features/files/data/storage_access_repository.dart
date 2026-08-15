import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A folder the user granted access to through the Storage Access Framework.
class GrantedFolder {
  const GrantedFolder({required this.uri, required this.label});

  final String uri;
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is GrantedFolder && other.uri == uri);

  @override
  int get hashCode => uri.hashCode;
}

/// User-granted folder access.
///
/// Scoped storage hides non-media files that other apps created, so documents,
/// downloads, and APKs need an explicit SAF grant to be listed. This never
/// requests MANAGE_EXTERNAL_STORAGE, which Google Play restricts to a narrow
/// set of app categories.
abstract interface class StorageAccessRepository {
  /// Folders the user has already granted, newest first.
  Future<List<GrantedFolder>> grantedFolders();

  /// Opens the system folder picker. Returns the grants after the user
  /// chooses, or the unchanged list if they cancel.
  Future<List<GrantedFolder>> requestFolderAccess({String? initialDir});

  /// Drops a previously granted folder.
  Future<List<GrantedFolder>> releaseFolder(String uri);

  /// True on platforms where scoped storage hides non-media files.
  Future<bool> isAccessRequired();
}

final Provider<StorageAccessRepository> storageAccessRepositoryProvider =
    Provider<StorageAccessRepository>((ref) => PlatformStorageAccessRepository());

class PlatformStorageAccessRepository implements StorageAccessRepository {
  PlatformStorageAccessRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.mobilecleaner.app/saf';

  final MethodChannel _channel;

  @override
  Future<List<GrantedFolder>> grantedFolders() =>
      _invokeForFolders('getGrantedTrees');

  @override
  Future<List<GrantedFolder>> requestFolderAccess({String? initialDir}) =>
      _invokeForFolders('requestTreeAccess', <String, Object?>{
        'initialDir': initialDir,
      });

  @override
  Future<List<GrantedFolder>> releaseFolder(String uri) =>
      _invokeForFolders('releaseTree', <String, Object?>{'uri': uri});

  @override
  Future<bool> isAccessRequired() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessRequired') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<List<GrantedFolder>> _invokeForFolders(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final List<Object?>? raw = await _channel.invokeListMethod<Object?>(
        method,
        arguments,
      );
      return parseFolders(raw);
    } on PlatformException {
      // A denied or failed grant is a normal outcome, not a crash.
      return const <GrantedFolder>[];
    } on MissingPluginException {
      return const <GrantedFolder>[];
    }
  }

  /// Parses the platform payload. Exposed for testing.
  static List<GrantedFolder> parseFolders(List<Object?>? raw) {
    if (raw == null) {
      return const <GrantedFolder>[];
    }
    final List<GrantedFolder> folders = <GrantedFolder>[];
    for (final Object? entry in raw) {
      if (entry is! Map<Object?, Object?>) {
        continue;
      }
      final Object? uri = entry['uri'];
      if (uri is! String || uri.isEmpty) {
        continue;
      }
      final Object? label = entry['label'];
      folders.add(
        GrantedFolder(
          uri: uri,
          label: label is String && label.isNotEmpty ? label : 'Folder',
        ),
      );
    }
    return folders;
  }
}
