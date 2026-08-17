import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/history/data/cleanup_history_repository.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_entry.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_history.dart';

/// The stored cleanup log.
final FutureProvider<CleanupHistory> cleanupHistoryProvider =
    FutureProvider<CleanupHistory>((ref) {
      return ref.watch(cleanupHistoryRepositoryProvider).load();
    });

/// Records one completed cleanup, then refreshes the log.
///
/// Takes a [WidgetRef] because the only caller is the shared delete flow,
/// which runs in the widget layer. `Ref` and `WidgetRef` are distinct types,
/// so this must match the caller rather than the provider layer.
///
/// Failures are swallowed on purpose: history is a convenience, and a storage
/// error must never turn a successful deletion into an error the user sees.
Future<void> recordCleanup(
  WidgetRef ref, {
  required int filesRemoved,
  required int bytesRecovered,
  DateTime? at,
}) async {
  if (filesRemoved <= 0 && bytesRecovered <= 0) {
    return;
  }
  try {
    await ref
        .read(cleanupHistoryRepositoryProvider)
        .record(
          CleanupEntry(
            performedAt: at ?? DateTime.now(),
            filesRemoved: filesRemoved,
            bytesRecovered: bytesRecovered,
          ),
        );
    ref.invalidate(cleanupHistoryProvider);
  } on Exception {
    // Never surface: the files were still deleted.
  }
}
