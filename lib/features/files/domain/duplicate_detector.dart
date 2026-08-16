import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Finds byte-identical files.
///
/// Exact duplicates only. No perceptual or similarity matching: two photos of
/// the same scene are not duplicates, and treating them as such would risk
/// deleting the better shot.
///
/// The pipeline is deliberately cheap before it is expensive:
///
/// ```
/// same size  ->  candidate group  ->  hash  ->  exact duplicate
/// ```
///
/// Size comes free from the scan, so it eliminates almost everything before a
/// single byte is read. Only files that share a size with another file are
/// ever hashed.
abstract final class DuplicateDetector {
  /// Files below this are ignored. Tiny files are usually system artefacts,
  /// and grouping thousands of 0-byte stubs is noise, not cleaning.
  static const int minimumFileBytes = 16 * 1024;

  /// Stage one: group by size, keeping only sizes shared by two or more files.
  ///
  /// De-duplicates by URI first, so a file reported under two categories is
  /// never mistaken for its own duplicate — the bug this stage most invites.
  static List<List<ScannedFile>> candidateGroups(Iterable<ScannedFile> files) {
    final Set<String> seenUris = <String>{};
    final Map<int, List<ScannedFile>> bySize = <int, List<ScannedFile>>{};

    for (final ScannedFile file in files) {
      if (file.sizeBytes < minimumFileBytes) {
        continue;
      }
      if (!seenUris.add(file.uri)) {
        continue;
      }
      bySize.putIfAbsent(file.sizeBytes, () => <ScannedFile>[]).add(file);
    }

    return <List<ScannedFile>>[
      for (final List<ScannedFile> group in bySize.values)
        if (group.length > 1) group,
    ];
  }

  /// Every file worth hashing, flattened from [candidateGroups].
  static List<ScannedFile> candidates(Iterable<ScannedFile> files) =>
      <ScannedFile>[
        for (final List<ScannedFile> group in candidateGroups(files))
          ...group,
      ];

  /// Stage two: split candidates by content hash.
  ///
  /// [hashes] maps URI to hash. A file missing from the map could not be read,
  /// and is dropped rather than guessed at — an unreadable file must never be
  /// presented as a duplicate.
  static DuplicateScanResult group(
    Iterable<ScannedFile> files,
    Map<String, String> hashes,
  ) {
    final List<List<ScannedFile>> sizeGroups = candidateGroups(files);
    final int candidateCount = sizeGroups.fold<int>(
      0,
      (int sum, List<ScannedFile> group) => sum + group.length,
    );

    final List<DuplicateGroup> duplicates = <DuplicateGroup>[];
    int hashed = 0;

    for (final List<ScannedFile> sizeGroup in sizeGroups) {
      final Map<String, List<ScannedFile>> byHash =
          <String, List<ScannedFile>>{};

      for (final ScannedFile file in sizeGroup) {
        final String? hash = hashes[file.uri];
        if (hash == null || hash.isEmpty) {
          continue;
        }
        hashed++;
        byHash.putIfAbsent(hash, () => <ScannedFile>[]).add(file);
      }

      for (final MapEntry<String, List<ScannedFile>> entry in byHash.entries) {
        if (entry.value.length < 2) {
          continue;
        }
        // Oldest first, so the suggested keeper is the likely original.
        final List<ScannedFile> copies = List<ScannedFile>.of(entry.value)
          ..sort(
            (ScannedFile a, ScannedFile b) =>
                a.dateModified.compareTo(b.dateModified),
          );
        duplicates.add(
          DuplicateGroup(
            hash: entry.key,
            files: List<ScannedFile>.unmodifiable(copies),
          ),
        );
      }
    }

    // Biggest saving first.
    duplicates.sort(
      (DuplicateGroup a, DuplicateGroup b) =>
          b.reclaimableBytes.compareTo(a.reclaimableBytes),
    );

    return DuplicateScanResult(
      groups: List<DuplicateGroup>.unmodifiable(duplicates),
      candidatesConsidered: candidateCount,
      filesHashed: hashed,
    );
  }
}
