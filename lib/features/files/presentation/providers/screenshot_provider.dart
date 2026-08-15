import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_summary.dart';

/// One scan of the image library for the screenshot cleaner.
///
/// Only images are requested, and no size floor is applied: screenshots are
/// usually small, so filtering by size would hide most of them.
final FutureProvider<FileScanResult> screenshotScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return ref
          .watch(fileScannerRepositoryProvider)
          .scan(
            const FileScanRequest(
              categories: <FileCategory>[FileCategory.images],
              limitPerCategory: 1000,
              sortOrder: FileSortOrder.dateDesc,
            ),
          );
    });

/// Screenshots and their combined size for one age group.
///
/// Every group is a subset of the same scan, so switching groups filters in
/// memory instead of hitting the device again.
final screenshotSummaryProvider =
    FutureProvider.family<ScreenshotSummary, ScreenshotGroup>((
      ref,
      ScreenshotGroup group,
    ) async {
      final FileScanResult result = await ref.watch(
        screenshotScanProvider.future,
      );
      return ScreenshotSummary.from(result.files, group);
    });
