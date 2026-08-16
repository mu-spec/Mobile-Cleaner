import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_detector.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// One scan across the categories duplicates realistically appear in.
///
/// The size floor is applied here so the platform never returns the thousands
/// of tiny files that could never be worth hashing.
final FutureProvider<FileScanResult> duplicateScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return ref
          .watch(fileScannerRepositoryProvider)
          .scan(
            FileScanRequest(
              categories: const <FileCategory>[
                FileCategory.images,
                FileCategory.videos,
                FileCategory.audio,
                FileCategory.documents,
                FileCategory.downloads,
              ],
              minSizeBytes: DuplicateDetector.minimumFileBytes,
              limitPerCategory: 500,
            ),
          );
    });

/// Exact duplicates: same size, then confirmed by content hash.
///
/// Hashing is the expensive step, so it runs only for files that already share
/// a size with another file. On a library with no repeated sizes, no file is
/// read at all.
final FutureProvider<DuplicateScanResult> duplicatesProvider =
    FutureProvider<DuplicateScanResult>((ref) async {
      final FileScanResult scan = await ref.watch(
        duplicateScanProvider.future,
      );

      final List<ScannedFile> candidates = DuplicateDetector.candidates(
        scan.files,
      );
      if (candidates.isEmpty) {
        return DuplicateScanResult.empty;
      }

      final Map<String, String> hashes = await ref
          .watch(fileHashRepositoryProvider)
          .hashFiles(candidates);

      return DuplicateDetector.group(scan.files, hashes);
    });
