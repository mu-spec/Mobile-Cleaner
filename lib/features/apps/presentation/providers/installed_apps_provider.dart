import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/apps/data/installed_apps_repository.dart';
import 'package:mobile_cleaner/features/apps/domain/app_inventory.dart';

/// One read of the installed-app list.
///
/// Reading is a single platform call that rasterises every icon, so it is done
/// once and re-sorted in memory rather than repeated per sort or filter.
final FutureProvider<InstalledAppsSnapshot> installedAppsProvider =
    FutureProvider<InstalledAppsSnapshot>((ref) {
      return ref.watch(installedAppsRepositoryProvider).getInstalledApps();
    });

/// Sort and filter applied to one cached read.
final appInventoryProvider =
    FutureProvider.family<AppInventory, (AppSort, AppFilter)>((
      ref,
      (AppSort, AppFilter) options,
    ) async {
      final InstalledAppsSnapshot snapshot = await ref.watch(
        installedAppsProvider.future,
      );

      return AppInventory.from(
        snapshot.apps,
        sort: options.$1,
        filter: options.$2,
        hasUsageAccess: snapshot.hasUsageAccess,
        sizeDetailSupported: snapshot.sizeDetailSupported,
      );
    });

/// Re-reads the installed app list.
///
/// Called after returning from an uninstall or from Usage Access settings,
/// where the answer can only be learned by looking again.
void refreshInstalledApps(WidgetRef ref) {
  ref.invalidate(installedAppsProvider);
}
