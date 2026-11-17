import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_scan_result.dart';
import 'package:phone_storage_cleaner/features/files/domain/large_file_filter.dart';
import 'package:phone_storage_cleaner/features/files/domain/large_file_summary.dart';

/// One scan for the Large Files tool, at the lowest supported threshold.
///
/// Every filter chip is a subset of this result, so switching chips filters
/// in memory instead of hitting the device again.
final FutureProvider<FileScanResult> largeFileScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return observeScan(ref, 'discovery:largeFiles', () async {
        return ref
            .watch(fileScannerRepositoryProvider)
            .scan(
              FileScanRequest(
                minSizeBytes: LargeFileFilter.lowestBound,
                limitPerCategory: 300,
              ),
            );
      }, numeric: false);
    });

/// Files and total size for one threshold.
final largeFileSummaryProvider =
    FutureProvider.family<LargeFileSummary, LargeFileFilter>((
      ref,
      LargeFileFilter filter,
    ) async {
      return observeScan(ref, 'largeFiles', () async {
        final FileScanResult result = await scanDependency(
          ref,
          'discovery:largeFiles',
          ref.watch(largeFileScanProvider.future),
        );
        return LargeFileSummary.from(result.files, filter);
      }, numeric: false);
    });
