import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_entry.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the cleanup log on this device.
///
/// Local only. Nothing is uploaded, and the log holds no file names — just a
/// timestamp, a count, and a size per cleanup.
abstract interface class CleanupHistoryRepository {
  Future<CleanupHistory> load();

  /// Appends one cleanup and returns the updated history.
  Future<CleanupHistory> record(CleanupEntry entry);

  Future<void> clear();
}

final Provider<CleanupHistoryRepository> cleanupHistoryRepositoryProvider =
    Provider<CleanupHistoryRepository>(
      (ref) => const PreferencesCleanupHistoryRepository(),
    );

class PreferencesCleanupHistoryRepository
    implements CleanupHistoryRepository {
  const PreferencesCleanupHistoryRepository();

  static const String _key = 'cleanup_history';

  /// Cap on stored cleanups.
  ///
  /// The log lives in SharedPreferences, which is loaded into memory whole, so
  /// it must not grow without bound. 200 entries is far more than anyone will
  /// review and still trivially small on disk.
  static const int maxEntries = 200;

  @override
  Future<CleanupHistory> load() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    return decode(preferences.getString(_key));
  }

  @override
  Future<CleanupHistory> record(CleanupEntry entry) async {
    // A cleanup that removed nothing is not worth a row.
    if (entry.filesRemoved <= 0 && entry.bytesRecovered <= 0) {
      return load();
    }

    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final CleanupHistory existing = decode(preferences.getString(_key));

    final CleanupHistory updated = CleanupHistory.from(<CleanupEntry>[
      entry,
      ...existing.entries,
    ]);

    // Newest first, so trimming drops the oldest.
    final List<CleanupEntry> capped = updated.entries.length > maxEntries
        ? updated.entries.sublist(0, maxEntries)
        : updated.entries;

    await preferences.setString(_key, encode(capped));
    return CleanupHistory.from(capped);
  }

  @override
  Future<void> clear() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }

  /// Serialises entries to a JSON array string.
  ///
  /// Exposed for testing.
  static String encode(List<CleanupEntry> entries) => jsonEncode(
    <Map<String, Object?>>[
      for (final CleanupEntry entry in entries) entry.toJson(),
    ],
  );

  /// Parses stored JSON, dropping unusable rows.
  ///
  /// Any decode failure yields an empty history rather than throwing. Losing
  /// a corrupt log is a minor annoyance; a crash on every launch is not, and
  /// history is not data the app can fail to start without.
  ///
  /// Exposed for testing.
  static CleanupHistory decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return CleanupHistory.empty;
    }

    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! List<Object?>) {
        return CleanupHistory.empty;
      }
      final List<CleanupEntry> entries = <CleanupEntry>[];
      for (final Object? row in parsed) {
        final CleanupEntry? entry = CleanupEntry.fromJson(row);
        if (entry != null) {
          entries.add(entry);
        }
      }
      return CleanupHistory.from(entries);
    } on FormatException {
      return CleanupHistory.empty;
    }
  }
}
