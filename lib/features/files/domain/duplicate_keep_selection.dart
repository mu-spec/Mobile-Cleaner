import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Which copy of each duplicate set the user wants to keep.
///
/// Keyed by group hash, valued by the URI of the kept copy. A group with no
/// entry falls back to [DuplicateGroup.original] — the oldest copy, which is
/// usually the one the camera wrote rather than a share-sheet duplicate.
///
/// The kept copy is the safety rail of the whole feature: every screen derives
/// its removable set from here, so no code path can ever offer to delete all
/// copies of a photo.
class DuplicateKeepSelection {
  const DuplicateKeepSelection([this._kept = const <String, String>{}]);

  const DuplicateKeepSelection.empty() : _kept = const <String, String>{};

  final Map<String, String> _kept;

  /// How many groups the user has changed away from the default keeper.
  int get overrideCount => _kept.length;

  /// URI of the copy kept for [group]. Null only for an empty group.
  String? keptUri(DuplicateGroup group) {
    final String? chosen = _kept[group.hash];
    if (chosen != null) {
      for (final ScannedFile file in group.files) {
        if (file.uri == chosen) {
          return chosen;
        }
      }
      // The chosen copy is gone (deleted or rescanned away); fall back.
    }
    return group.original?.uri;
  }

  /// The copy kept for [group], resolved to a file.
  ScannedFile? kept(DuplicateGroup group) {
    final String? uri = keptUri(group);
    if (uri == null) {
      return null;
    }
    for (final ScannedFile file in group.files) {
      if (file.uri == uri) {
        return file;
      }
    }
    return null;
  }

  bool isKept(DuplicateGroup group, ScannedFile file) =>
      keptUri(group) == file.uri;

  /// Records [file] as the copy to keep for [group].
  ///
  /// A file that is not part of the group is ignored rather than recorded, so
  /// a stale callback can never mark an unrelated photo as protected.
  DuplicateKeepSelection keep(DuplicateGroup group, ScannedFile file) {
    bool belongs = false;
    for (final ScannedFile candidate in group.files) {
      if (candidate.uri == file.uri) {
        belongs = true;
        break;
      }
    }
    if (!belongs) {
      return this;
    }
    final Map<String, String> next = Map<String, String>.of(_kept);
    next[group.hash] = file.uri;
    return DuplicateKeepSelection(next);
  }

  /// Every copy of [group] except the kept one.
  List<ScannedFile> removable(DuplicateGroup group) {
    final String? keep = keptUri(group);
    return <ScannedFile>[
      for (final ScannedFile file in group.files)
        if (file.uri != keep) file,
    ];
  }

  /// Every removable copy across [groups], for a select-all action.
  List<ScannedFile> removableAcross(Iterable<DuplicateGroup> groups) =>
      <ScannedFile>[
        for (final DuplicateGroup group in groups) ...removable(group),
      ];

  /// Bytes freed by deleting every removable copy in [groups].
  int reclaimableBytes(Iterable<DuplicateGroup> groups) {
    int total = 0;
    for (final DuplicateGroup group in groups) {
      total += group.fileBytes * removable(group).length;
    }
    return total;
  }

  /// Drops choices for groups that no longer exist, so the map cannot grow
  /// without bound across rescans.
  DuplicateKeepSelection prune(Iterable<DuplicateGroup> groups) {
    final Set<String> live = <String>{
      for (final DuplicateGroup group in groups) group.hash,
    };
    final Map<String, String> next = <String, String>{
      for (final MapEntry<String, String> entry in _kept.entries)
        if (live.contains(entry.key)) entry.key: entry.value,
    };
    return next.length == _kept.length
        ? this
        : DuplicateKeepSelection(next);
  }
}
