import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/features/files/domain/apk_summary.dart';
import 'package:phone_storage_cleaner/features/files/domain/download_age_filter.dart';
import 'package:phone_storage_cleaner/features/files/domain/downloads_summary.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_category.dart';
import 'package:phone_storage_cleaner/features/files/domain/large_file_filter.dart';
import 'package:phone_storage_cleaner/features/files/domain/large_file_summary.dart';
import 'package:phone_storage_cleaner/features/files/domain/smart_scan_result.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/apk_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/downloads_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/large_files_provider.dart';

/// Runs all three checks and combines their findings.
///
/// Composed from the existing tool providers rather than issuing its own
/// scan, so Smart Scan and the individual tools can never disagree, and
/// opening a tool after a scan reuses the cached result instead of rescanning.
///
/// The three underlying scans are awaited together, so the total wait is the
/// slowest one rather than their sum.
final FutureProvider<SmartScanResult> smartScanProvider =
    FutureProvider<SmartScanResult>((ref) async {
      return observeScan(ref, 'clean', () async {
        // Start all three, then await together: the wait is the slowest scan
        // rather than the sum of the three.
        final Future<LargeFileSummary> largeFiles = scanDependency(
          ref,
          'largeFiles',
          ref.watch(
            largeFileSummaryProvider(LargeFileFilter.defaultFilter).future,
          ),
        );
        final Future<DownloadsSummary> oldDownloads = scanDependency(
          ref,
          'downloads',
          ref.watch(
            downloadsSummaryProvider(DownloadAgeFilter.defaultFilter).future,
          ),
        );
        final Future<ApkSummary> apks = scanDependency(
          ref,
          'apks',
          ref.watch(apkSummaryProvider(FileListSort.largest).future),
        );

        return SmartScanResult.from(
          largeFiles: await largeFiles,
          oldDownloads: await oldDownloads,
          apks: await apks,
        );
      }, numeric: false);
    });

/// Invalidates every scan Smart Scan depends on, forcing a fresh look.
///
/// Takes a [WidgetRef] because it is called from the screen. Invalidating the
/// three underlying scans is enough: `smartScanProvider` watches their
/// summaries and rebuilds itself.
void refreshSmartScan(WidgetRef ref) {
  ref.invalidate(largeFileScanProvider);
  ref.invalidate(downloadsScanProvider);
  ref.invalidate(apkScanProvider);
}
