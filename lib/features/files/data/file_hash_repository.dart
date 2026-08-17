import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Computes content hashes so exact duplicates can be proven.
///
/// Implementations must never throw and must simply omit any file they cannot
/// read: a file whose contents are unknown cannot be shown as a duplicate.
abstract interface class FileHashRepository {
  /// Returns a hash per file URI. Unreadable files are absent from the map.
  Future<Map<String, String>> hashFiles(List<ScannedFile> files);
}

final Provider<FileHashRepository> fileHashRepositoryProvider =
    Provider<FileHashRepository>((ref) => PlatformFileHashRepository());

class PlatformFileHashRepository implements FileHashRepository {
  PlatformFileHashRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.mobilecleaner.app/hash';

  /// Must not exceed `FileHashBridge.MAX_FILES_PER_CALL` on the native side,
  /// which silently drops anything beyond its cap.
  static const int maxUrisPerCall = 400;

  final MethodChannel _channel;

  /// Hashes are stable for a URI within a session, so never recompute one.
  ///
  /// Bounded: on a library with tens of thousands of size-matched candidates
  /// an unbounded map would grow for the life of the process. Hex hashes are
  /// small, so the cap is generous.
  static const int maxCacheEntries = 5000;

  final Map<String, String> _cache = <String, String>{};

  @override
  Future<Map<String, String>> hashFiles(List<ScannedFile> files) async {
    if (files.isEmpty) {
      return const <String, String>{};
    }

    final Map<String, String> results = <String, String>{};
    final List<String> missing = <String>[];

    for (final ScannedFile file in files) {
      final String? cached = _cache[file.uri];
      if (cached != null) {
        results[file.uri] = cached;
      } else {
        missing.add(file.uri);
      }
    }

    if (missing.isEmpty) {
      return results;
    }

    // Sent in chunks that the native side will not truncate.
    //
    // FileHashBridge caps one call at 400 URIs. Sending 900 in a single call
    // silently hashed the first 400 and dropped the rest, so duplicates past
    // that point were never found — a correctness bug that only appears on a
    // large library. Chunking also keeps each channel payload small and lets
    // partial results survive a mid-way failure.
    for (int start = 0; start < missing.length; start += maxUrisPerCall) {
      final int end = (start + maxUrisPerCall) > missing.length
          ? missing.length
          : start + maxUrisPerCall;
      final List<String> batch = missing.sublist(start, end);

      try {
        final Map<Object?, Object?>? payload = await _channel
            .invokeMapMethod<Object?, Object?>('hashFiles', <String, Object>{
              'uris': batch,
            });
        final Map<String, String> fresh = parseHashes(payload);
        results.addAll(fresh);
        _cache.addAll(fresh);
        _trimCache();
      } on PlatformException {
        // Keep what earlier batches produced rather than losing everything.
        return results;
      } on MissingPluginException {
        return results;
      }
    }

    return results;
  }

  /// Drops the oldest entries once the cap is passed.
  void _trimCache() {
    while (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Parses the platform payload, dropping malformed rows.
  ///
  /// Exposed for testing.
  static Map<String, String> parseHashes(Map<Object?, Object?>? payload) {
    if (payload == null) {
      return const <String, String>{};
    }
    final Map<String, String> hashes = <String, String>{};
    payload.forEach((Object? key, Object? value) {
      if (key is String &&
          key.isNotEmpty &&
          value is String &&
          value.isNotEmpty) {
        hashes[key] = value;
      }
    });
    return hashes;
  }
}
