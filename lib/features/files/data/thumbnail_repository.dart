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

  /// Bounded in-memory cache so scrolling back up does not re-decode.
  static const int _maxCacheEntries = 240;

  final MethodChannel _channel;
  final Map<String, Uint8List?> _cache = <String, Uint8List?>{};

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async {
    if (!file.supportsThumbnail) {
      return null;
    }

    final String cacheKey = '${file.uri}@$size';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    Uint8List? bytes;
    try {
      bytes = await _channel.invokeMethod<Uint8List>('getThumbnail', <String, Object>{
        'uri': file.uri,
        'size': size,
        'category': file.category.key,
      });
    } on PlatformException {
      bytes = null;
    } on MissingPluginException {
      bytes = null;
    }

    _remember(cacheKey, bytes);
    return bytes;
  }

  void _remember(String key, Uint8List? bytes) {
    if (_cache.length >= _maxCacheEntries) {
      // Simple FIFO eviction keeps memory bounded without a heavy LRU.
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = bytes;
  }
}
