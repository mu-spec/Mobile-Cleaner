import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';

/// Existing review screen owned by each recommendation category.
String recommendationRoute(RecommendationKind kind) => switch (kind) {
  RecommendationKind.duplicateCleanup => AppRoutes.duplicates,
  RecommendationKind.apkInstallerReview => AppRoutes.apkCleaner,
  RecommendationKind.oldDownloadReview => AppRoutes.downloadsCleaner,
  RecommendationKind.screenshotReview => AppRoutes.screenshotCleaner,
  RecommendationKind.largeFileReview => AppRoutes.largeFiles,
  RecommendationKind.largeVideoReview => AppRoutes.videos,
};
