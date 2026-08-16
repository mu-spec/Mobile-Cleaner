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

  final MethodChannel _channel;

  /// Hashes are stable for a URI within a session, so never recompute one.
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

    try {
      final Map<Object?, Object?>? payload = await _channel
          .invokeMapMethod<Object?, Object?>('hashFiles', <String, Object>{
            'uris': missing,
          });
      results.addAll(parseHashes(payload));
      _cache.addAll(results);
    } on PlatformException {
      // Hashing failed wholesale; report what is known rather than throwing.
      return results;
    } on MissingPluginException {
      return results;
    }

    return results;
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
