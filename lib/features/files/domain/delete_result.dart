import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// One file that could not be deleted, and why.
class DeleteFailure {
  const DeleteFailure({required this.uri, required this.reason});

  final String uri;
  final String reason;
}

/// Outcome of one delete operation.
///
/// Deliberately reports partial success: Android can remove some files and
/// refuse others in the same batch, and the result screen must not overstate
/// what actually happened.
class DeleteResult {
  const DeleteResult({
    required this.deletedFiles,
    required this.failures,
    this.userCancelled = false,
  });

  const DeleteResult.cancelled()
    : deletedFiles = const <ScannedFile>[],
      failures = const <DeleteFailure>[],
      userCancelled = true;

  /// Files confirmed gone.
  final List<ScannedFile> deletedFiles;

  /// Files that survived, with a reason.
  final List<DeleteFailure> failures;

  /// True when the user declined the system confirmation.
  final bool userCancelled;

  int get deletedCount => deletedFiles.length;

  int get failureCount => failures.length;

  /// Space actually reclaimed. Only counts files confirmed deleted.
  int get freedBytes => deletedFiles.fold<int>(
    0,
    (int sum, ScannedFile file) => sum + file.sizeBytes,
  );

  bool get isCompleteSuccess =>
      !userCancelled && failures.isEmpty && deletedFiles.isNotEmpty;

  bool get isPartialSuccess => deletedFiles.isNotEmpty && failures.isNotEmpty;

  /// Nothing was removed, whether cancelled or blocked.
  bool get isFailure => deletedFiles.isEmpty;
}
