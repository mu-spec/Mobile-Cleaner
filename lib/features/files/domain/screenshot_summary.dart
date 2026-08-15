import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';

/// Screenshots in one [ScreenshotGroup], plus the space they occupy.
class ScreenshotSummary {
  const ScreenshotSummary({
    required this.group,
    required this.files,
    required this.totalBytes,
  });

  /// Builds a summary by keeping the screenshots in [source] that fall inside
  /// [group].
  ///
  /// De-duplicates by URI, so an image reported under more than one category
  /// is counted once.
  factory ScreenshotSummary.from(
    Iterable<ScannedFile> source,
    ScreenshotGroup group, {
    DateTime? now,
  }) {
    final Set<String> seen = <String>{};
    final List<ScannedFile> matches = <ScannedFile>[];
    int totalBytes = 0;

    for (final ScannedFile file in source) {
      if (!ScreenshotDetector.isScreenshot(file)) {
        continue;
      }
      if (!group.matches(file.dateModified, now: now)) {
        continue;
      }
      if (!seen.add(file.uri)) {
        continue;
      }
      matches.add(file);
      totalBytes += file.sizeBytes;
    }

    // Newest first: the most recognisable screenshots lead.
    matches.sort(
      (ScannedFile a, ScannedFile b) =>
          b.dateModified.compareTo(a.dateModified),
    );

    return ScreenshotSummary(
      group: group,
      files: List<ScannedFile>.unmodifiable(matches),
      totalBytes: totalBytes,
    );
  }

  final ScreenshotGroup group;

  /// Matching screenshots, newest first.
  final List<ScannedFile> files;

  /// Combined size of [files].
  final int totalBytes;

  int get fileCount => files.length;

  bool get isEmpty => files.isEmpty;

  /// The largest screenshot, or `null` when none matched.
  ScannedFile? get largestFile {
    if (files.isEmpty) {
      return null;
    }
    return files.reduce(
      (ScannedFile a, ScannedFile b) => b.sizeBytes > a.sizeBytes ? b : a,
    );
  }
}
