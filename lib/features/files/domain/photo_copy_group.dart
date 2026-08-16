import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// A set of photos the user is offered a choice between, keeping one.
///
/// Implemented by both `DuplicateGroup` (byte-identical) and
/// `SimilarPhotoGroup` (visually alike) so that
/// [DuplicateKeepSelection](duplicate_keep_selection.dart) — and therefore the
/// "one copy is always kept" safety rule — is shared rather than reimplemented
/// per feature.
abstract interface class PhotoCopyGroup {
  /// Stable identity for this group, used to remember the user's choice.
  String get groupKey;

  /// Every member of the group.
  List<ScannedFile> get files;

  /// The member suggested for keeping when the user has not chosen.
  ScannedFile? get original;
}
