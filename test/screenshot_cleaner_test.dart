import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_summary.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/screenshot_cleaner_screen.dart';

const int _mib = 1024 * 1024;

/// Fixed clock for the pure domain tests.
final DateTime _now = DateTime(2026, 8, 15, 12);

/// Midday today, so a daylight-saving shift cannot move a fixture across a
/// day boundary and change its computed age.
DateTime _middayToday() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 12);
}

ScannedFile _image({
  required String id,
  required String name,
  int sizeBytes = 2 * _mib,
  int daysOld = 1,
  String relativePath = 'Pictures/Screenshots/',
  FileCategory category = FileCategory.images,
  String? mimeType = 'image/png',
  DateTime? base,
  String? uri,
}) {
  final DateTime reference = base ?? _middayToday();
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/$relativePath$name',
    uri: uri ?? 'content://media/external/images/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: reference.subtract(Duration(days: daysOld)),
    mimeType: mimeType,
    relativePath: relativePath,
  );
}

/// Screenshots either side of both thresholds, plus images that must not
/// be mistaken for screenshots.
List<ScannedFile> _fixture({DateTime? base}) => <ScannedFile>[
  _image(
    id: '1',
    name: 'Screenshot_20260814-101500.png',
    sizeBytes: 3 * _mib,
    daysOld: 1,
    base: base,
  ),
  _image(
    id: '2',
    name: 'Screenshot_20260601-090000.png',
    sizeBytes: 5 * _mib,
    daysOld: 60,
    base: base,
  ),
  _image(
    id: '3',
    name: 'Screenshot_20250101-120000.png',
    sizeBytes: 4 * _mib,
    daysOld: 300,
    base: base,
  ),
  // A camera photo: not a screenshot.
  _image(
    id: '4',
    name: 'IMG_20260101.jpg',
    sizeBytes: 8 * _mib,
    daysOld: 200,
    relativePath: 'DCIM/Camera/',
    mimeType: 'image/jpeg',
    base: base,
  ),
];

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);

  final List<ScannedFile> files;
  FileScanRequest? lastRequest;
  int scanCount = 0;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    scanCount++;
    lastRequest = request;
    return FileScanResult.fromFiles(files, categories: request.categories);
  }
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

class _RecordingDelete implements DeleteRepository {
  final List<List<ScannedFile>> requests = <List<ScannedFile>>[];

  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async {
    requests.add(files);
    return DeleteResult(
      deletedFiles: files,
      failures: const <DeleteFailure>[],
    );
  }
}

Future<_StubScanner> _pumpCleaner(
  WidgetTester tester, {
  List<ScannedFile>? files,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubScanner scanner = _StubScanner(files ?? _fixture());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(scanner),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
        deleteRepositoryProvider.overrideWithValue(_RecordingDelete()),
      ],
      child: const MaterialApp(home: ScreenshotCleanerScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return scanner;
}

void main() {
  group('ScreenshotDetector', () {
    test('recognises the standard folder', () {
      expect(
        ScreenshotDetector.isScreenshot(
          _image(id: '1', name: 'photo.png', relativePath: 'Pictures/Screenshots/'),
        ),
        isTrue,
      );
      expect(
        ScreenshotDetector.isScreenshot(
          _image(id: '2', name: 'photo.png', relativePath: 'DCIM/Screenshots/'),
        ),
        isTrue,
      );
    });

    test('recognises the filename prefix outside the folder', () {
      // A screenshot moved into the camera folder is still a screenshot.
      expect(
        ScreenshotDetector.isScreenshot(
          _image(
            id: '1',
            name: 'Screenshot_20260101-101500.png',
            relativePath: 'DCIM/Camera/',
          ),
        ),
        isTrue,
      );
    });

    test('is case insensitive', () {
      expect(
        ScreenshotDetector.isScreenshot(
          _image(id: '1', name: 'photo.png', relativePath: 'pictures/SCREENSHOTS/'),
        ),
        isTrue,
      );
      expect(
        ScreenshotDetector.isScreenshot(
          _image(id: '2', name: 'SCREENSHOT_1.png', relativePath: 'DCIM/Camera/'),
        ),
        isTrue,
      );
    });

    test('ignores ordinary photos', () {
      expect(
        ScreenshotDetector.isScreenshot(
          _image(
            id: '1',
            name: 'IMG_20260101.jpg',
            relativePath: 'DCIM/Camera/',
            mimeType: 'image/jpeg',
          ),
        ),
        isFalse,
      );
    });

    test('does not match a lookalike folder name', () {
      // "MyScreenshotsBackup" is a different folder and must not match.
      expect(
        ScreenshotDetector.isScreenshot(
          _image(
            id: '1',
            name: 'photo.png',
            relativePath: 'Pictures/MyScreenshotsBackup/',
          ),
        ),
        isFalse,
      );
    });

    test('ignores non-images even inside the screenshots folder', () {
      // A screen recording is a video, not a screenshot.
      expect(
        ScreenshotDetector.isScreenshot(
          _image(
            id: '1',
            name: 'recording.mp4',
            relativePath: 'Pictures/Screenshots/',
            category: FileCategory.videos,
            mimeType: 'video/mp4',
          ),
        ),
        isFalse,
      );
    });

    test('falls back to the full path when relativePath is absent', () {
      final ScannedFile file = ScannedFile(
        id: '1',
        name: 'shot.png',
        path: '/storage/emulated/0/Pictures/Screenshots/shot.png',
        uri: 'content://media/external/images/media/1',
        sizeBytes: _mib,
        category: FileCategory.images,
        dateModified: _now,
      );
      expect(ScreenshotDetector.isScreenshot(file), isTrue);
    });
  });

  group('ScreenshotGroup', () {
    test('offers exactly the three required groups', () {
      expect(ScreenshotGroup.values, <ScreenshotGroup>[
        ScreenshotGroup.all,
        ScreenshotGroup.days30,
        ScreenshotGroup.days90,
      ]);
      expect(
        ScreenshotGroup.values.map((ScreenshotGroup g) => g.label),
        <String>['All screenshots', '30+ days', '90+ days'],
      );
      expect(ScreenshotGroup.defaultGroup, ScreenshotGroup.all);
    });

    test('the all group ignores age entirely', () {
      expect(ScreenshotGroup.all.matches(_now, now: _now), isTrue);
      expect(
        ScreenshotGroup.all.matches(
          DateTime.fromMillisecondsSinceEpoch(0),
          now: _now,
        ),
        isTrue,
      );
    });

    test('age bounds are inclusive', () {
      expect(
        ScreenshotGroup.days30.matches(
          _now.subtract(const Duration(days: 30)),
          now: _now,
        ),
        isTrue,
      );
      expect(
        ScreenshotGroup.days30.matches(
          _now.subtract(const Duration(days: 29)),
          now: _now,
        ),
        isFalse,
      );
    });

    test('an unknown timestamp is never old', () {
      final DateTime unknown = DateTime.fromMillisecondsSinceEpoch(0);
      expect(ScreenshotGroup.days30.matches(unknown, now: _now), isFalse);
      expect(ScreenshotGroup.days90.matches(unknown, now: _now), isFalse);
    });
  });

  group('ScreenshotSummary', () {
    test('counts and totals each group', () {
      final List<ScannedFile> files = _fixture(base: _now);

      ScreenshotSummary summaryFor(ScreenshotGroup group) =>
          ScreenshotSummary.from(files, group, now: _now);

      final ScreenshotSummary all = summaryFor(ScreenshotGroup.all);
      expect(all.fileCount, 3);
      expect(all.totalBytes, (3 + 5 + 4) * _mib);

      final ScreenshotSummary d30 = summaryFor(ScreenshotGroup.days30);
      expect(d30.fileCount, 2);
      expect(d30.totalBytes, (5 + 4) * _mib);

      final ScreenshotSummary d90 = summaryFor(ScreenshotGroup.days90);
      expect(d90.fileCount, 1);
      expect(d90.totalBytes, 4 * _mib);
    });

    test('excludes the camera photo from every group', () {
      for (final ScreenshotGroup group in ScreenshotGroup.values) {
        final ScreenshotSummary summary = ScreenshotSummary.from(
          _fixture(base: _now),
          group,
          now: _now,
        );
        expect(
          summary.files.map((ScannedFile f) => f.name),
          isNot(contains('IMG_20260101.jpg')),
          reason: '${group.label} must not include a camera photo',
        );
      }
    });

    test('sorts newest first', () {
      final ScreenshotSummary summary = ScreenshotSummary.from(
        _fixture(base: _now),
        ScreenshotGroup.all,
        now: _now,
      );
      expect(summary.files.first.name, 'Screenshot_20260814-101500.png');
      expect(summary.files.last.name, 'Screenshot_20250101-120000.png');
    });

    test('counts a screenshot reported twice only once', () {
      const String sharedUri = 'content://media/external/file/media/9';
      final ScreenshotSummary summary = ScreenshotSummary.from(<ScannedFile>[
        _image(id: '9', name: 'Screenshot_a.png', uri: sharedUri, base: _now),
        _image(id: '9', name: 'Screenshot_a.png', uri: sharedUri, base: _now),
      ], ScreenshotGroup.all, now: _now);

      expect(summary.fileCount, 1);
      expect(summary.totalBytes, 2 * _mib);
    });

    test('reports the largest screenshot', () {
      final ScreenshotSummary summary = ScreenshotSummary.from(
        _fixture(base: _now),
        ScreenshotGroup.all,
        now: _now,
      );
      expect(summary.largestFile?.name, 'Screenshot_20260601-090000.png');
    });

    test('is empty when no screenshots exist', () {
      final ScreenshotSummary summary = ScreenshotSummary.from(<ScannedFile>[
        _image(
          id: '1',
          name: 'IMG_1.jpg',
          relativePath: 'DCIM/Camera/',
          mimeType: 'image/jpeg',
          base: _now,
        ),
      ], ScreenshotGroup.all, now: _now);

      expect(summary.isEmpty, isTrue);
      expect(summary.totalBytes, 0);
      expect(summary.largestFile, isNull);
    });
  });

  group('Screenshot cleaner screen', () {
    testWidgets('scans only images', (WidgetTester tester) async {
      final _StubScanner scanner = await _pumpCleaner(tester);

      expect(scanner.lastRequest?.categories, <FileCategory>[
        FileCategory.images,
      ]);
      // No size floor: screenshots are small.
      expect(scanner.lastRequest?.minSizeBytes, 0);
    });

    testWidgets('shows the three group chips', (WidgetTester tester) async {
      await _pumpCleaner(tester);

      for (final ScreenshotGroup group in ScreenshotGroup.values) {
        expect(
          find.byKey(Key('screenshot_group_${group.name}')),
          findsOneWidget,
          reason: '${group.label} chip should be visible',
        );
      }
    });

    testWidgets('displays the count and total size', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      expect(find.byKey(const Key('screenshot_total_card')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('screenshot_count'))).data,
        '3',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('screenshot_total_bytes')))
            .data,
        '12.0 MB',
      );
    });

    testWidgets('lists screenshots and hides ordinary photos', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      expect(find.text('Screenshot_20260814-101500.png'), findsOneWidget);
      expect(find.text('IMG_20260101.jpg'), findsNothing);
    });

    testWidgets('narrowing the group shrinks the count and size', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('screenshot_group_days90')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('screenshot_count'))).data,
        '1',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('screenshot_total_bytes')))
            .data,
        '4.0 MB',
      );
      expect(find.text('Screenshot_20260814-101500.png'), findsNothing);
    });

    testWidgets('changing group does not trigger another scan', (
      WidgetTester tester,
    ) async {
      final _StubScanner scanner = await _pumpCleaner(tester);
      expect(scanner.scanCount, 1);

      await tester.tap(find.byKey(const Key('screenshot_group_days30')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('screenshot_group_days90')));
      await tester.pumpAndSettle();

      expect(scanner.scanCount, 1);
    });

    testWidgets('selecting reveals the bar with count and size', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);
      expect(find.byKey(const Key('screenshot_selection_bar')), findsNothing);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('screenshot_selection_bar')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('screenshot_selection_count')))
            .data,
        '1 selected',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('screenshot_selection_bytes')))
            .data,
        '3.0 MB',
      );
    });

    testWidgets('select all covers every visible screenshot', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('screenshot_select_all')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('screenshot_selection_count')))
            .data,
        '3 selected',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('screenshot_selection_bytes')))
            .data,
        '12.0 MB',
      );
    });

    testWidgets('narrowing the group drops now-hidden selections', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('screenshot_select_all')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('screenshot_group_days90')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('screenshot_selection_count')))
            .data,
        '1 selected',
      );
    });

    testWidgets('the app bar reflects the selection', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('screenshot_title'))).data,
        '1 selected',
      );

      await tester.tap(find.byKey(const Key('screenshot_cancel_selection')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('screenshot_title'))).data,
        'Screenshots',
      );
    });

    testWidgets('delete is enabled once something is selected', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();

      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(const Key('screenshot_selection_delete')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows an empty state when nothing matches', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(
        tester,
        files: <ScannedFile>[
          _image(
            id: '1',
            name: 'IMG_1.jpg',
            relativePath: 'DCIM/Camera/',
            mimeType: 'image/jpeg',
          ),
        ],
      );

      expect(find.byKey(const Key('screenshot_empty')), findsOneWidget);
      expect(find.text('No screenshots found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
