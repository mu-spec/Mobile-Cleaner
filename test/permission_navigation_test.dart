import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/app/app.dart';
import 'package:phone_storage_cleaner/app/router/app_router.dart';
import 'package:phone_storage_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:phone_storage_cleaner/features/files/data/storage_access_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_scan_result.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/apk_cleaner_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/downloads_cleaner_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/large_photos_screen.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/screenshot_cleaner_screen.dart';
import 'package:phone_storage_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';
import 'package:phone_storage_cleaner/features/permissions/presentation/providers/permission_manager.dart';
import 'package:phone_storage_cleaner/features/storage/data/storage_repository.dart';
import 'package:phone_storage_cleaner/features/storage/domain/storage_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/permission_fakes.dart';

class _EmptyScanner implements FileScannerRepository {
  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => FileScanResult.empty;
}

class _Storage implements StorageRepository {
  @override
  Future<StorageInfo> getStorageInfo() async =>
      const StorageInfo(totalBytes: 64000000000, freeBytes: 32000000000);
}

Future<void> _flush(WidgetTester tester) async {
  // Bounded frames: scan/loading animations intentionally do not settle.
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  FakePermissionGateway gateway,
  FakeFolderAccess folders,
) async {
  SharedPreferences.setMockInitialValues({'onboarding_completed': true});
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  appRouter.go(AppRoutes.home);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        permissionGatewayProvider.overrideWithValue(gateway),
        storageAccessRepositoryProvider.overrideWithValue(folders),
        fileScannerRepositoryProvider.overrideWithValue(_EmptyScanner()),
        storageRepositoryProvider.overrideWithValue(_Storage()),
      ],
      child: const PhoneStorageCleanerApp(),
    ),
  );
  await _flush(tester);
  return ProviderScope.containerOf(
    tester.element(find.byType(PhoneStorageCleanerApp)),
  );
}

void main() {
  testWidgets(
    'grant in one tool is reused by the next, then video asks only when missing',
    (tester) async {
      final gateway = FakePermissionGateway();
      await _mount(tester, gateway, FakeFolderAccess());
      appRouter.push(AppRoutes.screenshotCleaner);
      await _flush(tester);
      expect(find.byKey(const Key('permission_education')), findsOneWidget);
      expect(gateway.requests, isEmpty);
      await tester.tap(find.byKey(const Key('permission_primary_action')));
      await _flush(tester);
      expect(find.byType(ScreenshotCleanerScreen), findsOneWidget);
      expect(find.byKey(const Key('permission_granted')), findsNothing);
      expect(gateway.requests, [
        {PermissionKind.photos},
      ]);

      appRouter.go(AppRoutes.home);
      await _flush(tester);
      appRouter.push(AppRoutes.largePhotos);
      await _flush(tester);
      expect(find.byType(LargePhotosScreen), findsOneWidget);
      expect(find.byKey(const Key('permission_education')), findsNothing);
      expect(gateway.requests.length, 1);

      appRouter.push(AppRoutes.videos);
      await _flush(tester);
      expect(find.byKey(const Key('permission_education')), findsOneWidget);
      expect(gateway.requests.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Files access is reused for APK and Downloads without another page',
    (tester) async {
      final gateway = FakePermissionGateway(sdkInt: 28);
      await _mount(tester, gateway, FakeFolderAccess());
      appRouter.push(AppRoutes.files);
      await _flush(tester);
      await tester.tap(find.byKey(const Key('permission_primary_action')));
      await _flush(tester);
      expect(gateway.requests, [
        {PermissionKind.storage},
      ]);
      appRouter.push(AppRoutes.apkCleaner);
      await _flush(tester);
      expect(find.byType(ApkCleanerScreen), findsOneWidget);
      expect(find.byKey(const Key('permission_education')), findsNothing);
      appRouter.push(AppRoutes.downloadsCleaner);
      await _flush(tester);
      expect(find.byType(DownloadsCleanerScreen), findsOneWidget);
      expect(gateway.requests.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'scoped non-media tools never request unrelated photo/audio grants',
    (tester) async {
      final gateway = FakePermissionGateway();
      await _mount(tester, gateway, FakeFolderAccess());
      appRouter.push(AppRoutes.files);
      await _flush(tester);
      expect(find.byKey(const Key('folder_access_banner')), findsOneWidget);
      expect(find.byKey(const Key('permission_education')), findsNothing);
      appRouter.push(AppRoutes.apkCleaner);
      await _flush(tester);
      expect(find.byType(ApkCleanerScreen), findsOneWidget);
      appRouter.push(AppRoutes.downloadsCleaner);
      await _flush(tester);
      expect(find.byType(DownloadsCleanerScreen), findsOneWidget);
      expect(find.byKey(const Key('permission_education')), findsNothing);
      expect(gateway.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'permanent denial opens Settings; resume continues automatically',
    (tester) async {
      final gateway = FakePermissionGateway(
        initial: AppPermissionStatus.permanentlyDenied,
      );
      await _mount(tester, gateway, FakeFolderAccess());
      appRouter.push(AppRoutes.screenshotCleaner);
      await _flush(tester);
      expect(
        find.byKey(const Key('permission_permanently_denied')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('permission_primary_action')));
      await _flush(tester);
      expect(gateway.settingsOpened, 1);
      expect(gateway.requests, isEmpty);
      gateway.statuses[PermissionKind.photos] = AppPermissionStatus.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _flush(tester);
      expect(find.byType(ScreenshotCleanerScreen), findsOneWidget);
      expect(find.byKey(const Key('permission_granted')), findsNothing);
      expect(gateway.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'revocation while backgrounded guards the active feature on return',
    (tester) async {
      final gateway = FakePermissionGateway(
        initial: AppPermissionStatus.granted,
      );
      await _mount(tester, gateway, FakeFolderAccess());
      appRouter.push(AppRoutes.screenshotCleaner);
      await _flush(tester);
      expect(find.byType(ScreenshotCleanerScreen), findsOneWidget);
      gateway.statuses[PermissionKind.photos] = AppPermissionStatus.denied;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _flush(tester);
      expect(find.byKey(const Key('permission_education')), findsOneWidget);
      expect(gateway.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'limited selected-photo access opens photo tools without another prompt',
    (tester) async {
      final gateway = FakePermissionGateway();
      gateway.statuses[PermissionKind.photos] = AppPermissionStatus.limited;
      final container = await _mount(tester, gateway, FakeFolderAccess());
      appRouter.push(AppRoutes.screenshotCleaner);
      await _flush(tester);
      expect(find.byType(ScreenshotCleanerScreen), findsOneWidget);
      expect(gateway.requests, isEmpty);
      final snapshot = await container
          .read(permissionManagerProvider.notifier)
          .refresh();
      expect(
        snapshot.statusOf(PermissionKind.photos),
        AppPermissionStatus.limited,
      );
      expect(snapshot.allowsFeature(PermissionFeature.videos), isFalse);
      expect(snapshot.folderUris, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('existing SAF grants suppress the repeated folder explanation', (
    tester,
  ) async {
    final gateway = FakePermissionGateway(initial: AppPermissionStatus.granted);
    final folders = FakeFolderAccess();
    await folders.requestFolderAccess();
    final container = await _mount(tester, gateway, folders);
    appRouter.push(AppRoutes.files);
    await _flush(tester);
    expect(find.byKey(const Key('folder_access_banner')), findsNothing);
    folders.folders.clear();
    await container.read(permissionManagerProvider.notifier).refresh();
    await _flush(tester);
    expect(find.byKey(const Key('folder_access_banner')), findsOneWidget);
    expect(folders.pickerRequests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
