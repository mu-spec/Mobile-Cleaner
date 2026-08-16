import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_summary.dart';

/// One scan of the image library for the Large Photos tool.
///
/// Only images are requested, with the size floor pushed into the query so the
/// platform never returns the thousands of small pictures a phone holds.
final FutureProvider<FileScanResult> largePhotoScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return ref
          .watch(fileScannerRepositoryProvider)
          .scan(
            FileScanRequest(
              categories: const <FileCategory>[FileCategory.images],
              minSizeBytes: LargePhotoFilter.lowestBound,
              limitPerCategory: 500,
            ),
          );
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
      final FileScanResult result = await ref.watch(
        largePhotoScanProvider.future,
      );
      return LargePhotoSummary.from(result.files, filter);
    });
