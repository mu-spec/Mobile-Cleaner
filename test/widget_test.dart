import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/app/app.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/features/apps/data/installed_apps_repository.dart';
import 'package:mobile_cleaner/features/apps/domain/installed_app.dart';
import 'package:mobile_cleaner/features/cleaner/presentation/screens/clean_screen.dart';
import 'package:mobile_cleaner/features/files/data/file_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/perceptual_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/files_screen.dart';
import 'package:mobile_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:mobile_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:mobile_cleaner/features/storage/data/storage_repository.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // `appRouter` is a global singleton shared by every test, so the shell's
    // selected branch leaks across tests. Reset it to a known state.
    appRouter.go(AppRoutes.home);
  });

  /// The default 800x600 test window is shorter than any phone, which pushes
  /// scrollable content underneath the bottom navigation bar and makes taps
  /// land on the wrong widget. Use a realistic portrait surface instead.
  Future<void> usePhoneSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('onboarding is first-launch only and can be replayed', (
    WidgetTester tester,
  ) async {
    await usePhoneSurface(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{'onboarding_completed': false});
    appRouter.go(AppRoutes.splash);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionGatewayProvider.overrideWithValue(
            _FakePermissionGateway(AppPermissionStatus.denied),
          ),
          ..._offlineDataOverrides,
        ],
        child: const MobileCleanerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 500));

    const double activeIndicatorWidth = 28;
    const double inactiveIndicatorWidth = 8;

    void expectActiveOnboardingIndicator(int activeIndex) {
      expect(find.byKey(const Key('onboarding_screen')), findsOneWidget);
      for (int index = 0; index < 3; index++) {
        final AnimatedContainer indicator = tester.widget<AnimatedContainer>(
          find.byKey(Key('onboarding_indicator_$index')),
        );
        expect(
          indicator.constraints?.maxWidth,
          index == activeIndex
              ? activeIndicatorWidth
              : inactiveIndicatorWidth,
        );
      }
    }

    Future<void> advanceOnboarding() async {
      await tester.tap(find.byKey(const Key('onboarding_next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    expectActiveOnboardingIndicator(0);

    await advanceOnboarding();
    expectActiveOnboardingIndicator(1);

    await advanceOnboarding();
    expectActiveOnboardingIndicator(2);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('permission_education')), findsOneWidget);

    await tester.tap(find.byKey(const Key('permission_secondary_action')));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.byKey(const Key('home_scan_now_button')), findsOneWidget);

    appRouter.go(AppRoutes.splash);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('home_scan_now_button')), findsOneWidget);
    expect(find.byKey(const Key('onboarding_screen')), findsNothing);

    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pump(const Duration(milliseconds: 2000));
    // Settings gained theme, threshold, privacy and about entries, so the
    // lower rows now sit below the fold on a phone-sized surface.
    await scrollSettingsTo(tester, const Key('replay_onboarding'));
    await tester.tap(find.byKey(const Key('replay_onboarding')));
    await tester.pump(const Duration(milliseconds: 2000));
    expectActiveOnboardingIndicator(0);

    await tester.tap(find.byKey(const Key('onboarding_skip')));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.byKey(const Key('home_scan_now_button')), findsOneWidget);
  });

  testWidgets('denied permission is handled without a crash', (
    WidgetTester tester,
  ) async {
    await usePhoneSurface(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_completed': true,
      'permission_education_seen': false,
    });
    appRouter.go(AppRoutes.splash);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionGatewayProvider.overrideWithValue(
            _FakePermissionGateway(AppPermissionStatus.denied),
          ),
          ..._offlineDataOverrides,
        ],
        child: const MobileCleanerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('permission_education')), findsOneWidget);
    await tester.tap(find.byKey(const Key('permission_primary_action')));
    await tester.pump(const Duration(milliseconds: 2000));

    expect(find.byKey(const Key('permission_denied')), findsOneWidget);
    expect(find.text('Permission denied'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final Finder secondaryAction = find.descendant(
      of: find.byKey(const Key('permission_denied')),
      matching: find.byKey(const Key('permission_secondary_action')),
    );
    expect(secondaryAction, findsOneWidget);

    await tester.ensureVisible(secondaryAction);
    await tester.pump();

    await tester.tap(secondaryAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('home_scan_now_button')), findsOneWidget);
  });

  testWidgets('home displays real storage values from the repository', (
    WidgetTester tester,
  ) async {
    await usePhoneSurface(tester);
    const int gib = 1024 * 1024 * 1024;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_completed': true,
      'permission_education_seen': true,
    });
    appRouter.go(AppRoutes.splash);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(
            const _FakeStorageRepository(
              StorageInfo(totalBytes: 128 * gib, freeBytes: 46 * gib),
            ),
          ),
          fileScannerRepositoryProvider.overrideWithValue(
            _EmptyFileScannerRepository(),
          ),
        ],
        child: const MobileCleanerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('storage_used_percentage')), findsOneWidget);
    expect(find.text('${((128 - 46) / 128 * 100).round()}%'), findsOneWidget);
    expect(find.text('128.0 GB'), findsOneWidget);
    expect(find.text('82.0 GB'), findsOneWidget);
    expect(find.text('46.0 GB'), findsOneWidget);
    expect(find.byKey(const Key('smart_scan_button')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('quick_tools_section')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('home_dashboard')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const Key('quick_tools_section')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Smart Scan and Settings actions open their screens', (
    WidgetTester tester,
  ) async {
    await usePhoneSurface(tester);
    const int gib = 1024 * 1024 * 1024;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_completed': true,
      'permission_education_seen': true,
    });
    appRouter.go(AppRoutes.splash);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageRepositoryProvider.overrideWithValue(
            const _FakeStorageRepository(
              StorageInfo(totalBytes: 128 * gib, freeBytes: 46 * gib),
            ),
          ),
          fileScannerRepositoryProvider.overrideWithValue(
            _EmptyFileScannerRepository(),
          ),
        ],
        child: const MobileCleanerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('home_scan_now_button')));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.byType(CleanScreen), findsOneWidget);

    appRouter.go(AppRoutes.home);
    await tester.pump(const Duration(milliseconds: 2000));
    // The in-header Home settings button was removed; Settings remains
    // reachable through bottom navigation (structure unchanged).
    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pump(const Duration(milliseconds: 2000));
    // 'Settings' appears both in the app bar and as the bottom nav label.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Settings')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every bottom tab opens without errors', (
    WidgetTester tester,
  ) async {
    await usePhoneSurface(tester);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_completed': true,
      'permission_education_seen': true,
    });
    appRouter.go(AppRoutes.splash);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _offlineDataOverrides,
        child: const MobileCleanerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('home_scan_now_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_clean')));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.byType(CleanScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_photos')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const Key('photos_screen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_files')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FilesScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_apps')));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.byKey(const Key('apps_list')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Settings')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('nav_home')));
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.byKey(const Key('home_scan_now_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Scrolls the Settings list until [key] is visible.
///
/// Settings is longer than a phone screen since Phase 26, so rows near the
/// bottom must be scrolled to before they can be tapped.
Future<void> scrollSettingsTo(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('settings_list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump(const Duration(milliseconds: 2000));
}

/// Platform channels are unavailable in widget tests, so stub every data
/// source that Home and Files read on start-up. Without this the loading
/// spinners animate forever and `pumpAndSettle` times out.
final _offlineDataOverrides = [
  storageRepositoryProvider.overrideWithValue(
    const _FakeStorageRepository(
      StorageInfo(
        totalBytes: 64 * 1024 * 1024 * 1024,
        freeBytes: 20 * 1024 * 1024 * 1024,
      ),
    ),
  ),
  fileScannerRepositoryProvider.overrideWithValue(
    _EmptyFileScannerRepository(),
  ),
  thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
  // The Photos tab composes the duplicate scan, which hashes over a channel.
  fileHashRepositoryProvider.overrideWithValue(const _NoHashes()),
  // Similar photos decode over a channel that does not exist in tests.
  perceptualHashRepositoryProvider.overrideWithValue(const _NoFingerprints()),
  // The Apps tab reads installed packages over a channel.
  installedAppsRepositoryProvider.overrideWithValue(const _OneFakeApp()),
];

/// The Apps tab reads the package list over a channel that does not exist in
/// tests. One app keeps the list non-empty so `apps_list` renders.
class _OneFakeApp implements InstalledAppsRepository {
  const _OneFakeApp();

  @override
  Future<InstalledAppsSnapshot> getInstalledApps({
    bool includeIcons = true,
  }) async => const InstalledAppsSnapshot(
    apps: <InstalledApp>[
      InstalledApp(
        packageName: 'com.example.demo',
        name: 'Demo',
        apkBytes: 1024,
      ),
    ],
    sizeDetailSupported: false,
  );

  @override
  Future<bool> hasUsageAccess() async => false;

  @override
  Future<bool> openUsageAccessSettings() async => false;

  @override
  Future<bool> openApp(String packageName) async => false;

  @override
  Future<bool> openAppSettings(String packageName) async => false;

  @override
  Future<bool> requestUninstall(String packageName) async => false;

  @override
  Future<bool> isInstalled(String packageName) async => true;
}

/// Perceptual hashing is a platform channel; the Photos tab reaches it.
class _NoFingerprints implements PerceptualHashRepository {
  const _NoFingerprints();

  @override
  Future<Map<String, String>> hashImages(List<ScannedFile> files) async =>
      const <String, String>{};
}

/// Hashing is a platform channel too, and the Photos dashboard reaches it.
class _NoHashes implements FileHashRepository {
  const _NoHashes();

  @override
  Future<Map<String, String>> hashFiles(List<ScannedFile> files) async =>
      const <String, String>{};
}

/// Thumbnails come from a platform channel that does not exist in tests.
class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

class _EmptyFileScannerRepository implements FileScannerRepository {
  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => FileScanResult.fromFiles(const []);
}

class _FakeStorageRepository implements StorageRepository {
  const _FakeStorageRepository(this.info);

  final StorageInfo info;

  @override
  Future<StorageInfo> getStorageInfo() async => info;
}

class _FakePermissionGateway implements AppPermissionGateway {
  _FakePermissionGateway(this.status);

  final AppPermissionStatus status;

  @override
  Future<AppPermissionStatus> checkMediaAndStorage() async => status;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<AppPermissionStatus> requestMediaAndStorage() async => status;
}
