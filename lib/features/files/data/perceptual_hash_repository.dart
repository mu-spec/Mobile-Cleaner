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

  /// Decoding is the expensive part, so never decode the same image twice in
  /// a session. Hashes are stable for a URI.
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

    try {
      final Map<Object?, Object?>? payload = await _channel
          .invokeMapMethod<Object?, Object?>('hashImages', <String, Object>{
            'uris': missing,
          });
      final Map<String, String> fresh = parseHashes(payload);
      results.addAll(fresh);
      _cache.addAll(fresh);
    } on PlatformException {
      // Hashing failed wholesale; report what is known rather than throwing.
      return results;
    } on MissingPluginException {
      // Older build without the native bridge. Similar photos are simply
      // unavailable, which the screen reports as "nothing found".
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
