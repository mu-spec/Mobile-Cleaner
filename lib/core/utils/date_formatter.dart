/// Shared human-readable date formatting used across the app.
abstract final class DateFormatter {
  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Formats a date as `04 Aug 2026`, or `Unknown date` when absent.
  static String format(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) {
      return 'Unknown date';
    }
    final String day = date.day.toString().padLeft(2, '0');
    return '$day ${_months[date.month - 1]} ${date.year}';
  }

  /// Formats a date relative to [now], e.g. `Today`, `Yesterday`, `3 days ago`.
  ///
  /// Falls back to the absolute date beyond a month so older files stay
  /// unambiguous.
  static String relative(DateTime date, {DateTime? now}) {
    if (date.millisecondsSinceEpoch == 0) {
      return 'Unknown date';
    }

    final DateTime reference = now ?? DateTime.now();
    final DateTime startOfToday = DateTime(
      reference.year,
      reference.month,
      reference.day,
    );
    final DateTime startOfDate = DateTime(date.year, date.month, date.day);
    final int days = startOfToday.difference(startOfDate).inDays;

    if (days < 0) {
      return format(date);
    }
    if (days == 0) {
      return 'Today';
    }
    if (days == 1) {
      return 'Yesterday';
    }
    if (days < 30) {
      return '$days days ago';
    }
    return format(date);
  }
}
