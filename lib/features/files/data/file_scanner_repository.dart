import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_channel.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Options controlling one discovery pass.
class FileScanRequest {
  const FileScanRequest({
    this.categories = FileCategory.scannable,
    this.limitPerCategory = 500,
    this.minSizeBytes = 0,
    this.sortOrder = FileSortOrder.sizeDesc,
  });

  final List<FileCategory> categories;

  /// Safety valve: MediaStore can hold tens of thousands of rows.
  final int limitPerCategory;

  /// Skip files smaller than this, useful for the Large Files view.
  final int minSizeBytes;

  final FileSortOrder sortOrder;
}

/// Read-only discovery of user-visible files. Phase 6 never deletes anything.
abstract interface class FileScannerRepository {
  Future<FileScanResult> scan([FileScanRequest request]);
}

final Provider<FileScannerRepository> fileScannerRepositoryProvider =
    Provider<FileScannerRepository>((ref) {
      return MediaStoreFileScannerRepository(
        ref.watch(fileScannerChannelProvider),
      );
    });

class MediaStoreFileScannerRepository implements FileScannerRepository {
  const MediaStoreFileScannerRepository(this._channel);

  final FileScannerChannel _channel;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    final Map<Object?, Object?> payload = await _channel.scan(
      categories: request.categories,
      limitPerCategory: request.limitPerCategory,
      minSizeBytes: request.minSizeBytes,
      sortOrder: request.sortOrder,
    );

    final List<ScannedFile> files = _parseFiles(payload['files']);

    return FileScanResult.fromFiles(
      files,
      durationMillis: _readInt(payload['durationMillis']) ?? 0,
      truncated: payload['truncated'] == true,
      needsFolderAccess: payload['needsFolderAccess'] == true,
      categories: request.categories,
    );
  }

  List<ScannedFile> _parseFiles(Object? raw) {
    if (raw is! List<Object?>) {
      return const <ScannedFile>[];
    }

    final List<ScannedFile> files = <ScannedFile>[];
    final Set<String> seen = <String>{};
    for (final Object? row in raw) {
      if (row is! Map<Object?, Object?>) {
        continue;
      }
      final ScannedFile? file = ScannedFile.fromPlatformMap(row);
      // A file can legitimately appear in both its media table and Downloads;
      // de-duplicate so totals are not double counted.
      if (file != null && seen.add('${file.category.key}:${file.id}')) {
        files.add(file);
      }
    }
    return files;
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
