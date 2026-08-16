import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/video_sort.dart';
import 'package:mobile_cleaner/features/files/domain/video_summary.dart';

/// One scan of the video library.
///
/// No size floor: a short clip can still be worth reviewing, and unlike photos
/// there are rarely thousands of them. The scan is ordered by size so that a
/// truncated result keeps the biggest videos, which are the ones the section
/// exists to surface.
final FutureProvider<FileScanResult> videoScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return ref
          .watch(fileScannerRepositoryProvider)
          .scan(
            const FileScanRequest(
              categories: <FileCategory>[FileCategory.videos],
              limitPerCategory: 500,
            ),
          );
    });

/// Videos in one ordering.
///
/// Every ordering is a re-sort of the same scan, so switching sort filters in
/// memory instead of hitting the device again.
final videoSummaryProvider =
    FutureProvider.family<VideoSummary, VideoSort>((
      ref,
      VideoSort sort,
    ) async {
      final FileScanResult result = await ref.watch(videoScanProvider.future);
      return VideoSummary.from(result.files, sort);
    });
