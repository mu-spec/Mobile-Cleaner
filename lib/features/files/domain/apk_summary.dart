import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Installer packages found on the device, plus the space they occupy.
class ApkSummary {
  const ApkSummary({
    required this.files,
    required this.totalBytes,
    required this.sort,
  });

  /// Builds a summary from any file list, keeping only real `.apk` files.
  ///
  /// Filtering on [ScannedFile.isApk] rather than category matters: an
  /// installer sitting in the Downloads folder is still an APK, and the
  /// scanner reports it under both categories.
  ///
  /// De-duplicates by URI so a package reported under both Downloads and
  /// APKs is listed and counted exactly once.
  factory ApkSummary.from(
    Iterable<ScannedFile> source, {
    FileListSort sort = FileListSort.largest,
  }) {
    final Set<String> seen = <String>{};
    final List<ScannedFile> matches = <ScannedFile>[];
    int totalBytes = 0;

    for (final ScannedFile file in source) {
      if (!file.isApk) {
        continue;
      }
      if (!seen.add(file.uri)) {
        continue;
      }
      matches.add(file);
      totalBytes += file.sizeBytes;
    }

    matches.sort(FileScanResult.compareFiles(sort));

    return ApkSummary(
      files: List<ScannedFile>.unmodifiable(matches),
      totalBytes: totalBytes,
      sort: sort,
    );
  }

  /// Matching installers, ordered by [sort].
  final List<ScannedFile> files;

  /// Combined size of [files].
  final int totalBytes;

  /// Order the list is currently in.
  final FileListSort sort;

  int get fileCount => files.length;

  bool get isEmpty => files.isEmpty;

  /// The largest installer, or `null` when none were found.
  ScannedFile? get largestFile {
    if (files.isEmpty) {
      return null;
    }
    return files.reduce(
      (ScannedFile a, ScannedFile b) => b.sizeBytes > a.sizeBytes ? b : a,
    );
  }
}
