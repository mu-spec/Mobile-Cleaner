/// One recorded cleanup: when it happened, and what it removed.
///
/// Deliberately holds no file names, paths, or URIs. A history of exactly
/// which files someone deleted is far more sensitive than a count, and it is
/// not needed to answer the question this feature exists for — "how much have
/// I cleaned, and when".
class CleanupEntry {
  const CleanupEntry({
    required this.performedAt,
    required this.filesRemoved,
    required this.bytesRecovered,
  });

  /// When the cleanup completed.
  final DateTime performedAt;

  /// How many files Android confirmed were removed.
  final int filesRemoved;

  /// Space actually recovered. Only counts confirmed deletions.
  final int bytesRecovered;

  /// The calendar day this entry belongs to, with the time discarded.
  ///
  /// Grouping is by local calendar day, which is what a user means by "today".
  DateTime get day =>
      DateTime(performedAt.year, performedAt.month, performedAt.day);

  Map<String, Object?> toJson() => <String, Object?>{
    'at': performedAt.millisecondsSinceEpoch,
    'files': filesRemoved,
    'bytes': bytesRecovered,
  };

  /// Reads one stored entry, returning null when the record is unusable.
  ///
  /// A corrupt row is dropped rather than defaulted: a fabricated entry would
  /// silently inflate the user's lifetime total.
  static CleanupEntry? fromJson(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return null;
    }

    final int? millis = _readInt(raw['at']);
    if (millis == null || millis <= 0) {
      return null;
    }

    final int files = _readInt(raw['files']) ?? 0;
    final int bytes = _readInt(raw['bytes']) ?? 0;
    if (files <= 0 && bytes <= 0) {
      // A cleanup that removed nothing is not worth remembering.
      return null;
    }

    return CleanupEntry(
      performedAt: DateTime.fromMillisecondsSinceEpoch(millis),
      filesRemoved: files < 0 ? 0 : files,
      bytesRecovered: bytes < 0 ? 0 : bytes,
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}
