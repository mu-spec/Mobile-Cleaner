import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Loads thumbnail bytes for media files.
///
/// Implementations must never throw: a missing thumbnail is normal (documents,
/// deleted files, revoked permissions) and always degrades to a category icon.
abstract interface class ThumbnailRepository {
  Future<Uint8List?> load(ScannedFile file, {int size});
}

final Provider<ThumbnailRepository> thumbnailRepositoryProvider =
    Provider<ThumbnailRepository>((ref) => PlatformThumbnailRepository());

class PlatformThumbnailRepository implements ThumbnailRepository {
  PlatformThumbnailRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.mobilecleaner.app/thumbnails';

  /// Cap on cached thumbnails.
  ///
  /// Bounded by *bytes* as well as by count, because 240 entries means very
  /// different things for 44px icons and 128px previews.
  static const int maxCacheEntries = 240;

  /// Roughly 12 MB. A JPEG thumbnail is a few KB, so this is generous for
  /// scrolling while still being a hard ceiling on a low-memory device.
  static const int maxCacheBytes = 12 * 1024 * 1024;

  final MethodChannel _channel;

  /// Insertion-ordered, and re-inserted on every hit so the iteration order is
  /// least-recently-used first. Dart maps preserve insertion order, which
  /// makes a real LRU possible without a dependency.
  final Map<String, Uint8List?> _cache = <String, Uint8List?>{};

  int _cachedBytes = 0;

  /// In-flight requests, so two tiles showing the same file during a fast
  /// scroll issue **one** platform call rather than two.
  final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};

  /// Current cache size, for tests and diagnostics.
  int get cachedEntryCount => _cache.length;

  int get cachedByteCount => _cachedBytes;

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) {
    if (!file.supportsThumbnail) {
      return Future<Uint8List?>.value();
    }

    final String cacheKey = '${file.uri}@$size';

    if (_cache.containsKey(cacheKey)) {
      final Uint8List? cached = _cache.remove(cacheKey);
      // Re-insert to mark as most recently used.
      _cache[cacheKey] = cached;
      return Future<Uint8List?>.value(cached);
    }

    final Future<Uint8List?>? pending = _inFlight[cacheKey];
    if (pending != null) {
      return pending;
    }

    final Future<Uint8List?> request = _fetch(file, size, cacheKey);
    _inFlight[cacheKey] = request;
    return request;
  }

  Future<Uint8List?> _fetch(
    ScannedFile file,
    int size,
    String cacheKey,
  ) async {
    Uint8List? bytes;
    try {
      bytes = await _channel
          .invokeMethod<Uint8List>('getThumbnail', <String, Object>{
            'uri': file.uri,
            'size': size,
            'category': file.category.key,
          });
    } on PlatformException {
      bytes = null;
    } on MissingPluginException {
      bytes = null;
    } finally {
      _inFlight.remove(cacheKey);
    }

    _remember(cacheKey, bytes);
    return bytes;
  }

  void _remember(String key, Uint8List? bytes) {
    _cache[key] = bytes;
    _cachedBytes += bytes?.lengthInBytes ?? 0;

    // Evict least-recently-used until both limits are satisfied. A null entry
    // still occupies a slot — it records "this file has no thumbnail", which
    // is worth remembering so it is not re-requested every rebuild.
    while (_cache.length > maxCacheEntries ||
        (_cachedBytes > maxCacheBytes && _cache.length > 1)) {
      final String oldest = _cache.keys.first;
      final Uint8List? evicted = _cache.remove(oldest);
      _cachedBytes -= evicted?.lengthInBytes ?? 0;
      if (_cachedBytes < 0) {
        _cachedBytes = 0;
      }
    }
  }
}
