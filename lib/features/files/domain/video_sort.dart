import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Orderings offered by the Videos section.
enum VideoSort {
  largest('Largest', 'Biggest files first'),
  longest('Longest', 'Longest playback first'),
  newest('Newest', 'Most recent first'),
  oldest('Oldest', 'Oldest first');

  const VideoSort(this.label, this.description);

  final String label;
  final String description;

  static const VideoSort defaultSort = VideoSort.largest;

  /// Comparator for this ordering.
  ///
  /// Every comparator falls back to the file name, so equal sizes, equal
  /// lengths, or identical timestamps still produce a stable, predictable
  /// order rather than one that shuffles between rebuilds.
  Comparator<ScannedFile> get comparator {
    int byName(ScannedFile a, ScannedFile b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());

    return switch (this) {
      VideoSort.largest => (ScannedFile a, ScannedFile b) {
        final int result = b.sizeBytes.compareTo(a.sizeBytes);
        return result != 0 ? result : byName(a, b);
      },
      VideoSort.longest => (ScannedFile a, ScannedFile b) {
        // Videos of unknown length sort last rather than first. MediaStore
        // leaves DURATION null often enough that treating it as zero would
        // bury real videos beneath unreadable ones.
        final int? aMillis = a.durationMillis;
        final int? bMillis = b.durationMillis;
        if (aMillis == null && bMillis == null) {
          return byName(a, b);
        }
        if (aMillis == null) {
          return 1;
        }
        if (bMillis == null) {
          return -1;
        }
        final int result = bMillis.compareTo(aMillis);
        return result != 0 ? result : byName(a, b);
      },
      VideoSort.newest => (ScannedFile a, ScannedFile b) {
        final int result = b.dateModified.compareTo(a.dateModified);
        return result != 0 ? result : byName(a, b);
      },
      VideoSort.oldest => (ScannedFile a, ScannedFile b) {
        final int result = a.dateModified.compareTo(b.dateModified);
        return result != 0 ? result : byName(a, b);
      },
    };
  }
}
