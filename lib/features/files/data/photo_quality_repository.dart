import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/photo_quality.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Measures sharpness and resolution so a best shot can be suggested.
///
/// Runs entirely on-device. Implementations must never throw, and must omit
/// any photo they cannot measure: an unmeasured photo gets no recommendation,
/// which is safe, whereas a fabricated measurement could recommend the wrong
/// shot.
abstract interface class PhotoQualityRepository {
  /// Returns a measurement per photo URI. Unmeasurable photos are absent.
  Future<Map<String, PhotoQuality>> analyzePhotos(List<ScannedFile> files);
}

final Provider<PhotoQualityRepository> photoQualityRepositoryProvider =
    Provider<PhotoQualityRepository>(
      (ref) => PlatformPhotoQualityRepository(),
    );

class PlatformPhotoQualityRepository implements PhotoQualityRepository {
  PlatformPhotoQualityRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.mobilecleaner.app/photo_quality';

  /// Decoding is the expensive part, so never measure the same photo twice in
  /// a session. Measurements are stable for a URI.
  final Map<String, PhotoQuality> _cache = <String, PhotoQuality>{};

  final MethodChannel _channel;

  @override
  Future<Map<String, PhotoQuality>> analyzePhotos(
    List<ScannedFile> files,
  ) async {
    if (files.isEmpty) {
      return const <String, PhotoQuality>{};
    }

    final Map<String, PhotoQuality> results = <String, PhotoQuality>{};
    final List<String> missing = <String>[];

    for (final ScannedFile file in files) {
      final PhotoQuality? cached = _cache[file.uri];
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
          .invokeMapMethod<Object?, Object?>('analyzePhotos', <String, Object>{
            'uris': missing,
          });
      final Map<String, PhotoQuality> fresh = parseQualities(payload);
      results.addAll(fresh);
      _cache.addAll(fresh);
    } on PlatformException {
      // Measurement failed wholesale; report what is known rather than throw.
      return results;
    } on MissingPluginException {
      // Older build without the native bridge. No recommendations are shown,
      // which the screen handles as "too close to call".
      return results;
    }

    return results;
  }

  /// Parses the platform payload, dropping malformed rows.
  ///
  /// Exposed for testing.
  static Map<String, PhotoQuality> parseQualities(
    Map<Object?, Object?>? payload,
  ) {
    if (payload == null) {
      return const <String, PhotoQuality>{};
    }
    final Map<String, PhotoQuality> qualities = <String, PhotoQuality>{};
    payload.forEach((Object? key, Object? value) {
      if (key is! String || key.isEmpty || value is! Map<Object?, Object?>) {
        return;
      }
      final PhotoQuality? quality = PhotoQuality.fromPlatformMap(value);
      if (quality != null) {
        qualities[key] = quality;
      }
    });
    return qualities;
  }
}
