import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/perceptual_hash_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/photo_duplicates.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/similar_photo_detector.dart';
import 'package:mobile_cleaner/features/files/domain/similar_photo_group.dart';

/// One scan of the places photographs live.
///
/// Mirrors the duplicate-photo scan: Downloads is included because a saved
/// picture is still a photo, and the result is narrowed to images before
/// anything is decoded.
final FutureProvider<FileScanResult> similarPhotoScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return ref
          .watch(fileScannerRepositoryProvider)
          .scan(
            FileScanRequest(
              categories: const <FileCategory>[
                FileCategory.images,
                FileCategory.downloads,
              ],
              minSizeBytes: SimilarPhotoDetector.minimumPhotoBytes,
              limitPerCategory: 500,
              sortOrder: FileSortOrder.dateDesc,
            ),
          );
    });

/// The perceptual hash of every candidate photo.
///
/// Kept separate from the grouping so that changing similarity strength
/// re-groups in memory instead of decoding every image again. Decoding is by
/// far the expensive step.
final FutureProvider<Map<String, String>> photoFingerprintProvider =
    FutureProvider<Map<String, String>>((ref) async {
      final FileScanResult scan = await ref.watch(
        similarPhotoScanProvider.future,
      );

      final List<ScannedFile> candidates = SimilarPhotoDetector.candidates(
        scan.files,
      );
      if (candidates.isEmpty) {
        return const <String, String>{};
      }

      return ref
          .watch(perceptualHashRepositoryProvider)
          .hashImages(candidates);
    });

/// Visually similar photo groups at one similarity strength.
final similarPhotosProvider =
    FutureProvider.family<SimilarPhotoScanResult, SimilarityStrength>((
      ref,
      SimilarityStrength strength,
    ) async {
      final FileScanResult scan = await ref.watch(
        similarPhotoScanProvider.future,
      );
      final Map<String, String> hashes = await ref.watch(
        photoFingerprintProvider.future,
      );
      if (hashes.isEmpty) {
        return SimilarPhotoScanResult.empty;
      }

      return SimilarPhotoDetector.group(
        PhotoDuplicates.only(scan.files),
        hashes,
        strength: strength,
      );
    });
