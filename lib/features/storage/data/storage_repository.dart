import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';

abstract interface class StorageRepository {
  Future<StorageInfo> getStorageInfo();
}

final Provider<StorageRepository> storageRepositoryProvider =
    Provider<StorageRepository>((ref) => PlatformStorageRepository());

class PlatformStorageRepository implements StorageRepository {
  static const MethodChannel _channel = MethodChannel(
    'com.mobilecleaner.app/storage',
  );

  @override
  Future<StorageInfo> getStorageInfo() async {
    final Map<Object?, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<Object?, Object?>(
        'getStorageInfo',
      );
    } on MissingPluginException {
      // An older build without the native side. Reported as unavailable
      // rather than crashing the Home screen on launch.
      throw PlatformException(
        code: 'STORAGE_UNAVAILABLE',
        message: 'Storage information is not available on this device.',
      );
    }
    if (result == null) {
      throw PlatformException(
        code: 'STORAGE_UNAVAILABLE',
        message: 'Storage information was not returned by Android.',
      );
    }

    final int? totalBytes = _readInt(result['totalBytes']);
    final int? freeBytes = _readInt(result['freeBytes']);
    if (totalBytes == null || freeBytes == null || totalBytes <= 0) {
      throw PlatformException(
        code: 'INVALID_STORAGE_DATA',
        message: 'Android returned invalid storage information.',
      );
    }

    return StorageInfo(
      totalBytes: totalBytes,
      freeBytes: freeBytes.clamp(0, totalBytes).toInt(),
    );
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}
