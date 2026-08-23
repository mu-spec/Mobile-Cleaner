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
  await tester.pumpAndSettle();
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
  await tester.pumpAndSettle();
}

void main() {
  group('Storage is the top of the hierarchy', () {
    testWidgets('used and available are both shown clearly', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byKey(const Key('used_storage')), findsOneWidget);
      expect(find.byKey(const Key('free_storage')), findsOneWidget);
      expect(find.text('Used'), findsOneWidget);
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

      expect(find.byKey(const Key('storage_percentage')), findsOneWidget);
      expect(find.text('64%'), findsOneWidget);
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
    testWidgets('the CTA reads Scan Now and carries the privacy note', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byKey(const Key('smart_scan_hero')), findsOneWidget);
      expect(find.byKey(const Key('smart_scan_button')), findsOneWidget);
      expect(find.text('Scan Now'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('smart_scan_privacy_note')))
            .data,
        'Files stay on your device.',
      );
    });

    testWidgets('the feature is still named on the screen', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      // The hero card names the feature; the button states the action.
      // Several existing tests use this text to confirm they landed on Home.
      expect(find.text('Smart Scan'), findsOneWidget);
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

  group('Recommended for you uses real data only', () {
    testWidgets('nothing is invented when the device is clean', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      // No findings, so no count badge and no fabricated rows.
      expect(find.byKey(const Key('recommendations_section')), findsOneWidget);
      expect(find.byKey(const Key('recommendations_count')), findsNothing);
      expect(
        find.byKey(const Key('recommendation_screenshotReview')),
        findsNothing,
      );
    });

    testWidgets('a real finding is shown with its real numbers', (
      WidgetTester tester,
    ) async {
      // 25 stale screenshots at 4 MB each: past the >20 rule.
      await _pumpHome(
        tester,
        files: <ScannedFile>[for (int i = 0; i < 25; i++) _screenshot(i)],
      );

      await _scrollTo(
        tester,
        find.byKey(const Key('recommendation_screenshotReview')),
      );

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('recommendation_detail_screenshotReview')),
            )
            .data,
        '25 screenshots older than 90 days · 100.0 MB',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('recommendations_count')))
            .data,
        '1',
      );
    });

    testWidgets('the section is headed Recommended for you', (
      WidgetTester tester,
    ) async {
      await _pumpHome(
        tester,
        files: <ScannedFile>[for (int i = 0; i < 25; i++) _screenshot(i)],
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('recommendations_title')))
            .data,
        'Recommended for you',
      );
    });
  });

  group('Quick tools', () {
    testWidgets('all four tools are present as compact tiles', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);
      await _scrollTo(tester, find.byKey(const Key('quick_tools_section')));

      for (final Key key in <Key>[
        Key('quick_photos'),
        Key('quick_files'),
        Key('quick_apps'),
        Key('quick_permissions'),
      ]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key missing');
      }
    });

    testWidgets('the section is headed Quick Tools with the review note', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);
      await _scrollTo(tester, find.byKey(const Key('quick_tools_section')));

      expect(find.text('Quick Tools'), findsOneWidget);
      expect(find.text('Review before removing'), findsOneWidget);
    });

    testWidgets('tiles meet the minimum touch target', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);
      await _scrollTo(tester, find.byKey(const Key('quick_photos')));

      final Size row = tester.getSize(find.byKey(const Key('quick_photos')));
      // Comfortably above the 48dp accessibility guideline.
      expect(row.height, greaterThanOrEqualTo(48));
    });

    testWidgets('tools sit below the recommendations', (
      WidgetTester tester,
    ) async {
      await _pumpHome(tester);

      final double recommendationsY = tester
          .getTopLeft(find.byKey(const Key('recommendations_section')))
          .dy;
      final double toolsY = tester
          .getTopLeft(find.byKey(const Key('quick_tools_section')))
          .dy;

      expect(recommendationsY, lessThan(toolsY));
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

      expect(find.text('100%'), findsOneWidget);
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
}
