import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_summary.dart';
import 'package:mobile_cleaner/features/files/domain/photo_cleanup_summary.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_summary.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/large_photos_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/photo_duplicates_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/screenshot_provider.dart';

/// The Photos tab dashboard.
///
/// Composed from the three existing photo tool providers rather than running
/// its own scan, so a figure shown here is exactly what the tool will show
/// when opened, and opening a tool reuses the cached result instead of
/// scanning the device again.
///
/// The three scans are started together and awaited afterwards, so the wait is
/// the slowest one rather than the sum of the three.
final FutureProvider<PhotoCleanupSummary> photoCleanupProvider =
    FutureProvider<PhotoCleanupSummary>((ref) async {
      final Future<DuplicateScanResult> duplicates = ref.watch(
        photoDuplicatesProvider.future,
      );
      final Future<ScreenshotSummary> screenshots = ref.watch(
        screenshotSummaryProvider(ScreenshotGroup.defaultGroup).future,
      );
      final Future<LargePhotoSummary> largePhotos = ref.watch(
        largePhotoSummaryProvider(LargePhotoFilter.defaultFilter).future,
      );

      return PhotoCleanupSummary.from(
        duplicates: await duplicates,
        screenshots: await screenshots,
        largePhotos: await largePhotos,
      );
    });

/// Invalidates every scan the Photos tab depends on, forcing a fresh look.
///
/// Takes a [WidgetRef] because it is called from the screen. Invalidating the
/// three underlying scans is enough: `photoCleanupProvider` watches their
/// summaries and rebuilds itself.
void refreshPhotoCleanup(WidgetRef ref) {
  ref.invalidate(photoDuplicateScanProvider);
  ref.invalidate(screenshotScanProvider);
  ref.invalidate(largePhotoScanProvider);
}
