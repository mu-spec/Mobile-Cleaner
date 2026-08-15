import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/app/app.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
    await tester.pumpAndSettle();
    expect(find.text('Understand Your Storage'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('Clean Smarter'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('Private by Design'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('permission_education')), findsOneWidget);

    await tester.tap(find.byKey(const Key('permission_secondary_action')));
    await tester.pumpAndSettle();
    expect(find.text('Smart Scan'), findsOneWidget);

    appRouter.go(AppRoutes.splash);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text('Smart Scan'), findsOneWidget);
    expect(find.text('Understand Your Storage'), findsNothing);

    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replay_onboarding')));
    await tester.pumpAndSettle();
    expect(find.text('Understand Your Storage'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_skip')));
    await tester.pumpAndSettle();
    expect(find.text('Smart Scan'), findsOneWidget);
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
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('permission_education')), findsOneWidget);
    await tester.tap(find.byKey(const Key('permission_primary_action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('permission_denied')), findsOneWidget);
    expect(find.text('Permission denied'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('permission_secondary_action')));
    await tester.pumpAndSettle();
    expect(find.text('Smart Scan'), findsOneWidget);
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
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('storage_percentage')), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('128.0 GB'), findsOneWidget);
    expect(find.text('82.0 GB'), findsOneWidget);
    expect(find.text('46.0 GB'), findsOneWidget);
    expect(find.byKey(const Key('smart_scan_button')), findsOneWidget);
    expect(find.byKey(const Key('home_settings_button')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('recommendations_section')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('home_dashboard')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const Key('quick_tools_section')), findsOneWidget);
    expect(find.byKey(const Key('recommendations_section')), findsOneWidget);
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
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('smart_scan_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen_Clean')), findsOneWidget);

    appRouter.go(AppRoutes.home);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_settings_button')));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();

    expect(find.text('Smart Scan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_clean')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen_Clean')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_photos')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen_Photos')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_files')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('files_overview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_apps')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen_Apps')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pumpAndSettle();
    expect(find.text('App version'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
];

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
