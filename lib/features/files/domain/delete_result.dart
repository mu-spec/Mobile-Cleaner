import 'package:phone_storage_cleaner/features/files/domain/scanned_file.dart';

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
    this.skippedUris = const <String>[],
    this.confirmedBytesByUri,
  });

  const DeleteResult.cancelled()
    : deletedFiles = const <ScannedFile>[],
      failures = const <DeleteFailure>[],
      userCancelled = true,
      skippedUris = const <String>[],
      confirmedBytesByUri = null;

  /// Files confirmed gone.
  final List<ScannedFile> deletedFiles;

  /// Files that survived, with a reason.
  final List<DeleteFailure> failures;

  /// True when the user declined the system confirmation.
  final bool userCancelled;

  /// Already absent/no row removed: handled but never claimed as cleaned.
  final List<String> skippedUris;

  /// Native pre-delete logical sizes, only for confirmed removals. Null is
  /// legacy/custom-repository compatibility; an empty map means unknown size.
  final Map<String, int>? confirmedBytesByUri;
  int get unmeasuredDeletedCount => confirmedBytesByUri == null
      ? 0
      : deletedFiles
            .where((file) => !confirmedBytesByUri!.containsKey(file.uri))
            .length;

  int get deletedCount => deletedFiles.length;

  int get failureCount => failures.length;

  /// Space actually reclaimed. Only counts files confirmed deleted.
  int get freedBytes => deletedFiles.fold<int>(
    0,
    (int sum, ScannedFile file) =>
        sum +
        (confirmedBytesByUri == null
            ? file.sizeBytes
            : confirmedBytesByUri![file.uri] ?? 0),
  );

  bool get isCompleteSuccess =>
      !userCancelled &&
      failures.isEmpty &&
      skippedUris.isEmpty &&
      deletedFiles.isNotEmpty;

  bool get isPartialSuccess =>
      deletedFiles.isNotEmpty &&
      (failures.isNotEmpty || skippedUris.isNotEmpty || userCancelled);

  /// Nothing was removed, whether cancelled or blocked.
  bool get isFailure => deletedFiles.isEmpty;
}
