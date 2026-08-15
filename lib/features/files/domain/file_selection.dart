import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// An immutable set of selected files, keyed by URI.
///
/// Selection is tracked by URI rather than by object so it survives a rescan
/// that returns freshly constructed [ScannedFile] instances.
class FileSelection {
  const FileSelection(this._selected);

  const FileSelection.empty() : _selected = const <String, ScannedFile>{};

  final Map<String, ScannedFile> _selected;

  Iterable<ScannedFile> get files => _selected.values;

  Set<String> get uris => _selected.keys.toSet();

  int get count => _selected.length;

  bool get isEmpty => _selected.isEmpty;

  bool get isNotEmpty => _selected.isNotEmpty;

  /// Combined size of every selected file.
  int get totalBytes => _selected.values.fold<int>(
    0,
    (int sum, ScannedFile file) => sum + file.sizeBytes,
  );

  bool contains(ScannedFile file) => _selected.containsKey(file.uri);

  FileSelection toggle(ScannedFile file) {
    final Map<String, ScannedFile> next = Map<String, ScannedFile>.of(
      _selected,
    );
    if (next.containsKey(file.uri)) {
      next.remove(file.uri);
    } else {
      next[file.uri] = file;
    }
    return FileSelection(next);
  }

  FileSelection selectAll(Iterable<ScannedFile> files) {
    final Map<String, ScannedFile> next = Map<String, ScannedFile>.of(
      _selected,
    );
    for (final ScannedFile file in files) {
      next[file.uri] = file;
    }
    return FileSelection(next);
  }

  FileSelection deselectAll(Iterable<ScannedFile> files) {
    final Map<String, ScannedFile> next = Map<String, ScannedFile>.of(
      _selected,
    );
    for (final ScannedFile file in files) {
      next.remove(file.uri);
    }
    return FileSelection(next);
  }

  FileSelection clear() => const FileSelection.empty();

  /// Drops selections that are no longer present in [visible].
  ///
  /// Called when the filter narrows, so the action bar can never offer to act
  /// on a file the user can no longer see.
  FileSelection retainWhereVisible(Iterable<ScannedFile> visible) {
    final Set<String> allowed = visible
        .map((ScannedFile file) => file.uri)
        .toSet();
    final Map<String, ScannedFile> next = <String, ScannedFile>{
      for (final MapEntry<String, ScannedFile> entry in _selected.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
    return next.length == _selected.length
        ? this
        : FileSelection(next);
  }

  /// True when every file in [files] is selected. Empty input is not "all".
  bool containsAll(Iterable<ScannedFile> files) {
    bool sawAny = false;
    for (final ScannedFile file in files) {
      sawAny = true;
      if (!_selected.containsKey(file.uri)) {
        return false;
      }
    }
    return sawAny;
  }
}
