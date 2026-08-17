import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Computes perceptual hashes so visually similar photos can be grouped.
///
/// Runs entirely on-device. Implementations must never throw, and must simply
/// omit any image they cannot decode: an image whose appearance is unknown
/// must not be presented as similar to anything.
abstract interface class PerceptualHashRepository {
  /// Returns a hash per image URI. Undecodable images are absent from the map.
  Future<Map<String, String>> hashImages(List<ScannedFile> files);
}

final Provider<PerceptualHashRepository> perceptualHashRepositoryProvider =
    Provider<PerceptualHashRepository>(
      (ref) => PlatformPerceptualHashRepository(),
    );

class PlatformPerceptualHashRepository implements PerceptualHashRepository {
  PlatformPerceptualHashRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.mobilecleaner.app/perceptual_hash';

  /// Must not exceed `PerceptualHashBridge.MAX_FILES_PER_CALL`, which
  /// silently drops anything beyond its cap.
  static const int maxUrisPerCall = 600;

  /// Decoding is the expensive part, so never decode the same image twice in
  /// a session. Hashes are stable for a URI.
  ///
  /// Bounded so a very large library cannot grow this without limit.
  static const int maxCacheEntries = 5000;

  final Map<String, String> _cache = <String, String>{};

  final MethodChannel _channel;

  @override
  Future<Map<String, String>> hashImages(List<ScannedFile> files) async {
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

    // Chunked so the native cap cannot silently drop images. Sending more
    // than the cap in one call hashed only the first N, so similar photos
    // beyond that were never grouped.
    for (int start = 0; start < missing.length; start += maxUrisPerCall) {
      final int end = (start + maxUrisPerCall) > missing.length
          ? missing.length
          : start + maxUrisPerCall;

      try {
        final Map<Object?, Object?>? payload = await _channel
            .invokeMapMethod<Object?, Object?>('hashImages', <String, Object>{
              'uris': missing.sublist(start, end),
            });
        final Map<String, String> fresh = parseHashes(payload);
        results.addAll(fresh);
        _cache.addAll(fresh);
        _trimCache();
      } on PlatformException {
        // Keep earlier batches rather than losing everything.
        return results;
      } on MissingPluginException {
        // Older build without the native bridge. Similar photos are simply
        // unavailable, which the screen reports as "nothing found".
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
