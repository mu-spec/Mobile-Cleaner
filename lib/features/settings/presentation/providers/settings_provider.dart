import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/settings/data/settings_repository.dart';
import 'package:mobile_cleaner/features/settings/domain/app_settings.dart';

/// The stored preferences.
///
/// A plain [FutureProvider] rather than a Notifier: the codebase standardises
/// on `Provider` and `FutureProvider`, which are the patterns already proven
/// to compile against Riverpod 3 here. Writes go through [saveSettings], which
/// invalidates this so every watcher rebuilds.
final FutureProvider<AppSettings> settingsProvider =
    FutureProvider<AppSettings>((ref) {
      return ref.watch(settingsRepositoryProvider).load();
    });

/// Persists [next] and refreshes every watcher.
///
/// Takes a [WidgetRef] because the callers are Settings widgets. `Ref` and
/// `WidgetRef` are distinct types, so this must match the caller.
Future<void> saveSettings(WidgetRef ref, AppSettings next) async {
  await ref.read(settingsRepositoryProvider).save(next);
  ref.invalidate(settingsProvider);
}
