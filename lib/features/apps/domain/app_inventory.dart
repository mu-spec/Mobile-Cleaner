import 'package:mobile_cleaner/features/apps/domain/installed_app.dart';

/// Orderings offered by the Apps section.
enum AppSort {
  largest('Largest', 'Biggest apps first'),
  name('Name', 'Alphabetical'),
  recentlyUpdated('Updated', 'Most recently updated first'),
  oldest('Oldest', 'Installed longest ago first');

  const AppSort(this.label, this.description);

  final String label;
  final String description;

  static const AppSort defaultSort = AppSort.largest;

  /// Comparator for this ordering.
  ///
  /// Every comparator falls back to the package name, so equal sizes or
  /// missing dates still produce a stable order rather than one that shuffles
  /// between rebuilds.
  Comparator<InstalledApp> get comparator {
    int byPackage(InstalledApp a, InstalledApp b) =>
        a.packageName.compareTo(b.packageName);

    int byName(InstalledApp a, InstalledApp b) {
      final int result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return result != 0 ? result : byPackage(a, b);
    }

    // Apps with no date sort last, never first: an unknown date is not the
    // same as a very old one.
    int byDate(DateTime? a, DateTime? b, InstalledApp x, InstalledApp y,
        {required bool newestFirst}) {
      if (a == null && b == null) {
        return byName(x, y);
      }
      if (a == null) {
        return 1;
      }
      if (b == null) {
        return -1;
      }
      final int result = newestFirst ? b.compareTo(a) : a.compareTo(b);
      return result != 0 ? result : byName(x, y);
    }

    return switch (this) {
      AppSort.largest => (InstalledApp a, InstalledApp b) {
        final int result = b.bestKnownBytes.compareTo(a.bestKnownBytes);
        return result != 0 ? result : byName(a, b);
      },
      AppSort.name => byName,
      AppSort.recentlyUpdated => (InstalledApp a, InstalledApp b) =>
          byDate(a.updatedAt, b.updatedAt, a, b, newestFirst: true),
      AppSort.oldest => (InstalledApp a, InstalledApp b) =>
          byDate(a.installedAt, b.installedAt, a, b, newestFirst: false),
    };
  }
}

/// Which apps to list.
enum AppFilter {
  /// Apps the user installed. The default: these are the ones that can
  /// realistically be uninstalled.
  userApps('Installed', 'Apps you installed'),

  /// Everything with a launcher icon, including preloaded system apps.
  all('All', 'Including system apps');

  const AppFilter(this.label, this.description);

  final String label;
  final String description;

  static const AppFilter defaultFilter = AppFilter.userApps;

  bool matches(InstalledApp app) =>
      this == AppFilter.all || !app.isSystemApp;
}

/// Everything the Apps section needs to draw itself.
class AppInventory {
  const AppInventory({
    required this.apps,
    required this.sort,
    required this.filter,
    this.hasUsageAccess = false,
    this.sizeDetailSupported = true,
    this.hiddenSystemAppCount = 0,
  });

  /// Builds an inventory from a raw app list.
  factory AppInventory.from(
    Iterable<InstalledApp> source, {
    AppSort sort = AppSort.defaultSort,
    AppFilter filter = AppFilter.defaultFilter,
    bool hasUsageAccess = false,
    bool sizeDetailSupported = true,
  }) {
    final Set<String> seen = <String>{};
    final List<InstalledApp> matches = <InstalledApp>[];
    int hiddenSystem = 0;

    for (final InstalledApp app in source) {
      if (!seen.add(app.packageName)) {
        continue;
      }
      if (!filter.matches(app)) {
        hiddenSystem++;
        continue;
      }
      matches.add(app);
    }

    matches.sort(sort.comparator);

    return AppInventory(
      apps: List<InstalledApp>.unmodifiable(matches),
      sort: sort,
      filter: filter,
      hasUsageAccess: hasUsageAccess,
      sizeDetailSupported: sizeDetailSupported,
      hiddenSystemAppCount: hiddenSystem,
    );
  }

  static const AppInventory empty = AppInventory(
    apps: <InstalledApp>[],
    sort: AppSort.largest,
    filter: AppFilter.userApps,
  );

  /// Visible apps in [sort] order.
  final List<InstalledApp> apps;

  final AppSort sort;
  final AppFilter filter;

  /// Whether Android is giving full app + data + cache figures.
  final bool hasUsageAccess;

  /// False below Android 8, where no detailed size API exists at all.
  ///
  /// Distinguished from [hasUsageAccess] so the UI does not offer a permission
  /// prompt that could not help on that device.
  final bool sizeDetailSupported;

  /// System apps excluded by the current filter.
  final int hiddenSystemAppCount;

  int get appCount => apps.length;

  bool get isEmpty => apps.isEmpty;

  /// Combined size using the best figure known for each app.
  int get totalBytes => apps.fold<int>(
    0,
    (int sum, InstalledApp app) => sum + app.bestKnownBytes,
  );

  /// Combined cache, when Usage Access allows it to be read.
  int get totalCacheBytes => apps.fold<int>(
    0,
    (int sum, InstalledApp app) => sum + (app.cacheBytes ?? 0),
  );

  /// True when granting Usage Access would actually improve the figures.
  ///
  /// False on devices where the API does not exist, so the UI never nags for a
  /// permission that would change nothing.
  bool get canImproveSizes => sizeDetailSupported && !hasUsageAccess;

  /// The biggest app, or null when the list is empty.
  InstalledApp? get largestApp {
    if (apps.isEmpty) {
      return null;
    }
    return apps.reduce(
      (InstalledApp a, InstalledApp b) =>
          b.bestKnownBytes > a.bestKnownBytes ? b : a,
    );
  }

  /// Same inventory without [packageName], for use after an uninstall.
  AppInventory withoutPackage(String packageName) {
    final List<InstalledApp> remaining = <InstalledApp>[
      for (final InstalledApp app in apps)
        if (app.packageName != packageName) app,
    ];
    if (remaining.length == apps.length) {
      return this;
    }
    return AppInventory(
      apps: List<InstalledApp>.unmodifiable(remaining),
      sort: sort,
      filter: filter,
      hasUsageAccess: hasUsageAccess,
      sizeDetailSupported: sizeDetailSupported,
      hiddenSystemAppCount: hiddenSystemAppCount,
    );
  }
}
