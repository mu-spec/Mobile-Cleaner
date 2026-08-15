/// Shared age arithmetic for files.
///
/// Comparisons happen at day boundaries rather than on raw durations, so a
/// file saved at 23:59 is treated the same as one saved at 00:01 that day.
abstract final class FileAge {
  /// Whole days between [modified] and [now], never negative.
  ///
  /// A future timestamp — possible with a bad device clock or a file copied
  /// across timezones — clamps to 0 rather than going negative.
  static int inDays(DateTime modified, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime startOfToday = DateTime(
      reference.year,
      reference.month,
      reference.day,
    );
    final DateTime startOfModified = DateTime(
      modified.year,
      modified.month,
      modified.day,
    );
    final int days = startOfToday.difference(startOfModified).inDays;
    return days < 0 ? 0 : days;
  }

  /// True when the platform could not read a timestamp.
  ///
  /// Such a file must never be reported as ancient and offered for deletion.
  static bool isUnknown(DateTime modified) =>
      modified.millisecondsSinceEpoch == 0;
}
