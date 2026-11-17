import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:phone_storage_cleaner/features/files/data/perceptual_hash_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_category.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_scan_result.dart';
import 'package:phone_storage_cleaner/features/files/domain/photo_duplicates.dart';
import 'package:phone_storage_cleaner/features/files/domain/scanned_file.dart';
import 'package:phone_storage_cleaner/features/files/domain/similar_photo_detector.dart';
import 'package:phone_storage_cleaner/features/files/domain/similar_photo_group.dart';

/// One scan of the places photographs live.
///
/// Mirrors the duplicate-photo scan: Downloads is included because a saved
/// picture is still a photo, and the result is narrowed to images before
/// anything is decoded.
final FutureProvider<FileScanResult> similarPhotoScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return observeScan(ref, 'discovery:similar', () async {
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
      }, numeric: false);
    });

/// The perceptual hash of every candidate photo.
///
/// Kept separate from the grouping so that changing similarity strength
/// re-groups in memory instead of decoding every image again. Decoding is by
/// far the expensive step.
final FutureProvider<Map<String, String>> photoFingerprintProvider =
    FutureProvider<Map<String, String>>((ref) async {
      return observeScan(ref, 'fingerprints', () async {
        final FileScanResult scan = await scanDependency(
          ref,
          'discovery:similar',
          ref.watch(similarPhotoScanProvider.future),
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
      }, numeric: false);
    });

/// Visually similar photo groups at one similarity strength.
final similarPhotosProvider =
    FutureProvider.family<SimilarPhotoScanResult, SimilarityStrength>((
      ref,
      SimilarityStrength strength,
    ) async {
      return observeScan(ref, 'similar', () async {
        final FileScanResult scan = await scanDependency(
          ref,
          'discovery:similar',
          ref.watch(similarPhotoScanProvider.future),
        );
        final Map<String, String> hashes = await scanDependency(
          ref,
          'fingerprints',
          ref.watch(photoFingerprintProvider.future),
        );
        if (hashes.isEmpty) {
          return SimilarPhotoScanResult.empty;
        }

        ScanOperation.current?.stage('Comparing similar photos');
        return SimilarPhotoDetector.group(
          PhotoDuplicates.only(scan.files),
          hashes,
          strength: strength,
        );
      }, numeric: false);
    });
