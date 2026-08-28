import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/apps/data/installed_apps_repository.dart';
import 'package:mobile_cleaner/features/apps/domain/app_inventory.dart';
import 'package:mobile_cleaner/features/apps/domain/installed_app.dart';
import 'package:mobile_cleaner/features/apps/presentation/screens/app_details_screen.dart';
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
  String? versionName,
  int? versionCode,
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
  versionName: versionName,
  versionCode: versionCode,
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
    versionName: '2.88.1',
    versionCode: 28801,
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
    this.actionsSucceed = true,
    this.stillInstalled = true,
  }) : apps = apps ?? _fixture();

  final List<InstalledApp> apps;
  final bool hasAccess;
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
      sizeDetailSupported: true,
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
    AppInventory.from(
      _fixture(),
      sort: sort,
      filter: filter,
    ).apps.map((InstalledApp a) => a.name).toList();

Future<void> _openDetails(WidgetTester tester, String packageName) async {
  await tester.tap(find.byKey(Key('app_card_$packageName')));
  await tester.pumpAndSettle();
}

void main() {
  group('InstalledApp parsing', () {
    test('reads a well-formed platform row', () {
      final InstalledApp? app = InstalledApp.fromPlatformMap(<Object?, Object?>{
        'packageName': 'com.example',
        'name': 'Example',
        'apkBytes': 30 * _mib,
        'appBytes': 30 * _mib,
        'dataBytes': 70 * _mib,
        'cacheBytes': 5 * _mib,
        'versionName': '4.2.1',
        'versionCode': 421,
        'isSystemApp': false,
        'canOpen': true,
        'updatedAtMillis': 1700000000000,
      });

      expect(app, isNotNull);
      expect(app!.name, 'Example');
      expect(app.hasDetailedSize, isTrue);
      expect(app.totalBytes, 105 * _mib);
      expect(app.versionName, '4.2.1');
      expect(app.versionCode, 421);
      expect(app.updatedAt, isNotNull);
    });

    test('a row without a package name is dropped', () {
      expect(
        InstalledApp.fromPlatformMap(<Object?, Object?>{'name': 'Ghost'}),
        isNull,
      );
    });

    test('a missing label falls back to the package name', () {
      final InstalledApp? app = InstalledApp.fromPlatformMap(<Object?, Object?>{
        'packageName': 'com.silent',
        'apkBytes': 100,
      });
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
      expect(PlatformInstalledAppsRepository.parseSnapshot(null).apps, isEmpty);
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
      expect(_names(AppSort.largest), <String>['Chatter', 'Arcade', 'Notepad']);
    });

    test('name and date orderings each differ', () {
      expect(_names(AppSort.name), <String>['Arcade', 'Chatter', 'Notepad']);
      expect(_names(AppSort.recentlyUpdated), <String>[
        'Chatter',
        'Notepad',
        'Arcade',
      ]);
      expect(_names(AppSort.oldest), <String>['Arcade', 'Chatter', 'Notepad']);
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
      expect(AppInventory.from(_fixture()).canImproveSizes, isTrue);
      // Below Android 8 the API does not exist, so never nag.
      expect(
        AppInventory.from(
          _fixture(),
          sizeDetailSupported: false,
        ).canImproveSizes,
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
    testWidgets('shows the compact reference list with no inline actions', (
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
      expect(
        tester.widget<Text>(find.byKey(const Key('app_detail_com.chat'))).data,
        'Updated 01 Feb 2026',
      );
      expect(find.byKey(const Key('app_more_com.chat')), findsOneWidget);
      expect(find.byKey(const Key('app_open_com.chat')), findsNothing);
      expect(find.byKey(const Key('apps_usage_access_card')), findsNothing);
      expect(find.byKey(const Key('apps_refresh')), findsNothing);
      expect(
        find.byKey(const Key('app_icon_fallback_com.chat')),
        findsOneWidget,
      );
    });

    testWidgets('tapping an app opens its complete real detail screen', (
      WidgetTester tester,
    ) async {
      await _pumpApps(tester);
      await _openDetails(tester, 'com.chat');

      expect(
        find.byKey(const Key('app_details_screen_com.chat')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('app_details_version_com.chat')))
            .data,
        'Version 2.88.1',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('app_details_package_com.chat')))
            .data,
        'com.chat',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('app_details_total_com.chat')))
            .data,
        '1000.0 MB',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('app_details_app_bytes_com.chat')),
            )
            .data,
        '40.0 MB',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('app_details_data_bytes_com.chat')),
            )
            .data,
        '900.0 MB',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('app_details_cache_bytes_com.chat')),
            )
            .data,
        '60.0 MB',
      );
    });

    testWidgets('detail screen offers Open, App Settings, and Uninstall', (
      WidgetTester tester,
    ) async {
      final _StubApps repo = await _pumpApps(tester);
      await _openDetails(tester, 'com.chat');

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

    testWidgets('uninstall remains an Android handoff', (
      WidgetTester tester,
    ) async {
      final _StubApps repo = _StubApps(stillInstalled: true);
      await _pumpApps(tester, repository: repo);
      final int readsBefore = repo.reads;
      await _openDetails(tester, 'com.chat');

      await tester.tap(find.byKey(const Key('app_uninstall_com.chat')));
      await tester.pumpAndSettle();

      expect(repo.uninstallRequested, <String>['com.chat']);
      expect(repo.reads, readsBefore);
    });

    testWidgets('a failed detail action is reported', (
      WidgetTester tester,
    ) async {
      await _pumpApps(tester, repository: _StubApps(actionsSucceed: false));
      await _openDetails(tester, 'com.chat');

      await tester.tap(find.byKey(const Key('app_open_com.chat')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('apps_message')), findsOneWidget);
      expect(find.text('Chatter could not be opened.'), findsOneWidget);
    });

    testWidgets('system app detail disables impossible actions', (
      WidgetTester tester,
    ) async {
      final InstalledApp system = _fixture().last;
      await tester.pumpWidget(
        MaterialApp(
          home: AppDetailsScreen(
            app: system,
            onOpen: () {},
            onSettings: () {},
            onUninstall: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('app_open_com.android.systemthing')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('app_uninstall_com.android.systemthing')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('partial Android figures stay honestly labelled', (
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

      expect(
        tester.widget<Text>(find.byKey(const Key('app_size_com.a'))).data,
        '25.0 MB',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('apps_total_label'))).data,
        'App size, excluding data',
      );
      expect(find.byKey(const Key('apps_usage_access_card')), findsNothing);

      await _openDetails(tester, 'com.a');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('app_details_size_scope_com.a')))
            .data,
        'Excluding data',
      );
      expect(find.text('Not available'), findsNWidgets(2));
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

    testWidgets('only the four reference sorts are shown and work in memory', (
      WidgetTester tester,
    ) async {
      final _StubApps repo = await _pumpApps(tester);

      for (final AppSort sort in AppSort.values) {
        expect(find.byKey(Key('app_sort_${sort.name}')), findsOneWidget);
      }
      expect(find.byKey(const Key('app_filter_all')), findsNothing);
      expect(find.byKey(const Key('app_filter_userApps')), findsNothing);

      await tester.tap(find.byKey(const Key('app_sort_name')));
      await tester.pumpAndSettle();
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
