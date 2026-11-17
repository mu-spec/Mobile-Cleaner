import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/download_age_filter.dart';
import 'package:phone_storage_cleaner/features/files/domain/downloads_summary.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_category.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_scan_result.dart';

/// One scan of the Downloads folder for the cleaner.
///
/// Only the Downloads category is requested, and no size floor is applied:
/// age, not size, is what this tool filters on.
final FutureProvider<FileScanResult> downloadsScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return observeScan(ref, 'discovery:downloads', () async {
        return ref
            .watch(fileScannerRepositoryProvider)
            .scan(
              const FileScanRequest(
                categories: <FileCategory>[FileCategory.downloads],
                limitPerCategory: 500,
                sortOrder: FileSortOrder.dateDesc,
              ),
            );
      }, numeric: false);
    });

/// Downloads and total size for one age threshold.
///
/// Every threshold is a subset of the same scan, so switching chips filters
/// in memory instead of hitting the device again.
final downloadsSummaryProvider =
    FutureProvider.family<DownloadsSummary, DownloadAgeFilter>((
      ref,
      DownloadAgeFilter filter,
    ) async {
      return observeScan(ref, 'downloads', () async {
        final FileScanResult result = await scanDependency(
          ref,
          'discovery:downloads',
          ref.watch(downloadsScanProvider.future),
        );
        return DownloadsSummary.from(
          result.byCategory(FileCategory.downloads),
          filter,
        );
      }, numeric: false);
    });
