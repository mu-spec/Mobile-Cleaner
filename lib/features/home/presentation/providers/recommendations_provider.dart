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
import 'package:mobile_cleaner/features/home/domain/cleanup_score.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation_engine.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';

/// The one completed analyzer snapshot used to produce both Home features.
class CleanupScanData {
  const CleanupScanData({
    required this.recommendationInputs,
    required this.scoreSnapshot,
  });

  final RecommendationInputs recommendationInputs;

  /// Null only when Android could not provide real total-storage capacity.
  /// Recommendations remain usable, but a ratio-based score would be
  /// misleading and is therefore left unavailable.
  final CleanupScanSnapshot? scoreSnapshot;
}

/// Score and recommendations calculated together from one scan snapshot.
class CompletedCleanupAnalysis {
  const CompletedCleanupAnalysis({
    required this.score,
    required this.recommendations,
    required this.scannedAt,
  });

  final CleanupScore score;
  final List<Recommendation> recommendations;
  final DateTime scannedAt;
}

/// Gathers results from the existing real analyzers after a user starts Smart
/// Scan. Nothing on Home watches this provider directly, so it cannot start a
/// background scan merely because the Home screen was built.
final FutureProvider<CleanupScanData>
cleanupScanDataProvider = FutureProvider<CleanupScanData>((ref) async {
  final Future<SmartScanResult> smartScan = ref.watch(smartScanProvider.future);
  final Future<ScreenshotSummary> screenshots = ref.watch(
    screenshotSummaryProvider(ScreenshotGroup.days90).future,
  );
  final Future<DuplicateScanResult> duplicates = ref.watch(
    duplicatesProvider.future,
  );
  final Future<VideoSummary> videos = ref.watch(
    videoSummaryProvider(VideoSort.largest).future,
  );
  final Future<StorageInfo> storage = ref.watch(storageOverviewProvider.future);

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

  StorageInfo? storageInfo;
  try {
    storageInfo = await storage;
  } catch (_) {
    // A recommendation can still be based on real file analyzers when
    // Android cannot report capacity. The score cannot, so it stays
    // unavailable instead of guessing a denominator.
  }

  final RecommendationInputs inputs = RecommendationInputs(
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

  return CleanupScanData(
    recommendationInputs: inputs,
    scoreSnapshot: storageInfo == null
        ? null
        : CleanupScanSnapshot(
            totalStorageBytes: storageInfo.totalBytes,
            scannedAt: fileResult.scannedAt,
            opportunities: <CleanupOpportunity>[
              CleanupOpportunity(
                kind: CleanupOpportunityKind.exactDuplicates,
                files: duplicateResult.allDuplicates,
              ),
              CleanupOpportunity(
                kind: CleanupOpportunityKind.apkInstallers,
                files: apks.files,
              ),
              CleanupOpportunity(
                kind: CleanupOpportunityKind.oldDownloads,
                files: oldDownloads.files,
              ),
              CleanupOpportunity(
                kind: CleanupOpportunityKind.oldScreenshots,
                files: staleShots.files,
              ),
              CleanupOpportunity(
                kind: CleanupOpportunityKind.largeVideos,
                files: largeVideos,
              ),
              CleanupOpportunity(
                kind: CleanupOpportunityKind.largeFiles,
                files: largeFiles.files,
              ),
            ],
          ),
  );
});

/// In-memory only: a restart or invalidation returns to the unscanned state.
final NotifierProvider<
  CleanupAnalysisController,
  AsyncValue<CompletedCleanupAnalysis?>
>
cleanupAnalysisProvider =
    NotifierProvider<
      CleanupAnalysisController,
      AsyncValue<CompletedCleanupAnalysis?>
    >(CleanupAnalysisController.new);

class CleanupAnalysisController
    extends Notifier<AsyncValue<CompletedCleanupAnalysis?>> {
  @override
  AsyncValue<CompletedCleanupAnalysis?> build() =>
      const AsyncValue<CompletedCleanupAnalysis?>.data(null);

  void begin() {
    state = const AsyncValue<CompletedCleanupAnalysis?>.loading();
  }

  void complete(CompletedCleanupAnalysis analysis) {
    state = AsyncValue<CompletedCleanupAnalysis?>.data(analysis);
  }

  void unavailable(Object error, StackTrace stackTrace) {
    state = AsyncValue<CompletedCleanupAnalysis?>.error(error, stackTrace);
  }

  void invalidate() {
    state = const AsyncValue<CompletedCleanupAnalysis?>.data(null);
  }
}

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
    final CleanupAnalysisController analysis = ref.read(
      cleanupAnalysisProvider.notifier,
    )..begin();
    _invalidateScanInputs();

    try {
      final CleanupScanData scanData = await ref.read(
        cleanupScanDataProvider.future,
      );
      final List<Recommendation> found = RecommendationEngine.evaluate(
        scanData.recommendationInputs,
      );
      final CleanupScanSnapshot? snapshot = scanData.scoreSnapshot;
      if (snapshot == null) {
        analysis.unavailable(
          StateError('Storage capacity is unavailable.'),
          StackTrace.current,
        );
      } else {
        analysis.complete(
          CompletedCleanupAnalysis(
            score: CleanupScoreCalculator.calculate(snapshot),
            recommendations: found,
            scannedAt: snapshot.scannedAt,
          ),
        );
      }
      state = AsyncValue<List<Recommendation>>.data(found);
      return found;
    } catch (error, stackTrace) {
      analysis.unavailable(error, stackTrace);
      state = AsyncValue<List<Recommendation>>.error(error, stackTrace);
      rethrow;
    }
  }

  /// Clears potentially stale advice without starting another scan.
  void invalidateAfterCleanup() {
    state = const AsyncValue<List<Recommendation>>.data(<Recommendation>[]);
    ref.read(cleanupAnalysisProvider.notifier).invalidate();
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
    ref.invalidate(cleanupScanDataProvider);
  }
}
