import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_summary.dart';

/// One scan for the Large Files tool, at the lowest supported threshold.
///
/// Every filter chip is a subset of this result, so switching chips filters
/// in memory instead of hitting the device again.
final FutureProvider<FileScanResult> largeFileScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return ref
          .watch(fileScannerRepositoryProvider)
          .scan(
            FileScanRequest(
              minSizeBytes: LargeFileFilter.lowestBound,
              limitPerCategory: 300,
            ),
          );
    });

/// Files and total size for one threshold.
final largeFileSummaryProvider =
    FutureProvider.family<LargeFileSummary, LargeFileFilter>((
      ref,
      LargeFileFilter filter,
    ) async {
      final FileScanResult result = await ref.watch(
        largeFileScanProvider.future,
      );
      return LargeFileSummary.from(result.files, filter);
    });
