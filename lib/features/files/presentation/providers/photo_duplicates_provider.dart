import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_detector.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/photo_duplicates.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// One scan of the places photographs live.
///
/// Downloads is included because a picture saved from a chat is the most
/// common source of a second copy; it is filtered back down to images before
/// anything is hashed.
final FutureProvider<FileScanResult> photoDuplicateScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return ref
          .watch(fileScannerRepositoryProvider)
          .scan(
            FileScanRequest(
              categories: const <FileCategory>[
                FileCategory.images,
                FileCategory.downloads,
              ],
              minSizeBytes: DuplicateDetector.minimumFileBytes,
              limitPerCategory: 500,
            ),
          );
    });

/// Duplicate photos: same size, then confirmed byte-identical by hash.
///
/// This is the Phase 17 engine unchanged. The only difference is the input:
/// images alone, so the results can be shown as picture groups.
final FutureProvider<DuplicateScanResult> photoDuplicatesProvider =
    FutureProvider<DuplicateScanResult>((ref) async {
      final FileScanResult scan = await ref.watch(
        photoDuplicateScanProvider.future,
      );

      final List<ScannedFile> photos = PhotoDuplicates.only(scan.files);
      if (photos.isEmpty) {
        return DuplicateScanResult.empty;
      }

      final List<ScannedFile> candidates = DuplicateDetector.candidates(photos);
      if (candidates.isEmpty) {
        return DuplicateScanResult.empty;
      }

      final Map<String, String> hashes = await ref
          .watch(fileHashRepositoryProvider)
          .hashFiles(candidates);

      return DuplicateDetector.group(photos, hashes);
    });
