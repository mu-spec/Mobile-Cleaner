import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/photo_quality_repository.dart';
import 'package:mobile_cleaner/features/files/domain/best_photo_scorer.dart';
import 'package:mobile_cleaner/features/files/domain/photo_quality.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/similar_photo_group.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/similar_photos_provider.dart';

/// Measurements for every photo that landed in a similar group.
///
/// Only grouped photos are measured. A lone photo has nothing to be compared
/// against, so analysing it would be wasted decoding.
final photoQualityProvider =
    FutureProvider.family<Map<String, PhotoQuality>, SimilarityStrength>((
      ref,
      SimilarityStrength strength,
    ) async {
      final SimilarPhotoScanResult result = await ref.watch(
        similarPhotosProvider(strength).future,
      );
      if (result.isEmpty) {
        return const <String, PhotoQuality>{};
      }

      final List<ScannedFile> grouped = <ScannedFile>[
        for (final SimilarPhotoGroup group in result.groups) ...group.files,
      ];

      return ref
          .watch(photoQualityRepositoryProvider)
          .analyzePhotos(grouped);
    });

/// A recommendation per group, keyed by [SimilarPhotoGroup.key].
///
/// Ranking is pure arithmetic over the measurements, so it is derived here
/// rather than recomputed by the widget on every rebuild.
final bestPhotoProvider =
    FutureProvider.family<
      Map<String, BestPhotoRecommendation>,
      SimilarityStrength
    >((ref, SimilarityStrength strength) async {
      final SimilarPhotoScanResult result = await ref.watch(
        similarPhotosProvider(strength).future,
      );
      if (result.isEmpty) {
        return const <String, BestPhotoRecommendation>{};
      }

      final Map<String, PhotoQuality> qualities = await ref.watch(
        photoQualityProvider(strength).future,
      );
      if (qualities.isEmpty) {
        return const <String, BestPhotoRecommendation>{};
      }

      return <String, BestPhotoRecommendation>{
        for (final SimilarPhotoGroup group in result.groups)
          group.key: BestPhotoScorer.rank(group.files, qualities),
      };
    });
