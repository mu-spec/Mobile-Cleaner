/// Age thresholds offered by the Downloads cleaner.
///
/// A download matches when it has not been modified for at least [minDays].
enum DownloadAgeFilter {
  days30('30+ days', '30 days', 30),
  days90('90+ days', '90 days', 90),
  months6('6+ months', '6 months', 182),
  year1('1+ year', '1 year', 365);

  const DownloadAgeFilter(this.label, this.threshold, this.minDays);

  /// Chip label, e.g. `30+ days`.
  final String label;

  /// Bare threshold used in sentences, e.g. `30 days`.
  final String threshold;

  /// Inclusive lower bound in days since the file was last modified.
  final int minDays;

  /// The most permissive threshold, used for the initial view.
  static const DownloadAgeFilter defaultFilter = DownloadAgeFilter.days30;

  /// Smallest age across every filter.
  ///
  /// Every other threshold is a subset of this one, so the tool scans once
  /// and narrows in memory.
  static int get lowestBoundDays => DownloadAgeFilter.days30.minDays;

  /// Whole days between [modified] and [now], never negative.
  ///
  /// Compared at day boundaries so a file saved earlier today reads as 0 days
  /// old regardless of the clock time.
  static int ageInDays(DateTime modified, {DateTime? now}) {
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

  /// True when [modified] is at least [minDays] old.
  bool matches(DateTime modified, {DateTime? now}) {
    // An unknown timestamp must never be reported as ancient and offered
    // for deletion, so it is excluded from every age filter.
    if (modified.millisecondsSinceEpoch == 0) {
      return false;
    }
    return ageInDays(modified, now: now) >= minDays;
  }
}
