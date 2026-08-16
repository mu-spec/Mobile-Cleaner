import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_filter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Photos matching one [LargePhotoFilter], plus the space they occupy.
class LargePhotoSummary {
  const LargePhotoSummary({
    required this.filter,
    required this.files,
    required this.totalBytes,
  });

  /// Builds a summary by keeping the photos in [source] that meet [filter].
  ///
  /// De-duplicates by URI, so an image reported under more than one category
  /// is listed and counted exactly once.
  factory LargePhotoSummary.from(
    Iterable<ScannedFile> source,
    LargePhotoFilter filter,
  ) {
    final Set<String> seen = <String>{};
    final List<ScannedFile> matches = <ScannedFile>[];
    int totalBytes = 0;

    for (final ScannedFile file in source) {
      if (!isPhoto(file)) {
        continue;
      }
      if (!filter.matches(file.sizeBytes)) {
        continue;
      }
      if (!seen.add(file.uri)) {
        continue;
      }
      matches.add(file);
      totalBytes += file.sizeBytes;
    }

    // Largest first: the biggest space savings lead.
    matches.sort(
      (ScannedFile a, ScannedFile b) => b.sizeBytes.compareTo(a.sizeBytes),
    );

    return LargePhotoSummary(
      filter: filter,
      files: List<ScannedFile>.unmodifiable(matches),
      totalBytes: totalBytes,
    );
  }

  /// True when [file] is a still image.
  ///
  /// Videos are excluded even though they are the largest media on most
  /// devices: a tool labelled "Large Photos" that offered to delete a home
  /// video would be a nasty surprise. Large videos remain reachable through
  /// Large Files and the Videos category.
  static bool isPhoto(ScannedFile file) {
    final String? mime = file.mimeType?.toLowerCase();
    if (mime != null) {
      // Trust an explicit MIME type over the category bucket.
      return mime.startsWith('image/');
    }
    return file.category == FileCategory.images;
  }

  final LargePhotoFilter filter;

  /// Matching photos, largest first.
  final List<ScannedFile> files;

  /// Combined size of [files], the headline "space used" figure.
  final int totalBytes;

  int get fileCount => files.length;

  bool get isEmpty => files.isEmpty;

  /// The largest photo, or `null` when nothing matched.
  ScannedFile? get largestFile => files.isEmpty ? null : files.first;

  /// Mean photo size, useful context next to the total. Zero when empty.
  int get averageBytes => files.isEmpty ? 0 : totalBytes ~/ files.length;
}
