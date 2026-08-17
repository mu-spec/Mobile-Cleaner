import 'package:mobile_cleaner/features/history/domain/cleanup_entry.dart';

/// Every cleanup recorded on one calendar day, combined.
///
/// The screen lists days, not individual deletions: three cleanups this
/// afternoon read as one line — "Today · 1.8 GB cleaned" — which is how a
/// person thinks about it.
class CleanupDay {
  const CleanupDay({
    required this.day,
    required this.filesRemoved,
    required this.bytesRecovered,
    required this.cleanupCount,
  });

  final DateTime day;
  final int filesRemoved;
  final int bytesRecovered;

  /// How many separate cleanups happened that day.
  final int cleanupCount;
}

/// The stored cleanup log, newest first.
class CleanupHistory {
  const CleanupHistory({required this.entries});

  static const CleanupHistory empty = CleanupHistory(
    entries: <CleanupEntry>[],
  );

  /// Builds a history, ordering newest first.
  factory CleanupHistory.from(Iterable<CleanupEntry> source) {
    final List<CleanupEntry> sorted = List<CleanupEntry>.of(source)
      ..sort(
        (CleanupEntry a, CleanupEntry b) =>
            b.performedAt.compareTo(a.performedAt),
      );
    return CleanupHistory(entries: List<CleanupEntry>.unmodifiable(sorted));
  }

  /// Individual cleanups, newest first.
  final List<CleanupEntry> entries;

  bool get isEmpty => entries.isEmpty;

  int get cleanupCount => entries.length;

  /// Files removed across every recorded cleanup.
  int get totalFilesRemoved => entries.fold<int>(
    0,
    (int sum, CleanupEntry entry) => sum + entry.filesRemoved,
  );

  /// Space recovered across every recorded cleanup.
  ///
  /// A lifetime figure, not current free space: the two differ as soon as
  /// anything new is saved, and conflating them would be misleading.
  int get totalBytesRecovered => entries.fold<int>(
    0,
    (int sum, CleanupEntry entry) => sum + entry.bytesRecovered,
  );

  /// The most recent cleanup, or null when nothing is recorded.
  CleanupEntry? get mostRecent => entries.isEmpty ? null : entries.first;

  /// Entries combined per calendar day, newest day first.
  List<CleanupDay> get byDay {
    final Map<DateTime, List<CleanupEntry>> grouped =
        <DateTime, List<CleanupEntry>>{};
    for (final CleanupEntry entry in entries) {
      grouped.putIfAbsent(entry.day, () => <CleanupEntry>[]).add(entry);
    }

    final List<DateTime> days = grouped.keys.toList()
      ..sort((DateTime a, DateTime b) => b.compareTo(a));

    return <CleanupDay>[
      for (final DateTime day in days)
        CleanupDay(
          day: day,
          filesRemoved: grouped[day]!.fold<int>(
            0,
            (int sum, CleanupEntry entry) => sum + entry.filesRemoved,
          ),
          bytesRecovered: grouped[day]!.fold<int>(
            0,
            (int sum, CleanupEntry entry) => sum + entry.bytesRecovered,
          ),
          cleanupCount: grouped[day]!.length,
        ),
    ];
  }

  /// Space recovered in the last [days] days, inclusive of today.
  int bytesRecoveredWithin(int days, {DateTime? now}) {
    final DateTime reference = now ?? DateTime.now();
    final DateTime cutoff = DateTime(
      reference.year,
      reference.month,
      reference.day,
    ).subtract(Duration(days: days - 1));

    return entries
        .where((CleanupEntry entry) => !entry.day.isBefore(cutoff))
        .fold<int>(
          0,
          (int sum, CleanupEntry entry) => sum + entry.bytesRecovered,
        );
  }
}
