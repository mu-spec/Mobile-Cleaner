import 'package:mobile_cleaner/features/files/domain/download_age_filter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Downloads older than one [DownloadAgeFilter], plus the space they occupy.
class DownloadsSummary {
  const DownloadsSummary({
    required this.filter,
    required this.files,
    required this.totalBytes,
  });

  /// Builds a summary by filtering [source] to downloads matching [filter].
  ///
  /// De-duplicates by URI, because a downloaded APK is reported under both
  /// Downloads and APKs and must not be counted twice.
  factory DownloadsSummary.from(
    Iterable<ScannedFile> source,
    DownloadAgeFilter filter, {
    DateTime? now,
  }) {
    final Set<String> seen = <String>{};
    final List<ScannedFile> matches = <ScannedFile>[];
    int totalBytes = 0;

    for (final ScannedFile file in source) {
      if (!filter.matches(file.dateModified, now: now)) {
        continue;
      }
      if (!seen.add(file.uri)) {
        continue;
      }
      matches.add(file);
      totalBytes += file.sizeBytes;
    }

    // Oldest first: the strongest cleanup candidates lead.
    matches.sort(
      (ScannedFile a, ScannedFile b) => a.dateModified.compareTo(b.dateModified),
    );

    return DownloadsSummary(
      filter: filter,
      files: List<ScannedFile>.unmodifiable(matches),
      totalBytes: totalBytes,
    );
  }

  final DownloadAgeFilter filter;

  /// Matching downloads, oldest first.
  final List<ScannedFile> files;

  /// Combined size of [files], the headline "space used" figure.
  final int totalBytes;

  int get fileCount => files.length;

  bool get isEmpty => files.isEmpty;

  /// The oldest matching download, or `null` when nothing matched.
  ScannedFile? get oldestFile => files.isEmpty ? null : files.first;

  /// The largest matching download, or `null` when nothing matched.
  ScannedFile? get largestFile {
    if (files.isEmpty) {
      return null;
    }
    return files.reduce(
      (ScannedFile a, ScannedFile b) => b.sizeBytes > a.sizeBytes ? b : a,
    );
  }
}
