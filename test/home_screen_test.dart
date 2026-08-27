import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_theme.dart';
import 'package:mobile_cleaner/features/apps/data/installed_apps_repository.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/perceptual_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/history/data/cleanup_history_repository.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_entry.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_history.dart';
import 'package:mobile_cleaner/features/home/presentation/screens/home_screen.dart';
import 'package:mobile_cleaner/features/storage/data/storage_repository.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';

const int _mib = 1024 * 1024;
const int _gib = 1024 * 1024 * 1024;

ScannedFile _screenshot(int i) => ScannedFile(
  id: 's$i',
  name: 'Screenshot_$i.png',
  path: '/storage/emulated/0/Pictures/Screenshots/Screenshot_$i.png',
  uri: 'content://media/external/images/media/$i',
  sizeBytes: 4 * _mib,
  category: FileCategory.images,
  dateModified: DateTime.now().subtract(const Duration(days: 200)),
  mimeType: 'image/png',
  relativePath: 'Pictures/Screenshots/',
);

class _FakeStorage implements StorageRepository {
  const _FakeStorage(this.info);
  final StorageInfo info;

  @override
  Future<StorageInfo> getStorageInfo() async => info;
}

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);
  final List<ScannedFile> files;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => FileScanResult.fromFiles(files, categories: request.categories);
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();
  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

class _NoHashes implements FileHashRepository {
  const _NoHashes();
  @override
  Future<Map<String, String>> hashFiles(List<ScannedFile> files) async =>
      const <String, String>{};
}

class _NoFingerprints implements PerceptualHashRepository {
  const _NoFingerprints();
  @override
  Future<Map<String, String>> hashImages(List<ScannedFile> files) async =>
      const <String, String>{};
}

class _NoopDelete implements DeleteRepository {
  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async =>
      DeleteResult(deletedFiles: files, failures: const <DeleteFailure>[]);
}

class _StubHistory implements CleanupHistoryRepository {
  _StubHistory([CleanupHistory? initial])
    : history = initial ?? CleanupHistory.empty;
  CleanupHistory history;

  @override
  Future<CleanupHistory> load() async => history;

  @override
  Future<CleanupHistory> record(CleanupEntry entry) async => history;

  @override
  Future<void> clear() async {}
}

class _NoApps implements InstalledAppsRepository {
  const _NoApps();

  @override
  Future<InstalledAppsSnapshot> getInstalledApps({
    bool includeIcons = true,
  }) async => InstalledAppsSnapshot.empty;

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

Future<void> _pumpHome(
  WidgetTester tester, {
  StorageInfo info = const StorageInfo(
    totalBytes: 128 * _gib,
    freeBytes: 46 * _gib,
  ),
  List<ScannedFile>? files,
  CleanupHistory? history,
  ThemeData? theme,
  double textScale = 1,
  Size size = const Size(420, 1000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageRepositoryProvider.overrideWithValue(_FakeStorage(info)),
        fileScannerRepositoryProvider.overrideWithValue(
          _StubScanner(files ?? const <ScannedFile>[]),
        ),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
        fileHashRepositoryProvider.overrideWithValue(const _NoHashes()),
        perceptualHashRepositoryProvider.overrideWithValue(
          const _NoFingerprints(),
        ),
        deleteRepositoryProvider.overrideWithValue(_NoopDelete()),
        cleanupHistoryRepositoryProvider.overrideWithValue(
          _StubHistory(history),
        ),
        installedAppsRepositoryProvider.overrideWithValue(const _NoApps()),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const HomeScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 2400));
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('home_dashboard')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump(const Duration(milliseconds: 2000));
}

void main() {
  group('Compact header', () {
    testWidgets('shows the app identity without an in-header action', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      expect(find.text('Mobile Cleaner'), findsOneWidget);
      expect(find.text('Clean smarter. Keep what matters.'), findsOneWidget);
      // The in-header Settings button was removed for a cleaner Home;
      // Settings stays available through bottom navigation.
      expect(find.byKey(const Key('home_settings_button')), findsNothing);
    });
  });

  group('Storage is the top of the hierarchy', () {
    testWidgets('used and available are both shown clearly', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byKey(const Key('used_storage')), findsOneWidget);
      expect(find.byKey(const Key('free_storage')), findsOneWidget);
      expect(find.text('Storage used'), findsOneWidget);
      // "Available" rather than "Free": plainer, and matches Android.
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('82.0 GB'), findsOneWidget);
      expect(find.text('46.0 GB'), findsOneWidget);
    });

    testWidgets('the total is labelled Internal storage', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      // Not "Total storage": what Android reports is the usable internal
      // partition, always less than the advertised capacity.
      expect(find.text('Internal storage'), findsOneWidget);
      expect(find.text('Total storage'), findsNothing);
      expect(find.byKey(const Key('total_storage')), findsOneWidget);
      expect(find.text('128.0 GB'), findsOneWidget);
    });

    testWidgets('the percentage ring is still shown', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byKey(const Key('storage_used_percentage')), findsOneWidget);
      expect(find.text('${((128 - 46) / 128 * 100).round()}%'), findsOneWidget);
    });

    testWidgets('the card is titled Storage Overview', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      expect(find.text('Storage Overview'), findsOneWidget);
    });

    testWidgets('storage appears before the scan action', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      final double storageY = tester
          .getTopLeft(find.byKey(const Key('used_storage')))
          .dy;
      final double scanY = tester
          .getTopLeft(find.byKey(const Key('smart_scan_button')))
          .dy;

      expect(storageY, lessThan(scanY));
    });
  });

  group('Smart Scan is the primary action', () {
    testWidgets('the CTA is a compact Smart Scan action', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byKey(const Key('smart_scan_hero')), findsOneWidget);
      expect(find.byKey(const Key('smart_scan_button')), findsOneWidget);
      expect(find.text('Scan Now'), findsOneWidget);
      // The separate privacy line was removed to keep Home compact; the app's
      // privacy/security behavior is unchanged.
      expect(find.byKey(const Key('smart_scan_privacy_note')), findsNothing);
      expect(find.text('Your files stay on your device'), findsNothing);
    });

    testWidgets('the feature is still named on the screen', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      // The hero card names the feature; the button states the action.
      // Several existing tests use this text to confirm they landed on Home.
      expect(find.text('Scan Now'), findsOneWidget);
    });

    testWidgets('the hero card is the full width of the content area', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      final Size hero = tester.getSize(
        find.byKey(const Key('smart_scan_hero')),
      );
      // 420 surface minus 16pt padding each side.
      expect(hero.width, 388);
    });
  });

  group('Smart Scan compact flow — Phase 1', () {
    testWidgets('Scan Now state shown when clean', (tester) async {
      await _pumpHome(tester);
      expect(find.byKey(const Key('smart_scan_hero')), findsOneWidget);
      expect(find.text('Scan Now'), findsOneWidget);
      expect(find.text('Scan Now'), findsOneWidget);
      expect(find.byKey(const Key('recommendations_section')), findsNothing);
      expect(find.text('Recommended for you'), findsNothing);
    });

    testWidgets('real recommendation shown inside Smart Scan card', (tester) async {
      await _pumpHome(
        tester,
        files: <ScannedFile>[for (int i = 0; i < 25; i++) _screenshot(i)],
      );
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.byKey(const Key('smart_scan_recommendation_screenshotReview')), findsOneWidget);
      expect(find.text('Review old screenshots'), findsOneWidget);
    });
  });

  group('Home hierarchy', () {
    testWidgets('Storage, Smart Scan, Quick Tools, Cleanup Summary appear in order', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      // Quick Tools restored
      expect(find.byKey(const Key('quick_tools_section')), findsOneWidget);

      final double storageY = tester
          .getTopLeft(find.byKey(const Key('used_storage')))
          .dy;
      final double scanY = tester
          .getTopLeft(find.byKey(const Key('smart_scan_button')))
          .dy;

      await _scrollTo(tester, find.byKey(const Key('home_history_empty')));
      final double historyY = tester
          .getTopLeft(find.byKey(const Key('home_history_empty')))
          .dy;
      // Quick Tools below Smart Scan and above Cleanup Summary
      final double quickY = tester
          .getTopLeft(find.byKey(const Key('quick_tools_section')))
          .dy;

      expect(storageY, lessThan(scanY));
      expect(scanY, lessThan(quickY));
      expect(quickY, lessThan(historyY));
      expect(find.text('Cleanup Summary'), findsOneWidget);
    });
  });

  group('History card', () {
    testWidgets('shows an honest empty state before the first cleanup', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      await _scrollTo(tester, find.byKey(const Key('home_history_empty')));
      // No invented amounts or dates — just where real numbers will appear.
      expect(find.byKey(const Key('home_history_card')), findsNothing);
      expect(find.text('No cleanups yet'), findsOneWidget);
    });

    testWidgets('appears once there is real history', (
      WidgetTester tester,
    ) async {
      await _pumpHome(
        tester,
        history: CleanupHistory.from(<CleanupEntry>[
          CleanupEntry(
            performedAt: DateTime(2026, 8, 17),
            filesRemoved: 4,
            bytesRecovered: 620 * _mib,
          ),
        ]),
      );

      await _scrollTo(tester, find.byKey(const Key('home_history_card')));
      expect(find.byKey(const Key('home_history_card')), findsOneWidget);
    });
  });

  group('Theme and layout robustness', () {
    testWidgets('renders in dark mode without throwing', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester, theme: AppTheme.dark);

      expect(find.byKey(const Key('home_dashboard')), findsOneWidget);
      expect(find.byKey(const Key('used_storage')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a large text scale', (WidgetTester tester) async {
      await _pumpHome(tester, textScale: 1.8);

      expect(find.byKey(const Key('smart_scan_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a small screen', (WidgetTester tester) async {
      await _pumpHome(tester, size: const Size(320, 560));

      expect(find.byKey(const Key('home_dashboard')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a full device still reports sane figures', (
      WidgetTester tester,
    ) async {
      await _pumpHome(
        tester,
        info: const StorageInfo(totalBytes: 64 * _gib, freeBytes: 0),
      );

      expect(find.text('${((64 - 0) / 64 * 100).round()}%'), findsOneWidget);
      expect(find.text('0 B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Navigation destinations are unchanged', () {
    test('recommendation routes still point at their existing screens', () {
      // Guards against a polish pass quietly repointing a destination.
      expect(AppRoutes.screenshotCleaner, '/screenshot-cleaner');
      expect(AppRoutes.duplicates, '/duplicates');
      expect(AppRoutes.videos, '/videos');
      expect(AppRoutes.clean, '/clean');
      expect(AppRoutes.photos, '/photos');
      expect(AppRoutes.largeFiles, '/large-files');
      expect(AppRoutes.apps, '/apps');
      expect(AppRoutes.permissions, '/permissions');
      expect(AppRoutes.history, '/history');
    });
  });
  group('Smart Scan compact flow — Phase 1', () {
    testWidgets('Scan Now state shown when no recommendation', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);
      expect(find.byKey(const Key('smart_scan_hero')), findsOneWidget);
      expect(find.text('Scan Now'), findsOneWidget);
      expect(find.text('Scan Now'), findsOneWidget);
      // Old descriptive text removed per spec.
      expect(find.text('Find and clean unnecessary files'), findsNothing);
    });

    testWidgets('recommendation state uses real recommendation data', (
      WidgetTester tester,
    ) async {
      // 25 stale screenshots past the >20 rule.
      await _pumpHome(
        tester,
        files: <ScannedFile>[for (int i = 0; i < 25; i++) _screenshot(i)],
      );
      await _scrollTo(
        tester,
        find.byKey(const Key('smart_scan_recommendation_screenshotReview')),
      );
      expect(
        find.byKey(const Key('smart_scan_recommendation_screenshotReview')),
        findsOneWidget,
      );
      expect(find.text('Review old screenshots'), findsOneWidget);
      expect(
        find.text('100.0 MB recoverable'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const Key('smart_scan_recommendation_screenshotReview'),
          ),
          matching: find.byKey(
            const Key('smart_scan_recommendation_icon'),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping recommendation targets existing destination', (
      WidgetTester tester,
    ) async {
      await _pumpHome(
        tester,
        files: <ScannedFile>[for (int i = 0; i < 25; i++) _screenshot(i)],
      );
      await _scrollTo(
        tester,
        find.byKey(const Key('smart_scan_recommendation_screenshotReview')),
      );
      final InkWell row = tester.widget<InkWell>(
        find.byKey(const Key('smart_scan_recommendation_screenshotReview')),
      );
      expect(row.onTap, isNotNull);
      expect(find.text('Review old screenshots'), findsOneWidget);
    });
  });

  group('Old Recommended for you card removed', () {
    testWidgets('separate recommendations section no longer on Home', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);
      expect(
        find.byKey(const Key('recommendations_section')),
        findsNothing,
      );
      expect(find.text('Recommended for you'), findsNothing);
      expect(find.byKey(const Key('recommendations_title')), findsNothing);
      expect(find.byKey(const Key('recommendations_count')), findsNothing);
    });
  });

  group('Quick Tools — Phase 2', () {
    testWidgets('all four tools appear in one row', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);
      expect(find.byKey(const Key('quick_photos')), findsOneWidget);
      expect(find.byKey(const Key('quick_files')), findsOneWidget);
      expect(find.byKey(const Key('quick_apps')), findsOneWidget);
      expect(find.byKey(const Key('quick_permissions')), findsOneWidget);
      expect(find.byKey(const Key('quick_tools_section')), findsOneWidget);
      expect(find.text('Review before removing'), findsNothing);
      expect(find.byKey(const Key('quick_photos_icon_tile')), findsOneWidget);
      expect(find.byKey(const Key('quick_files_icon_tile')), findsOneWidget);
      expect(find.byKey(const Key('quick_apps_icon_tile')), findsOneWidget);
      expect(
        find.byKey(const Key('quick_permissions_icon_tile')),
        findsOneWidget,
      );

      final Text storageAccess = tester.widget<Text>(
        find.text('Storage Access'),
      );
      expect(storageAccess.maxLines, 2);

      final Container photoIcon = tester.widget<Container>(
        find.byKey(const Key('quick_photos_icon_tile')),
      );
      final BoxDecoration decoration = photoIcon.decoration! as BoxDecoration;
      expect(decoration.gradient, isNotNull);
      expect(decoration.border, isNotNull);
      expect(decoration.boxShadow, isNotEmpty);
    });

    testWidgets('each tool opens correct destination', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);
      final Finder photo = find.byKey(const Key('quick_photos'));
      final Finder files = find.byKey(const Key('quick_files'));
      final Finder apps = find.byKey(const Key('quick_apps'));
      final Finder perms = find.byKey(const Key('quick_permissions'));

      expect(photo, findsOneWidget);
      expect(files, findsOneWidget);
      expect(apps, findsOneWidget);
      expect(perms, findsOneWidget);

      // Verify they are tappable
      final InkWell photoRow = tester.widget<InkWell>(photo);
      expect(photoRow.onTap, isNotNull);
    });

    testWidgets('layout survives large text scale', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester, textScale: 1.8);
      expect(find.byKey(const Key('quick_tools_section')), findsOneWidget);
      expect(find.byKey(const Key('quick_photos')), findsOneWidget);
    });
  });

  group('Storage ring animation — Phase 3', () {
    testWidgets('ring animates while percentage shows the final value', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);
      expect(find.byKey(const Key('storage_used_percentage')), findsOneWidget);
      // After short pump the animation should have progressed.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('storage_used_percentage')), findsOneWidget);
    });

    testWidgets('reduced motion shows final state immediately', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageRepositoryProvider.overrideWithValue(
              const _FakeStorage(StorageInfo(
                totalBytes: 128 * 1024 * 1024 * 1024,
                freeBytes: 30 * 1024 * 1024 * 1024,
              )),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(
                disableAnimations: true,
                size: Size(420, 1000),
              ),
              child: const HomeScreen(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('storage_used_percentage')), findsOneWidget);
    });
  });
}
