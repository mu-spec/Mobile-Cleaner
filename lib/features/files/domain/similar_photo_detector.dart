import 'package:mobile_cleaner/features/files/domain/perceptual_hash.dart';
import 'package:mobile_cleaner/features/files/domain/photo_duplicates.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/similar_photo_group.dart';

/// Groups photos that look alike.
///
/// Runs entirely on-device. Every comparison is integer arithmetic over two
/// 64-bit hashes; no image data leaves the phone and nothing is uploaded.
///
/// The pipeline mirrors the exact-duplicate one — cheap before expensive:
///
/// ```
/// images only  ->  perceptual hash  ->  compare hashes  ->  similar group
/// ```
///
/// Hashing requires decoding, so it is the expensive step and is capped. The
/// comparison itself is trivially cheap.
abstract final class SimilarPhotoDetector {
  /// Photos below this are ignored: thumbnails and icons look alike to a
  /// perceptual hash and grouping them is noise, not cleaning.
  static const int minimumPhotoBytes = 64 * 1024;

  /// Upper bound on photos compared in one pass.
  ///
  /// Comparison is leader-based, so cost is roughly photos x groups rather
  /// than photos squared, but decoding is not free and a phone holding tens of
  /// thousands of images should not stall on entering the screen.
  static const int maxPhotosPerScan = 600;

  /// The photos worth hashing: images, above the floor, de-duplicated by URI.
  ///
  /// De-duplicating first matters because a photo surfaced under two
  /// categories would otherwise appear to be similar to itself.
  static List<ScannedFile> candidates(Iterable<ScannedFile> files) {
    final Set<String> seen = <String>{};
    final List<ScannedFile> photos = <ScannedFile>[];

    for (final ScannedFile file in files) {
      if (!PhotoDuplicates.isPhoto(file)) {
        continue;
      }
      if (file.sizeBytes < minimumPhotoBytes) {
        continue;
      }
      if (!seen.add(file.uri)) {
        continue;
      }
      photos.add(file);
      if (photos.length >= maxPhotosPerScan) {
        break;
      }
    }

    return photos;
  }

  /// Groups [files] using the perceptual [hashes], keyed by URI.
  ///
  /// A photo with no usable hash is dropped rather than guessed at.
  ///
  /// ## Why leader comparison, not transitive chaining
  ///
  /// The obvious approach — union any two photos within the threshold — chains:
  /// A is near B, B is near C, C is near D, and the group ends up holding two
  /// photos that look nothing like each other. Every member here is instead
  /// compared against its group's **leader**, so every photo in a group is
  /// provably within the threshold of one common reference. Groups stay tight
  /// and a user reviewing them is never asked to compare unrelated scenes.
  static SimilarPhotoScanResult group(
    Iterable<ScannedFile> files,
    Map<String, String> hashes, {
    SimilarityStrength strength = SimilarityStrength.defaultStrength,
  }) {
    final List<ScannedFile> photos = candidates(files);

    final List<ScannedFile> hashed = <ScannedFile>[];
    final Map<String, PerceptualHash> parsed = <String, PerceptualHash>{};
    for (final ScannedFile photo in photos) {
      final PerceptualHash? hash = PerceptualHash.tryParse(hashes[photo.uri]);
      if (hash == null) {
        continue;
      }
      parsed[photo.uri] = hash;
      hashed.add(photo);
    }

    // Oldest first, so the leader of each group is the first shot taken and
    // the ordering inside a group is chronological — how a burst reads.
    hashed.sort(
      (ScannedFile a, ScannedFile b) =>
          a.dateModified.compareTo(b.dateModified),
    );

    final List<ScannedFile> leaders = <ScannedFile>[];
    final Map<String, List<ScannedFile>> members =
        <String, List<ScannedFile>>{};

    for (final ScannedFile photo in hashed) {
      final PerceptualHash hash = parsed[photo.uri]!;
      ScannedFile? bestLeader;
      int bestDistance = 1 << 30;

      for (final ScannedFile leader in leaders) {
        final PerceptualHash leaderHash = parsed[leader.uri]!;
        if (!strength.matches(hash, leaderHash)) {
          continue;
        }
        // Closest leader wins, so a photo between two groups joins the one it
        // actually resembles most.
        final int distance = hash.differenceDistance(leaderHash);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestLeader = leader;
        }
      }

      if (bestLeader == null) {
        leaders.add(photo);
        members[photo.uri] = <ScannedFile>[photo];
      } else {
        members[bestLeader.uri]!.add(photo);
      }
    }

    final List<SimilarPhotoGroup> groups = <SimilarPhotoGroup>[
      for (final ScannedFile leader in leaders)
        if (members[leader.uri]!.length > 1)
          SimilarPhotoGroup(
            key: leader.uri,
            files: List<ScannedFile>.unmodifiable(members[leader.uri]!),
          ),
    ];

    // Biggest saving first.
    groups.sort(
      (SimilarPhotoGroup a, SimilarPhotoGroup b) =>
          b.reclaimableBytes.compareTo(a.reclaimableBytes),
    );

    return SimilarPhotoScanResult(
      groups: List<SimilarPhotoGroup>.unmodifiable(groups),
      photosAnalyzed: photos.length,
      photosHashed: hashed.length,
    );
  }
}
