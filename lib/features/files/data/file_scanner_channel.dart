import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';

/// Thin wrapper around the Android MediaStore method channel.
///
/// Kept separate from the repository so tests can fake the transport without
/// touching parsing logic.
abstract interface class FileScannerChannel {
  Future<Map<Object?, Object?>> scan({
    required List<FileCategory> categories,
    required int limitPerCategory,
    required int minSizeBytes,
    required FileSortOrder sortOrder,
  });
}

final Provider<FileScannerChannel> fileScannerChannelProvider =
    Provider<FileScannerChannel>((ref) => MethodChannelFileScanner());

class MethodChannelFileScanner implements FileScannerChannel {
  MethodChannelFileScanner({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.mobilecleaner.app/file_scanner';

  final MethodChannel _channel;

  @override
  Future<Map<Object?, Object?>> scan({
    required List<FileCategory> categories,
    required int limitPerCategory,
    required int minSizeBytes,
    required FileSortOrder sortOrder,
  }) async {
    final Map<Object?, Object?>? result;
    try {
      result = await _channel
          .invokeMapMethod<Object?, Object?>('scanFiles', <String, Object>{
            'categories': categories
                .map((FileCategory category) => category.key)
                .toList(growable: false),
            'limitPerCategory': limitPerCategory,
            'minSizeBytes': minSizeBytes,
            'sortOrder': sortOrder.key,
          });
    } on MissingPluginException {
      // The scanner is the app's core capability, so this is surfaced rather
      // than silently returning an empty library that looks like a clean
      // device.
      throw PlatformException(
        code: 'SCAN_UNAVAILABLE',
        message: 'File scanning is not available on this device.',
      );
    }

    if (result == null) {
      throw PlatformException(
        code: 'SCAN_UNAVAILABLE',
        message: 'The file scanner returned no data.',
      );
    }
    return result;
  }
}
