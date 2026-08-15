import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// The files matching one [LargeFileFilter], plus the space they occupy.
class LargeFileSummary {
  const LargeFileSummary({
    required this.filter,
    required this.files,
    required this.totalBytes,
  });

  /// Builds a summary by filtering [source] to [filter].
  ///
  /// Files are de-duplicated by URI first, because a downloaded APK is
  /// reported under both Downloads and APKs and must not be counted twice.
  factory LargeFileSummary.from(
    Iterable<ScannedFile> source,
    LargeFileFilter filter,
  ) {
    final Set<String> seen = <String>{};
    final List<ScannedFile> matches = <ScannedFile>[];
    int totalBytes = 0;

    for (final ScannedFile file in source) {
      if (!filter.matches(file.sizeBytes)) {
        continue;
      }
      if (!seen.add(file.uri)) {
        continue;
      }
      matches.add(file);
      totalBytes += file.sizeBytes;
    }

    matches.sort(
      (ScannedFile a, ScannedFile b) => b.sizeBytes.compareTo(a.sizeBytes),
    );

    return LargeFileSummary(
      filter: filter,
      files: List<ScannedFile>.unmodifiable(matches),
      totalBytes: totalBytes,
    );
  }

  final LargeFileFilter filter;

  /// Matching files, largest first.
  final List<ScannedFile> files;

  /// Combined size of [files], the headline "space used" figure.
  final int totalBytes;

  int get fileCount => files.length;

  bool get isEmpty => files.isEmpty;

  /// Bytes per category, largest contributor first.
  List<MapEntry<FileCategory, int>> get bytesByCategory {
    final Map<FileCategory, int> totals = <FileCategory, int>{};
    for (final ScannedFile file in files) {
      totals[file.category] = (totals[file.category] ?? 0) + file.sizeBytes;
    }
    final List<MapEntry<FileCategory, int>> entries = totals.entries.toList()
      ..sort(
        (MapEntry<FileCategory, int> a, MapEntry<FileCategory, int> b) =>
            b.value.compareTo(a.value),
      );
    return entries;
  }

  /// The single biggest file, or `null` when nothing matched.
  ScannedFile? get largestFile => files.isEmpty ? null : files.first;
}
