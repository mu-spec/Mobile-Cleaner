import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/video_sort.dart';

/// The device's videos in one ordering, plus the space they occupy.
class VideoSummary {
  const VideoSummary({
    required this.sort,
    required this.videos,
    required this.totalBytes,
    required this.totalDuration,
    required this.unknownDurationCount,
  });

  /// Builds a summary from a scan, keeping videos only.
  ///
  /// De-duplicates by URI, so a clip reported under both Videos and Downloads
  /// is listed and counted exactly once.
  factory VideoSummary.from(
    Iterable<ScannedFile> source,
    VideoSort sort,
  ) {
    final Set<String> seen = <String>{};
    final List<ScannedFile> matches = <ScannedFile>[];
    int totalBytes = 0;
    int totalMillis = 0;
    int unknown = 0;

    for (final ScannedFile file in source) {
      if (!isVideo(file)) {
        continue;
      }
      if (!seen.add(file.uri)) {
        continue;
      }
      matches.add(file);
      totalBytes += file.sizeBytes;
      final int? millis = file.durationMillis;
      if (millis == null) {
        unknown++;
      } else {
        totalMillis += millis;
      }
    }

    matches.sort(sort.comparator);

    return VideoSummary(
      sort: sort,
      videos: List<ScannedFile>.unmodifiable(matches),
      totalBytes: totalBytes,
      totalDuration: Duration(milliseconds: totalMillis),
      unknownDurationCount: unknown,
    );
  }

  static const VideoSummary empty = VideoSummary(
    sort: VideoSort.largest,
    videos: <ScannedFile>[],
    totalBytes: 0,
    totalDuration: Duration.zero,
    unknownDurationCount: 0,
  );

  /// True when [file] is a video.
  ///
  /// The MIME type is trusted over the category bucket, because a clip saved
  /// into Downloads is still a video and belongs in this section.
  static bool isVideo(ScannedFile file) {
    final String? mime = file.mimeType?.toLowerCase();
    if (mime != null && mime.isNotEmpty) {
      return mime.startsWith('video/');
    }
    return file.category == FileCategory.videos;
  }

  final VideoSort sort;

  /// Videos in [sort] order.
  final List<ScannedFile> videos;

  /// Combined size of [videos].
  final int totalBytes;

  /// Combined playback length of the videos whose length is known.
  final Duration totalDuration;

  /// How many videos MediaStore could not report a length for.
  ///
  /// Surfaced rather than hidden, so the total length is not quietly
  /// understated.
  final int unknownDurationCount;

  int get videoCount => videos.length;

  bool get isEmpty => videos.isEmpty;

  /// True when at least one video is missing its length.
  bool get hasUnknownDurations => unknownDurationCount > 0;

  /// The biggest video, or null when there are none.
  ScannedFile? get largestVideo {
    if (videos.isEmpty) {
      return null;
    }
    return videos.reduce(
      (ScannedFile a, ScannedFile b) => b.sizeBytes > a.sizeBytes ? b : a,
    );
  }

  /// The longest video, or null when no length is known.
  ScannedFile? get longestVideo {
    ScannedFile? longest;
    for (final ScannedFile file in videos) {
      final int? millis = file.durationMillis;
      if (millis == null) {
        continue;
      }
      if (longest == null || millis > longest.durationMillis!) {
        longest = file;
      }
    }
    return longest;
  }

  /// Mean video size. Zero when empty.
  int get averageBytes => videos.isEmpty ? 0 : totalBytes ~/ videos.length;
}
