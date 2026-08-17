import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/apps/data/installed_apps_repository.dart';
import 'package:mobile_cleaner/features/apps/domain/app_inventory.dart';
import 'package:mobile_cleaner/features/apps/domain/installed_app.dart';
import 'package:mobile_cleaner/features/apps/presentation/screens/apps_screen.dart';

const int _mib = 1024 * 1024;

InstalledApp _app({
  required String packageName,
  required String name,
  int apkBytes = 20 * _mib,
  int? appBytes,
  int? dataBytes,
  int? cacheBytes,
  bool isSystemApp = false,
  bool canOpen = true,
  DateTime? installedAt,
  DateTime? updatedAt,
}) => InstalledApp(
  packageName: packageName,
  name: name,
  apkBytes: apkBytes,
  appBytes: appBytes,
  dataBytes: dataBytes,
  cacheBytes: cacheBytes,
  isSystemApp: isSystemApp,
  canOpen: canOpen,
  installedAt: installedAt,
  updatedAt: updatedAt,
);

/// Three user apps and one system app, with distinct sizes and dates.
List<InstalledApp> _fixture() => <InstalledApp>[
  _app(
    packageName: 'com.chat',
    name: 'Chatter',
    apkBytes: 40 * _mib,
    appBytes: 40 * _mib,
    dataBytes: 900 * _mib,
    cacheBytes: 60 * _mib,
    installedAt: DateTime(2024, 1, 10),
    updatedAt: DateTime(2026, 2, 1),
  ),
  _app(
    packageName: 'com.game',
    name: 'Arcade',
    apkBytes: 300 * _mib,
    appBytes: 300 * _mib,
    dataBytes: 100 * _mib,
    cacheBytes: 0,
    installedAt: DateTime(2023, 5, 1),
    updatedAt: DateTime(2025, 12, 1),
  ),
  _app(
    packageName: 'com.notes',
    name: 'Notepad',
    apkBytes: 10 * _mib,
    appBytes: 10 * _mib,
    dataBytes: 5 * _mib,
    cacheBytes: 1 * _mib,
    installedAt: DateTime(2025, 8, 1),
    updatedAt: DateTime(2026, 1, 1),
  ),
  _app(
    packageName: 'com.android.systemthing',
    name: 'System Thing',
    apkBytes: 80 * _mib,
    appBytes: 80 * _mib,
    dataBytes: 20 * _mib,
    isSystemApp: true,
    canOpen: false,
    installedAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2026, 3, 1),
  ),
];

class _StubApps implements InstalledAppsRepository {
  _StubApps({
    List<InstalledApp>? apps,
    this.hasAccess = true,
    this.detailSupported = true,
    this.actionsSucceed = true,
    this.stillInstalled = true,
  }) : apps = apps ?? _fixture();

  final List<InstalledApp> apps;
  final bool hasAccess;
  final bool detailSupported;
  final bool actionsSucceed;
  bool stillInstalled;

  int reads = 0;
  final List<String> opened = <String>[];
  final List<String> settingsOpened = <String>[];
  final List<String> uninstallRequested = <String>[];
  int usageSettingsOpened = 0;

  @override
  Future<InstalledAppsSnapshot> getInstalledApps({
    bool includeIcons = true,
  }) async {
    reads++;
    return InstalledAppsSnapshot(
      apps: apps,
      hasUsageAccess: hasAccess,
      sizeDetailSupported: detailSupported,
    );
  }

  @override
  Future<bool> hasUsageAccess() async => hasAccess;

  @override
  Future<bool> openUsageAccessSettings() async {
    usageSettingsOpened++;
    return actionsSucceed;
  }

  @override
  Future<bool> openApp(String packageName) async {
    opened.add(packageName);
    return actionsSucceed;
  }

  @override
  Future<bool> openAppSettings(String packageName) async {
    settingsOpened.add(packageName);
    return actionsSucceed;
  }

  @override
  Future<bool> requestUninstall(String packageName) async {
    uninstallRequested.add(packageName);
    return actionsSucceed;
  }

  @override
  Future<bool> isInstalled(String packageName) async => stillInstalled;
}

Future<_StubApps> _pumpApps(
  WidgetTester tester, {
  _StubApps? repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubApps repo = repository ?? _StubApps();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [installedAppsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: AppsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

List<String> _names(AppSort sort, {AppFilter filter = AppFilter.userApps}) =>
    AppInventory.from(_fixture(), sort: sort, filter: filter)
        .apps
        .map((InstalledApp a) => a.name)
        .toList();

void main() {
  group('InstalledApp parsing', () {
    test('reads a well-formed platform row', () {
      final InstalledApp? app = InstalledApp.fromPlatformMap(
        <Object?, Object?>{
          'packageName': 'com.example',
          'name': 'Example',
          'apkBytes': 30 * _mib,
          'appBytes': 30 * _mib,
          'dataBytes': 70 * _mib,
          'cacheBytes': 5 * _mib,
          'isSystemApp': false,
          'canOpen': true,
          'updatedAtMillis': 1700000000000,
        },
      );

      expect(app, isNotNull);
      expect(app!.name, 'Example');
      expect(app.hasDetailedSize, isTrue);
      expect(app.totalBytes, 105 * _mib);
      expect(app.updatedAt, isNotNull);
    });

    test('a row without a package name is dropped', () {
      expect(
        InstalledApp.fromPlatformMap(<Object?, Object?>{'name': 'Ghost'}),
        isNull,
      );
    });

    test('a missing label falls back to the package name', () {
      final InstalledApp? app = InstalledApp.fromPlatformMap(
        <Object?, Object?>{'packageName': 'com.silent', 'apkBytes': 100},
      );
      // Listing it under its package beats hiding it.
      expect(app?.name, 'com.silent');
    });

    test('total is null rather than partial when data is unknown', () {
      final InstalledApp app = _app(
        packageName: 'com.a',
        name: 'A',
        apkBytes: 25 * _mib,
      );

      expect(app.hasDetailedSize, isFalse);
      // A partial sum would understate the real footprint.
      expect(app.totalBytes, isNull);
      // Sorting still has something honest to work with.
      expect(app.bestKnownBytes, 25 * _mib);
    });

    test('the repository drops malformed rows and reads the flags', () {
      final InstalledAppsSnapshot snapshot =
          PlatformInstalledAppsRepository.parseSnapshot(<Object?, Object?>{
            'apps': <Object?>[
              <Object?, Object?>{'packageName': 'com.good', 'name': 'Good'},
              <Object?, Object?>{'name': 'No package'},
              'not a map',
            ],
            'hasUsageAccess': true,
            'sizeDetailSupported': false,
          });

      expect(snapshot.apps, hasLength(1));
      expect(snapshot.apps.single.packageName, 'com.good');
      expect(snapshot.hasUsageAccess, isTrue);
      expect(snapshot.sizeDetailSupported, isFalse);
    });

    test('a null payload is empty, not an error', () {
      expect(
        PlatformInstalledAppsRepository.parseSnapshot(null).apps,
        isEmpty,
      );
    });
  });

  group('AppInventory', () {
    test('user apps are the default, system apps counted but hidden', () {
      final AppInventory inventory = AppInventory.from(_fixture());

      expect(inventory.appCount, 3);
      expect(
        inventory.apps.map((InstalledApp a) => a.name),
        isNot(contains('System Thing')),
      );
      expect(inventory.hiddenSystemAppCount, 1);
    });

    test('the All filter includes system apps', () {
      final AppInventory inventory = AppInventory.from(
        _fixture(),
        filter: AppFilter.all,
      );
      expect(inventory.appCount, 4);
      expect(inventory.hiddenSystemAppCount, 0);
    });

    test('largest sorts on the full footprint when it is known', () {
      // Chatter's 1 GB of data beats Arcade's 300 MB of code, even though
      // Arcade has the bigger APK.
      expect(_names(AppSort.largest), <String>[
        'Chatter',
        'Arcade',
        'Notepad',
      ]);
    });

    test('name and date orderings each differ', () {
      expect(_names(AppSort.name), <String>[
        'Arcade',
        'Chatter',
        'Notepad',
      ]);
      expect(_names(AppSort.recentlyUpdated), <String>[
        'Chatter',
        'Notepad',
        'Arcade',
      ]);
      expect(_names(AppSort.oldest), <String>[
        'Arcade',
        'Chatter',
        'Notepad',
      ]);
    });

    test('apps with no date sort last, never first', () {
      final List<InstalledApp> apps = <InstalledApp>[
        _app(packageName: 'com.undated', name: 'Undated'),
        _app(
          packageName: 'com.dated',
          name: 'Dated',
          updatedAt: DateTime(2020, 1, 1),
        ),
      ];
      final AppInventory inventory = AppInventory.from(
        apps,
        sort: AppSort.recentlyUpdated,
      );
      expect(inventory.apps.last.name, 'Undated');
    });

    test('ties break stably, so the order never shuffles', () {
      final List<InstalledApp> tied = <InstalledApp>[
        _app(packageName: 'com.z', name: 'Same', apkBytes: 10 * _mib),
        _app(packageName: 'com.a', name: 'Same', apkBytes: 10 * _mib),
      ];
      final AppInventory first = AppInventory.from(tied);
      final AppInventory second = AppInventory.from(tied.reversed);

      expect(first.apps.first.packageName, 'com.a');
      expect(
        first.apps.map((InstalledApp a) => a.packageName),
        second.apps.map((InstalledApp a) => a.packageName),
      );
    });

    test('a duplicate package is listed once', () {
      final InstalledApp app = _app(packageName: 'com.dup', name: 'Dup');
      expect(AppInventory.from(<InstalledApp>[app, app]).appCount, 1);
    });

    test('totals use the best figure known per app', () {
      final AppInventory inventory = AppInventory.from(_fixture());
      // 1000 + 400 + 16 MB.
      expect(inventory.totalBytes, 1416 * _mib);
      expect(inventory.totalCacheBytes, 61 * _mib);
      expect(inventory.largestApp?.name, 'Chatter');
    });

    test('a usage-access prompt is only offered when it would help', () {
      expect(
        AppInventory.from(_fixture(), hasUsageAccess: true).canImproveSizes,
        isFalse,
      );
      expect(
        AppInventory.from(_fixture()).canImproveSizes,
        isTrue,
      );
      // Below Android 8 the API does not exist, so never nag.
      expect(
        AppInventory.from(_fixture(), sizeDetailSupported: false)
            .canImproveSizes,
        isFalse,
      );
    });

    test('an uninstalled app can be dropped without a re-read', () {
      final AppInventory inventory = AppInventory.from(_fixture());
      final AppInventory after = inventory.withoutPackage('com.chat');

      expect(after.appCount, 2);
      // An unknown package leaves the inventory untouched.
      expect(
        identical(inventory.withoutPackage('com.nope'), inventory),
        isTrue,
      );
    });
  });

  group('Apps screen', () {
    testWidgets('shows icon, name, and size for each app', (
      WidgetTester tester,
    ) async {
      await _pumpApps(tester);

      expect(find.byKey(const Key('app_card_com.chat')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('app_name_com.chat'))).data,
        'Chatter',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('app_size_com.chat'))).data,
        '1000.0 MB',
      );
      // No icon bytes in the fixture, so the lettered fallback is used.
      expect(
        find.byKey(const Key('app_icon_fallback_com.chat')),
        findsOneWidget,
      );
    });

    testWidgets('offers Open, App Settings, and Uninstall per app', (
      WidgetTester tester,
    ) async {
      final _StubApps repo = await _pumpApps(tester);

      await tester.tap(find.byKey(const Key('app_open_com.chat')));
      await tester.pumpAndSettle();
      expect(repo.opened, <String>['com.chat']);

      await tester.tap(find.byKey(const Key('app_settings_com.chat')));
      await tester.pumpAndSettle();
      expect(repo.settingsOpened, <String>['com.chat']);

      await tester.tap(find.byKey(const Key('app_uninstall_com.chat')));
      await tester.pumpAndSettle();
      expect(repo.uninstallRequested, <String>['com.chat']);
    });

    testWidgets('uninstall is a handoff, and the app is not removed locally', (
      WidgetTester tester,
    ) async {
      // The user backs out of Android's dialog, so the package remains.
      final _StubApps repo = _StubApps(stillInstalled: true);
      await _pumpApps(tester, repository: repo);
      final int readsBefore = repo.reads;

      await tester.tap(find.byKey(const Key('app_uninstall_com.chat')));
      await tester.pumpAndSettle();

      // Still listed: this screen never removes an app itself.
      expect(find.byKey(const Key('app_card_com.chat')), findsOneWidget);
      // And a cancelled uninstall costs no re-read.
      expect(repo.reads, readsBefore);
    });

    testWidgets('a failed action is reported rather than silently ignored', (
      WidgetTester tester,
    ) async {
      await _pumpApps(tester, repository: _StubApps(actionsSucceed: false));

      await tester.tap(find.byKey(const Key('app_open_com.chat')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('apps_message')), findsOneWidget);
      expect(find.text('Chatter could not be opened.'), findsOneWidget);
    });

    testWidgets('system apps cannot be uninstalled and say so', (
      WidgetTester tester,
    ) async {
      await _pumpApps(tester);

      await tester.tap(find.byKey(const Key('app_filter_all')));
      await tester.pumpAndSettle();

      final Finder uninstall = find.byKey(
        const Key('app_uninstall_com.android.systemthing'),
      );
      await tester.scrollUntilVisible(
        uninstall,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('apps_list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Android refuses for system apps, so the action is disabled up front.
      expect(
        tester.widget<TextButton>(uninstall).onPressed,
        isNull,
      );
      // Open is disabled too: it has no launcher intent.
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('app_open_com.android.systemthing')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('sizes are labelled honestly without usage access', (
      WidgetTester tester,
    ) async {
      await _pumpApps(
        tester,
        repository: _StubApps(
          apps: <InstalledApp>[
            _app(packageName: 'com.a', name: 'Alpha', apkBytes: 25 * _mib),
          ],
          hasAccess: false,
        ),
      );

      // Not presented as a full footprint.
      expect(
        tester.widget<Text>(find.byKey(const Key('app_size_com.a'))).data,
        '25.0 MB app',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('apps_total_bytes'))).data,
        '25.0 MB',
      );
      expect(find.byKey(const Key('apps_usage_access_card')), findsOneWidget);
    });

    testWidgets('the usage-access prompt opens system settings', (
      WidgetTester tester,
    ) async {
      final _StubApps repo = _StubApps(hasAccess: false);
      await _pumpApps(tester, repository: repo);

      await tester.tap(find.byKey(const Key('apps_grant_usage_access')));
      await tester.pumpAndSettle();

      expect(repo.usageSettingsOpened, 1);
    });

    testWidgets('no usage-access prompt where the API cannot exist', (
      WidgetTester tester,
    ) async {
      await _pumpApps(
        tester,
        repository: _StubApps(hasAccess: false, detailSupported: false),
      );

      // Nagging for a permission that would change nothing is worse than
      // showing a partial figure.
      expect(find.byKey(const Key('apps_usage_access_card')), findsNothing);
    });

    testWidgets('the list admits it is shorter than system settings', (
      WidgetTester tester,
    ) async {
      await _pumpApps(tester);

      expect(find.byKey(const Key('apps_visibility_note')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('apps_count'))).data,
        '3 apps',
      );
    });

    testWidgets('all four sorts are offered and reorder the list', (
      WidgetTester tester,
    ) async {
      final _StubApps repo = await _pumpApps(tester);

      for (final AppSort sort in AppSort.values) {
        expect(find.byKey(Key('app_sort_${sort.name}')), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('app_sort_name')));
      await tester.pumpAndSettle();

      // Re-sorting is done in memory, never by re-reading the package list.
      expect(repo.reads, 1);
    });

    testWidgets('the system filter changes the visible count', (
      WidgetTester tester,
    ) async {
      final _StubApps repo = await _pumpApps(tester);

      await tester.tap(find.byKey(const Key('app_filter_all')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('apps_count'))).data,
        '4 apps',
      );
      expect(repo.reads, 1);
    });

    testWidgets('an empty list explains itself', (WidgetTester tester) async {
      await _pumpApps(
        tester,
        repository: _StubApps(apps: const <InstalledApp>[]),
      );

      expect(find.byKey(const Key('apps_empty')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
