import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// A set of files proven byte-identical by content hash.
class DuplicateGroup {
  const DuplicateGroup({required this.hash, required this.files});

  /// The shared content hash.
  final String hash;

  /// Every copy, oldest first, so [original] is the one most likely kept.
  final List<ScannedFile> files;

  int get copyCount => files.length;

  /// Size of a single copy. Every file in the group has the same size.
  int get fileBytes => files.isEmpty ? 0 : files.first.sizeBytes;

  /// Total space the group occupies, all copies included.
  int get totalBytes => fileBytes * copyCount;

  /// Space freed by keeping one copy and deleting the rest.
  ///
  /// This, not [totalBytes], is what the user can actually recover: deleting
  /// every copy of a file is data loss, not cleaning.
  int get reclaimableBytes => files.isEmpty ? 0 : fileBytes * (copyCount - 1);

  /// The copy suggested for keeping: the oldest, which is usually the
  /// original rather than a re-download or a share-sheet copy.
  ScannedFile? get original => files.isEmpty ? null : files.first;

  /// The copies safe to remove once [original] is kept.
  List<ScannedFile> get duplicates =>
      files.length <= 1 ? const <ScannedFile>[] : files.sublist(1);
}

/// Outcome of one duplicate scan.
class DuplicateScanResult {
  const DuplicateScanResult({
    required this.groups,
    this.candidatesConsidered = 0,
    this.filesHashed = 0,
  });

  static const DuplicateScanResult empty = DuplicateScanResult(
    groups: <DuplicateGroup>[],
  );

  /// Duplicate sets, biggest reclaimable saving first.
  final List<DuplicateGroup> groups;

  /// How many files shared a size and so were worth hashing. Diagnostic.
  final int candidatesConsidered;

  /// How many files were actually hashed. Diagnostic.
  final int filesHashed;

  int get groupCount => groups.length;

  /// Total number of removable copies across every group.
  int get duplicateCount =>
      groups.fold<int>(0, (int sum, DuplicateGroup g) => sum + g.copyCount - 1);

  /// Total space recoverable by keeping one copy of each group.
  int get reclaimableBytes => groups.fold<int>(
    0,
    (int sum, DuplicateGroup g) => sum + g.reclaimableBytes,
  );

  bool get isEmpty => groups.isEmpty;

  /// Every removable copy, for a select-all action.
  List<ScannedFile> get allDuplicates => <ScannedFile>[
    for (final DuplicateGroup group in groups) ...group.duplicates,
  ];
}
