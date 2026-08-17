import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_summary.dart';
import 'package:mobile_cleaner/features/files/domain/video_sort.dart';
import 'package:mobile_cleaner/features/files/domain/video_summary.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/duplicates_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/screenshot_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/videos_provider.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation_engine.dart';

/// Gathers the figures the rules read.
///
/// Composed from the existing tool providers rather than scanning again, so a
/// recommendation always matches what the tool will show when opened, and
/// opening that tool reuses the cached scan.
///
/// The three scans start together and are awaited afterwards, so the wait is
/// the slowest one rather than the sum.
final FutureProvider<RecommendationInputs> recommendationInputsProvider =
    FutureProvider<RecommendationInputs>((ref) async {
      final Future<ScreenshotSummary> screenshots = ref.watch(
        // The rule is specifically about screenshots older than 90 days, so
        // ask for exactly that bucket rather than filtering afterwards.
        screenshotSummaryProvider(ScreenshotGroup.days90).future,
      );
      final Future<DuplicateScanResult> duplicates = ref.watch(
        duplicatesProvider.future,
      );
      final Future<VideoSummary> videos = ref.watch(
        videoSummaryProvider(VideoSort.largest).future,
      );

      final ScreenshotSummary staleShots = await screenshots;
      final DuplicateScanResult duplicateResult = await duplicates;
      final VideoSummary videoResult = await videos;

      final List<ScannedFile> largeVideos = <ScannedFile>[
        for (final ScannedFile video in videoResult.videos)
          if (video.sizeBytes >= RecommendationEngine.largeVideoBytes) video,
      ];

      return RecommendationInputs(
        oldScreenshotCount: staleShots.fileCount,
        oldScreenshotBytes: staleShots.totalBytes,
        duplicateReclaimableBytes: duplicateResult.reclaimableBytes,
        duplicateGroupCount: duplicateResult.groupCount,
        largestVideo: videoResult.largestVideo,
        largeVideoCount: largeVideos.length,
        largeVideoBytes: largeVideos.fold<int>(
          0,
          (int sum, ScannedFile video) => sum + video.sizeBytes,
        ),
      );
    });

/// The advice Home shows, strongest first.
///
/// Rule evaluation is pure arithmetic, so it is derived here rather than
/// recomputed by the widget on every rebuild.
final FutureProvider<List<Recommendation>> recommendationsProvider =
    FutureProvider<List<Recommendation>>((ref) async {
      final RecommendationInputs inputs = await ref.watch(
        recommendationInputsProvider.future,
      );
      return RecommendationEngine.evaluate(inputs);
    });

/// Re-runs every scan the recommendations depend on.
///
/// Takes a [WidgetRef] because it is called from Home. Invalidating the
/// underlying scans is enough: the inputs and rules rebuild from them.
void refreshRecommendations(WidgetRef ref) {
  ref.invalidate(screenshotScanProvider);
  ref.invalidate(duplicateScanProvider);
  ref.invalidate(videoScanProvider);
}
