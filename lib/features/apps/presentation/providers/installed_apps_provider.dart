import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/features/apps/data/installed_apps_repository.dart';
import 'package:phone_storage_cleaner/features/apps/domain/app_inventory.dart';

/// Null: rely on the native read-time check. False: hide cached details while
/// a foreground special-access check is pending or has denied access.
final appsUsageAuthorizationProvider = StateProvider<bool?>((ref) => null);

/// One read of the installed-app list.
///
/// Reading is a single platform call that rasterises every icon, so it is done
/// once and re-sorted in memory rather than repeated per sort or filter.
final FutureProvider<InstalledAppsSnapshot> installedAppsProvider =
    FutureProvider<InstalledAppsSnapshot>((ref) {
      return observeScan(ref, 'discovery:apps', () async {
        return ref.watch(installedAppsRepositoryProvider).getInstalledApps();
      }, numeric: true);
    });

/// Sort and filter applied to one cached read.
final appInventoryProvider =
    FutureProvider.family<AppInventory, (AppSort, AppFilter)>((
      ref,
      (AppSort, AppFilter) options,
    ) async {
      final authorization = ref.watch(appsUsageAuthorizationProvider);
      return observeScan(ref, 'apps', () async {
        final InstalledAppsSnapshot snapshot = await scanDependency(
          ref,
          'discovery:apps',
          ref.watch(installedAppsProvider.future),
        );

        return AppInventory.from(
          authorization == false ||
                  !snapshot.hasUsageAccess ||
                  !snapshot.sizeDetailSupported
              ? snapshot.apps.map((app) => app.withoutSizeDetails())
              : snapshot.apps,
          sort: options.$1,
          filter: options.$2,
          hasUsageAccess: authorization != false && snapshot.hasUsageAccess,
          sizeDetailSupported: snapshot.sizeDetailSupported,
        );
      }, numeric: true);
    });

/// Re-reads the installed app list.
///
/// Called after returning from an uninstall or from Usage Access settings,
/// where the answer can only be learned by looking again.
void refreshInstalledApps(WidgetRef ref) {
  ref.invalidate(installedAppsProvider);
}
