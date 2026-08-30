import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_summary.dart';
import 'package:mobile_cleaner/features/files/domain/smart_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/video_sort.dart';
import 'package:mobile_cleaner/features/files/domain/video_summary.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/apk_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/downloads_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/duplicates_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/large_files_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/screenshot_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/smart_scan_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/videos_provider.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation_engine.dart';

/// Gathers results from the existing real analyzers after a user starts Smart
/// Scan. Nothing on Home watches this provider directly, so it cannot start a
/// background scan merely because the Home screen was built.
final FutureProvider<RecommendationInputs> recommendationInputsProvider =
    FutureProvider<RecommendationInputs>((ref) async {
      final Future<SmartScanResult> smartScan = ref.watch(
        smartScanProvider.future,
      );
      final Future<ScreenshotSummary> screenshots = ref.watch(
        screenshotSummaryProvider(ScreenshotGroup.days90).future,
      );
      final Future<DuplicateScanResult> duplicates = ref.watch(
        duplicatesProvider.future,
      );
      final Future<VideoSummary> videos = ref.watch(
        videoSummaryProvider(VideoSort.largest).future,
      );

      final SmartScanResult fileResult = await smartScan;
      final ScreenshotSummary staleShots = await screenshots;
      final DuplicateScanResult duplicateResult = await duplicates;
      final VideoSummary videoResult = await videos;

      final List<ScannedFile> largeVideos = <ScannedFile>[
        for (final ScannedFile video in videoResult.videos)
          if (video.sizeBytes >= RecommendationEngine.largeVideoBytes) video,
      ];
      final SmartScanGroup largeFiles = fileResult.groupFor(
        SmartScanCategory.largeFiles,
      );
      final SmartScanGroup oldDownloads = fileResult.groupFor(
        SmartScanCategory.oldDownloads,
      );
      final SmartScanGroup apks = fileResult.groupFor(
        SmartScanCategory.apkInstallers,
      );

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
        largeFileCount: largeFiles.fileCount,
        largeFileBytes: largeFiles.totalBytes,
        oldDownloadCount: oldDownloads.fileCount,
        oldDownloadBytes: oldDownloads.totalBytes,
        apkInstallerCount: apks.fileCount,
        apkInstallerBytes: apks.totalBytes,
      );
    });

/// The current app-session recommendation state for Home.
///
/// It begins empty on every process/provider-container start. A real scan is
/// only launched by [RecommendationsController.scan], which is called from
/// the explicit Smart Scan progress flow. Results are never persisted because
/// file-system findings cannot be guaranteed valid across app restarts.
final NotifierProvider<
  RecommendationsController,
  AsyncValue<List<Recommendation>>
>
recommendationsProvider =
    NotifierProvider<
      RecommendationsController,
      AsyncValue<List<Recommendation>>
    >(RecommendationsController.new);

class RecommendationsController
    extends Notifier<AsyncValue<List<Recommendation>>> {
  @override
  AsyncValue<List<Recommendation>> build() =>
      const AsyncValue<List<Recommendation>>.data(<Recommendation>[]);

  /// Runs every existing analyzer used by Home recommendations and publishes
  /// advice only after all of them finish successfully.
  Future<List<Recommendation>> scan() async {
    state = const AsyncValue<List<Recommendation>>.loading();
    _invalidateScanInputs();

    try {
      final RecommendationInputs inputs = await ref.read(
        recommendationInputsProvider.future,
      );
      final List<Recommendation> found = RecommendationEngine.evaluate(inputs);
      state = AsyncValue<List<Recommendation>>.data(found);
      return found;
    } catch (error, stackTrace) {
      state = AsyncValue<List<Recommendation>>.error(error, stackTrace);
      rethrow;
    }
  }

  /// Clears potentially stale advice without starting another scan.
  void invalidateAfterCleanup() {
    state = const AsyncValue<List<Recommendation>>.data(<Recommendation>[]);
    _invalidateScanInputs();
  }

  void _invalidateScanInputs() {
    ref.invalidate(largeFileScanProvider);
    ref.invalidate(downloadsScanProvider);
    ref.invalidate(apkScanProvider);
    ref.invalidate(smartScanProvider);
    ref.invalidate(screenshotScanProvider);
    ref.invalidate(duplicateScanProvider);
    ref.invalidate(duplicatesProvider);
    ref.invalidate(videoScanProvider);
    ref.invalidate(recommendationInputsProvider);
  }
}
