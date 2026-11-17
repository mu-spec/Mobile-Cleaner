import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_category.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_scan_result.dart';
import 'package:phone_storage_cleaner/features/files/domain/large_photo_filter.dart';
import 'package:phone_storage_cleaner/features/files/domain/large_photo_summary.dart';

/// One scan of the image library for the Large Photos tool.
///
/// Only images are requested, with the size floor pushed into the query so the
/// platform never returns the thousands of small pictures a phone holds.
final FutureProvider<FileScanResult> largePhotoScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return observeScan(ref, 'discovery:largePhotos', () async {
        return ref
            .watch(fileScannerRepositoryProvider)
            .scan(
              FileScanRequest(
                categories: const <FileCategory>[FileCategory.images],
                minSizeBytes: LargePhotoFilter.lowestBound,
                limitPerCategory: 500,
              ),
            );
      }, numeric: true);
    });

/// Photos and their combined size for one threshold.
///
/// Every threshold is a subset of the same scan, so switching chips filters in
/// memory instead of hitting the device again.
final largePhotoSummaryProvider =
    FutureProvider.family<LargePhotoSummary, LargePhotoFilter>((
      ref,
      LargePhotoFilter filter,
    ) async {
      return observeScan(ref, 'largePhotos', () async {
        final FileScanResult result = await scanDependency(
          ref,
          'discovery:largePhotos',
          ref.watch(largePhotoScanProvider.future),
        );
        return LargePhotoSummary.from(result.files, filter);
      }, numeric: true);
    });
