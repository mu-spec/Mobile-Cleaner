import 'package:mobile_cleaner/features/files/domain/perceptual_hash.dart';
import 'package:mobile_cleaner/features/files/domain/photo_copy_group.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// A set of photos that look alike without being byte-identical.
///
/// Typically a burst: several shots of the same scene seconds apart. Unlike a
/// `DuplicateGroup` these are *not* interchangeable — one may be sharper, or
/// the one where nobody blinked — so the tool never pre-selects anything and
/// the user's choice of keeper matters more here than for exact duplicates.
class SimilarPhotoGroup implements PhotoCopyGroup {
  const SimilarPhotoGroup({required this.key, required this.files});

  /// Stable identity, derived from the leader's URI.
  final String key;

  /// Members, oldest first, so the suggested keeper is the first shot taken.
  @override
  final List<ScannedFile> files;

  @override
  String get groupKey => key;

  int get photoCount => files.length;

  /// Combined size of every photo in the group.
  int get totalBytes => files.fold<int>(
    0,
    (int sum, ScannedFile file) => sum + file.sizeBytes,
  );

  /// Space freed by keeping the largest single photo and removing the rest.
  ///
  /// The largest is used deliberately: it is usually the highest quality shot,
  /// so this is the *conservative* estimate of what the user would recover.
  int get reclaimableBytes {
    if (files.length <= 1) {
      return 0;
    }
    int largest = 0;
    for (final ScannedFile file in files) {
      if (file.sizeBytes > largest) {
        largest = file.sizeBytes;
      }
    }
    return totalBytes - largest;
  }

  /// Suggested keeper: the oldest shot, matching the duplicate tool's rule.
  ///
  /// Only a default. Similar photos genuinely differ, so the user is expected
  /// to look before choosing, and nothing is selected for them.
  @override
  ScannedFile? get original => files.isEmpty ? null : files.first;

  /// Timespan the group covers, useful for recognising a burst.
  Duration get timeSpan {
    if (files.length < 2) {
      return Duration.zero;
    }
    DateTime earliest = files.first.dateModified;
    DateTime latest = files.first.dateModified;
    for (final ScannedFile file in files) {
      if (file.dateModified.isBefore(earliest)) {
        earliest = file.dateModified;
      }
      if (file.dateModified.isAfter(latest)) {
        latest = file.dateModified;
      }
    }
    return latest.difference(earliest);
  }

  /// True when every shot was taken within a minute — almost certainly a burst.
  bool get isBurst => files.length > 1 && timeSpan.inSeconds <= 60;
}

/// Outcome of one similar-photo scan.
class SimilarPhotoScanResult {
  const SimilarPhotoScanResult({
    required this.groups,
    this.photosAnalyzed = 0,
    this.photosHashed = 0,
  });

  static const SimilarPhotoScanResult empty = SimilarPhotoScanResult(
    groups: <SimilarPhotoGroup>[],
  );

  /// Similar sets, biggest reclaimable saving first.
  final List<SimilarPhotoGroup> groups;

  /// How many photos went into the comparison. Diagnostic.
  final int photosAnalyzed;

  /// How many produced a usable perceptual hash. Diagnostic.
  final int photosHashed;

  int get groupCount => groups.length;

  /// Total number of extra shots across every group.
  int get extraPhotoCount => groups.fold<int>(
    0,
    (int sum, SimilarPhotoGroup g) => sum + g.photoCount - 1,
  );

  /// Total space recoverable by keeping the best shot of each group.
  int get reclaimableBytes => groups.fold<int>(
    0,
    (int sum, SimilarPhotoGroup g) => sum + g.reclaimableBytes,
  );

  bool get isEmpty => groups.isEmpty;
}

/// How alike two photos must look before they are grouped.
enum SimilarityStrength {
  /// Only near-identical frames. Fewest groups, fewest surprises.
  strict('Strict', 'Near-identical shots only', 4, 6),

  /// The default. Catches a normal burst without reaching across scenes.
  balanced('Balanced', 'Nearly identical shots', 8, 10),

  /// Wider net. Will group shots that merely resemble each other.
  relaxed('Relaxed', 'Loosely similar shots', 12, 14);

  const SimilarityStrength(
    this.label,
    this.description,
    this.maxDifferenceDistance,
    this.maxAverageDistance,
  );

  final String label;
  final String description;

  /// Maximum differing bits in the gradient hash, out of 64.
  final int maxDifferenceDistance;

  /// Maximum differing bits in the average hash, out of 64.
  ///
  /// Looser than the gradient bound because aHash is the weaker signal; it is
  /// there to veto obvious mismatches, not to make the primary decision.
  final int maxAverageDistance;

  static const SimilarityStrength defaultStrength = SimilarityStrength.balanced;

  /// True when two hashes are close enough under this strength.
  ///
  /// **Both** hashes must agree. dHash alone groups any two flat images — a
  /// clear sky and a white wall have almost the same gradient signature —
  /// and aHash alone is fooled by exposure changes. Requiring both is what
  /// makes the result trustworthy enough to offer deletion from.
  bool matches(PerceptualHash a, PerceptualHash b) =>
      a.differenceDistance(b) <= maxDifferenceDistance &&
      a.averageDistance(b) <= maxAverageDistance;
}
