import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/cleaner/presentation/screens/clean_screen.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/apk_summary.dart';
import 'package:mobile_cleaner/features/files/domain/download_age_filter.dart';
import 'package:mobile_cleaner/features/files/domain/downloads_summary.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_summary.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/smart_scan_result.dart';

const int _mib = 1024 * 1024;
const int _gib = 1024 * 1024 * 1024;
const String _apkMime = 'application/vnd.android.package-archive';

/// Midday so a daylight-saving shift cannot move a fixture across a day.
DateTime _daysAgo(int days) {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 12)
      .subtract(Duration(days: days));
}

ScannedFile _file({
  required String id,
  required String name,
  required int sizeBytes,
  FileCategory category = FileCategory.downloads,
  int daysOld = 5,
  String? mimeType,
  String? uri,
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/Download/$name',
    uri: uri ?? 'content://media/external/${category.key}/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: _daysAgo(daysOld),
    mimeType: mimeType,
  );
}

/// A device holding one of each finding, plus a file matching all three.
List<ScannedFile> _fixture() => <ScannedFile>[
  // Large only: big, recent, not an installer.
  _file(
    id: '1',
    name: 'movie.mp4',
    sizeBytes: 800 * _mib,
    category: FileCategory.videos,
    daysOld: 2,
  ),
  // Old download only: small and old.
  _file(id: '2', name: 'invoice.pdf', sizeBytes: 2 * _mib, daysOld: 200),
  // APK only: recent, under the large threshold.
  _file(
    id: '3',
    name: 'tool.apk',
    sizeBytes: 20 * _mib,
    category: FileCategory.apks,
    daysOld: 3,
    mimeType: _apkMime,
  ),
  // All three at once: big, old, and an installer.
  _file(
    id: '4',
    name: 'old-game.apk',
    sizeBytes: 500 * _mib,
    daysOld: 400,
    mimeType: _apkMime,
  ),
];

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);

  final List<ScannedFile> files;
  int scanCount = 0;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    scanCount++;
    // Mirror the native contract so each tool sees what it would on device.
    final List<ScannedFile> visible = files
        .where((ScannedFile f) => f.sizeBytes >= request.minSizeBytes)
        .where((ScannedFile f) => request.categories.contains(f.category))
        .toList();
    return FileScanResult.fromFiles(visible, categories: request.categories);
  }
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

Future<_StubScanner> _pumpSmartScan(
  WidgetTester tester, {
  List<ScannedFile>? files,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubScanner scanner = _StubScanner(files ?? _fixture());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(scanner),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
      ],
      child: const MaterialApp(home: CleanScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return scanner;
}

/// Builds a result directly from the three summaries, bypassing the UI.
SmartScanResult _resultFrom(List<ScannedFile> files) {
  return SmartScanResult.from(
    largeFiles: LargeFileSummary.from(files, LargeFileFilter.defaultFilter),
    oldDownloads: DownloadsSummary.from(
      files.where((ScannedFile f) => f.category == FileCategory.downloads),
      DownloadAgeFilter.defaultFilter,
    ),
    apks: ApkSummary.from(files),
  );
}

void main() {
  group('SmartScanCategory', () {
    test('covers exactly the three required checks', () {
      expect(SmartScanCategory.values, <SmartScanCategory>[
        SmartScanCategory.largeFiles,
        SmartScanCategory.oldDownloads,
        SmartScanCategory.apkInstallers,
      ]);
      expect(
        SmartScanCategory.values.map((SmartScanCategory c) => c.label),
        <String>['Large files', 'Old downloads', 'APK installers'],
      );
    });
  });

  group('SmartScanResult', () {
    test('groups each finding under the right check', () {
      final SmartScanResult result = _resultFrom(_fixture());

      final SmartScanGroup large = result.groupFor(
        SmartScanCategory.largeFiles,
      );
      final SmartScanGroup old = result.groupFor(
        SmartScanCategory.oldDownloads,
      );
      final SmartScanGroup apks = result.groupFor(
        SmartScanCategory.apkInstallers,
      );

      // movie.mp4 (800 MB) and old-game.apk (500 MB) clear 100 MB.
      expect(
        large.files.map((ScannedFile f) => f.name),
        containsAll(<String>['movie.mp4', 'old-game.apk']),
      );
      // invoice.pdf and old-game.apk are old downloads.
      expect(
        old.files.map((ScannedFile f) => f.name),
        containsAll(<String>['invoice.pdf', 'old-game.apk']),
      );
      // Both installers.
      expect(
        apks.files.map((ScannedFile f) => f.name),
        containsAll(<String>['tool.apk', 'old-game.apk']),
      );
    });

    test('counts a file matched by several checks only once', () {
      final SmartScanResult result = _resultFrom(_fixture());

      // Four distinct files, even though the groups list six entries.
      expect(result.totalFiles, 4);
      expect(result.hasOverlap, isTrue);
      // 800 + 2 + 20 + 500 MB, each counted once.
      expect(result.totalBytes, (800 + 2 + 20 + 500) * _mib);
    });

    test('the headline is smaller than the summed group totals', () {
      final SmartScanResult result = _resultFrom(_fixture());
      final int summed = result.groups.fold<int>(
        0,
        (int sum, SmartScanGroup g) => sum + g.totalBytes,
      );

      // Adding group totals would double count the overlapping installer.
      expect(summed, greaterThan(result.totalBytes));
    });

    test('reports no overlap when checks find different files', () {
      final SmartScanResult result = _resultFrom(<ScannedFile>[
        _file(
          id: '1',
          name: 'movie.mp4',
          sizeBytes: 300 * _mib,
          category: FileCategory.videos,
          daysOld: 1,
        ),
        _file(id: '2', name: 'old.pdf', sizeBytes: _mib, daysOld: 100),
      ]);

      expect(result.hasOverlap, isFalse);
      expect(result.totalFiles, 2);
    });

    test('orders unique files largest first', () {
      final SmartScanResult result = _resultFrom(_fixture());
      expect(result.uniqueFiles.first.name, 'movie.mp4');
      expect(result.uniqueFiles.last.name, 'invoice.pdf');
    });

    test('ranks non-empty groups by size', () {
      final SmartScanResult result = _resultFrom(_fixture());
      expect(result.nonEmptyGroups.first.category, SmartScanCategory.largeFiles);
      expect(result.nonEmptyGroups, hasLength(3));
    });

    test('is empty when nothing matches any check', () {
      final SmartScanResult result = _resultFrom(<ScannedFile>[
        _file(id: '1', name: 'recent.txt', sizeBytes: _mib, daysOld: 1),
      ]);

      expect(result.isEmpty, isTrue);
      expect(result.totalBytes, 0);
      expect(result.nonEmptyGroups, isEmpty);
      expect(result.hasOverlap, isFalse);
    });

    test('an absent group still resolves', () {
      final SmartScanResult bare = SmartScanResult(
        groups: const <SmartScanGroup>[],
        scannedAt: DateTime(2026, 8, 15),
      );
      expect(bare.groupFor(SmartScanCategory.largeFiles).isEmpty, isTrue);
      expect(bare.groupFor(SmartScanCategory.largeFiles).totalBytes, 0);
    });
  });

  group('Smart Scan screen', () {
    testWidgets('shows a card for each of the three checks', (
      WidgetTester tester,
    ) async {
      await _pumpSmartScan(tester);

      for (final SmartScanCategory category in SmartScanCategory.values) {
        expect(
          find.byKey(Key('smart_group_${category.name}')),
          findsOneWidget,
          reason: '${category.label} needs a card',
        );
      }
    });

    testWidgets('reports the combined recoverable total', (
      WidgetTester tester,
    ) async {
      await _pumpSmartScan(tester);

      expect(find.byKey(const Key('smart_scan_total_card')), findsOneWidget);
      // 800 + 2 + 20 + 500 MB = 1322 MB = 1.3 GB
      expect(
        tester
            .widget<Text>(find.byKey(const Key('smart_scan_total_bytes')))
            .data,
        '1.3 GB',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('smart_scan_total_files')))
            .data,
        'across 4 files',
      );
    });

    testWidgets('explains the overlap when one exists', (
      WidgetTester tester,
    ) async {
      await _pumpSmartScan(tester);

      expect(find.byKey(const Key('smart_scan_overlap_note')), findsOneWidget);
    });

    testWidgets('runs one scan per underlying tool, not more', (
      WidgetTester tester,
    ) async {
      final _StubScanner scanner = await _pumpSmartScan(tester);

      // Large files, downloads, and APKs: three scans, no extra pass for the
      // combined view.
      expect(scanner.scanCount, 3);
    });

    testWidgets('lists the biggest items across every check', (
      WidgetTester tester,
    ) async {
      await _pumpSmartScan(tester);

      expect(find.text('movie.mp4'), findsOneWidget);
      // Listed once despite matching all three checks.
      expect(find.text('old-game.apk'), findsOneWidget);
    });

    testWidgets('shows a clean state when nothing is found', (
      WidgetTester tester,
    ) async {
      await _pumpSmartScan(
        tester,
        files: <ScannedFile>[
          _file(id: '1', name: 'recent.txt', sizeBytes: _mib, daysOld: 1),
        ],
      );

      expect(find.byKey(const Key('smart_scan_clean')), findsOneWidget);
      expect(find.text('Nothing to clean'), findsOneWidget);
      expect(find.byKey(const Key('smart_scan_findings')), findsNothing);
    });

    testWidgets('an empty check is shown but not tappable', (
      WidgetTester tester,
    ) async {
      await _pumpSmartScan(
        tester,
        files: <ScannedFile>[
          // Large only; no old downloads, no installers.
          _file(
            id: '1',
            name: 'movie.mp4',
            sizeBytes: 800 * _mib,
            category: FileCategory.videos,
            daysOld: 1,
          ),
        ],
      );

      final ListTile apkTile = tester.widget<ListTile>(
        find.byKey(const Key('smart_group_apkInstallers')),
      );
      expect(apkTile.onTap, isNull);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('smart_group_summary_apkInstallers')),
            )
            .data,
        'Nothing found',
      );

      final ListTile largeTile = tester.widget<ListTile>(
        find.byKey(const Key('smart_group_largeFiles')),
      );
      expect(largeTile.onTap, isNotNull);
    });

    testWidgets('group summaries show their own counts and sizes', (
      WidgetTester tester,
    ) async {
      await _pumpSmartScan(tester);

      // Large files: movie.mp4 800 MB + old-game.apk 500 MB.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('smart_group_summary_largeFiles')))
            .data,
        '2 files · 1.3 GB',
      );
      // APKs: tool.apk 20 MB + old-game.apk 500 MB.
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('smart_group_summary_apkInstallers')),
            )
            .data,
        '2 files · 520.0 MB',
      );
    });
  });
}
