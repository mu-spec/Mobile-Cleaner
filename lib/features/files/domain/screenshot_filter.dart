import 'package:mobile_cleaner/core/utils/file_age.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Age buckets offered by the Screenshot cleaner.
enum ScreenshotGroup {
  all('All screenshots', 'Every screenshot on the device', 0),
  days30('30+ days', 'Older than 30 days', 30),
  days90('90+ days', 'Older than 90 days', 90);

  const ScreenshotGroup(this.label, this.description, this.minDays);

  final String label;
  final String description;

  /// Inclusive lower bound in days. Zero means no age restriction.
  final int minDays;

  static const ScreenshotGroup defaultGroup = ScreenshotGroup.all;

  /// True when [modified] falls inside this bucket.
  bool matches(DateTime modified, {DateTime? now}) {
    if (minDays == 0) {
      return true;
    }
    // An unreadable timestamp is never treated as old.
    if (FileAge.isUnknown(modified)) {
      return false;
    }
    return FileAge.inDays(modified, now: now) >= minDays;
  }
}

/// Recognises screenshots among scanned images.
///
/// Android has no "screenshot" media type, so detection is heuristic. Both
/// signals below are checked, because neither alone is reliable: a user can
/// move screenshots out of the standard folder, and some apps save unrelated
/// images into it.
abstract final class ScreenshotDetector {
  /// Folder names vendors use. Matched case-insensitively against any path
  /// segment, so `Pictures/Screenshots` and `DCIM/Screenshots` both count.
  static const List<String> folderNames = <String>[
    'screenshot',
    'screenshots',
    'screen shots',
    'screencapture',
    'screen captures',
  ];

  /// Filename prefixes vendors use, e.g. `Screenshot_20260115-101500.png`.
  static const List<String> namePrefixes = <String>[
    'screenshot',
    'screen_shot',
    'screen-shot',
    'screnshot',
    'scr_',
  ];

  /// True when [file] looks like a screenshot.
  ///
  /// Only images qualify: a video recorded in a Screenshots folder is a screen
  /// recording, not a screenshot, and deleting it under this tool would
  /// surprise the user.
  static bool isScreenshot(ScannedFile file) {
    if (!_isImage(file)) {
      return false;
    }
    return _inScreenshotFolder(file) || _hasScreenshotName(file);
  }

  static bool _isImage(ScannedFile file) {
    if (file.category == FileCategory.images) {
      return true;
    }
    return file.mimeType?.toLowerCase().startsWith('image/') ?? false;
  }

  static bool _inScreenshotFolder(ScannedFile file) {
    final String source = (file.relativePath?.isNotEmpty ?? false)
        ? file.relativePath!
        : file.path;
    if (source.isEmpty) {
      return false;
    }

    // Compare whole segments so a folder named "MyScreenshotsBackup" does not
    // match, while "DCIM/Screenshots/" does.
    final List<String> segments = source
        .toLowerCase()
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .toList();

    // Drop a trailing file name so it cannot be mistaken for a folder.
    if (segments.isNotEmpty && segments.last == file.name.toLowerCase()) {
      segments.removeLast();
    }

    return segments.any(folderNames.contains);
  }

  static bool _hasScreenshotName(ScannedFile file) {
    final String name = file.name.toLowerCase();
    return namePrefixes.any(name.startsWith);
  }
}
