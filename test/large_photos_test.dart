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
import 'package:mobile_cleaner/features/files/domain/large_photo_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_summary.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/large_photos_screen.dart';

const int _mib = 1024 * 1024;

ScannedFile _photo({
  required String id,
  required String name,
  required int sizeBytes,
  FileCategory category = FileCategory.images,
  String? mimeType = 'image/jpeg',
  String? uri,
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/DCIM/Camera/$name',
    uri: uri ?? 'content://media/external/images/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: DateTime(2026, 5, 1),
    mimeType: mimeType,
  );
}

/// Photos either side of every threshold, plus non-photos to exclude.
List<ScannedFile> _fixture() => <ScannedFile>[
  _photo(id: '1', name: 'raw-sunset.jpg', sizeBytes: 30 * _mib),
  _photo(id: '2', name: 'portrait.jpg', sizeBytes: 12 * _mib),
  _photo(id: '3', name: 'snapshot.jpg', sizeBytes: 6 * _mib),
  // Below every threshold.
  _photo(id: '4', name: 'thumbnail.jpg', sizeBytes: 2 * _mib),
  // A large video: must never appear in a photos tool.
  _photo(
    id: '5',
    name: 'holiday.mp4',
    sizeBytes: 400 * _mib,
    category: FileCategory.videos,
    mimeType: 'video/mp4',
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
    // Mirror the native contract: the scanner honours minSizeBytes and the
    // requested categories.
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

class _RecordingDelete implements DeleteRepository {
  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async =>
      DeleteResult(deletedFiles: files, failures: const <DeleteFailure>[]);
}

Future<_StubScanner> _pumpLargePhotos(
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
      child: const MaterialApp(home: LargePhotosScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return scanner;
}

void main() {
  group('LargePhotoFilter', () {
    test('offers exactly the three suggested thresholds', () {
      expect(LargePhotoFilter.values, <LargePhotoFilter>[
        LargePhotoFilter.over5mb,
        LargePhotoFilter.over10mb,
        LargePhotoFilter.over20mb,
      ]);
      expect(
        LargePhotoFilter.values.map((LargePhotoFilter f) => f.label).toList(),
        <String>['5 MB+', '10 MB+', '20 MB+'],
      );
    });

    test('uses correct byte bounds', () {
      expect(LargePhotoFilter.over5mb.minBytes, 5 * _mib);
      expect(LargePhotoFilter.over10mb.minBytes, 10 * _mib);
      expect(LargePhotoFilter.over20mb.minBytes, 20 * _mib);
      expect(LargePhotoFilter.lowestBound, 5 * _mib);
      expect(LargePhotoFilter.defaultFilter, LargePhotoFilter.over5mb);
    });

    test('matches on an inclusive bound', () {
      expect(LargePhotoFilter.over5mb.matches(5 * _mib), isTrue);
      expect(LargePhotoFilter.over5mb.matches(5 * _mib - 1), isFalse);
      expect(LargePhotoFilter.over20mb.matches(20 * _mib), isTrue);
    });
  });

  group('LargePhotoSummary', () {
    test('filters and totals at each threshold', () {
      final List<ScannedFile> files = _fixture();

      LargePhotoSummary summaryFor(LargePhotoFilter filter) =>
          LargePhotoSummary.from(files, filter);

      final LargePhotoSummary over5 = summaryFor(LargePhotoFilter.over5mb);
      expect(over5.fileCount, 3);
      expect(over5.totalBytes, (30 + 12 + 6) * _mib);

      final LargePhotoSummary over10 = summaryFor(LargePhotoFilter.over10mb);
      expect(over10.fileCount, 2);
      expect(over10.totalBytes, (30 + 12) * _mib);

      final LargePhotoSummary over20 = summaryFor(LargePhotoFilter.over20mb);
      expect(over20.fileCount, 1);
      expect(over20.totalBytes, 30 * _mib);
    });

    test('excludes videos even when they are far larger', () {
      final LargePhotoSummary summary = LargePhotoSummary.from(
        _fixture(),
        LargePhotoFilter.over5mb,
      );
      expect(
        summary.files.map((ScannedFile f) => f.name),
        isNot(contains('holiday.mp4')),
      );
    });

    test('classifies by MIME type over category', () {
      // An image filed under Downloads is still a photo.
      expect(
        LargePhotoSummary.isPhoto(
          _photo(
            id: '1',
            name: 'saved.png',
            sizeBytes: _mib,
            category: FileCategory.downloads,
            mimeType: 'image/png',
          ),
        ),
        isTrue,
      );
      // A video filed under Images is not.
      expect(
        LargePhotoSummary.isPhoto(
          _photo(
            id: '2',
            name: 'clip.mp4',
            sizeBytes: _mib,
            mimeType: 'video/mp4',
          ),
        ),
        isFalse,
      );
      // No MIME type: fall back to the category.
      expect(
        LargePhotoSummary.isPhoto(
          _photo(id: '3', name: 'unknown', sizeBytes: _mib, mimeType: null),
        ),
        isTrue,
      );
    });

    test('sorts largest first and reports the biggest photo', () {
      final LargePhotoSummary summary = LargePhotoSummary.from(
        _fixture(),
        LargePhotoFilter.over5mb,
      );
      expect(summary.files.first.name, 'raw-sunset.jpg');
      expect(summary.files.last.name, 'snapshot.jpg');
      expect(summary.largestFile?.name, 'raw-sunset.jpg');
    });

    test('counts a photo reported twice only once', () {
      const String sharedUri = 'content://media/external/file/media/9';
      final LargePhotoSummary summary = LargePhotoSummary.from(<ScannedFile>[
        _photo(id: '9', name: 'a.jpg', sizeBytes: 8 * _mib, uri: sharedUri),
        _photo(
          id: '9',
          name: 'a.jpg',
          sizeBytes: 8 * _mib,
          category: FileCategory.downloads,
          uri: sharedUri,
        ),
      ], LargePhotoFilter.over5mb);

      expect(summary.fileCount, 1);
      expect(summary.totalBytes, 8 * _mib);
    });

    test('reports the average size', () {
      final LargePhotoSummary summary = LargePhotoSummary.from(
        _fixture(),
        LargePhotoFilter.over10mb,
      );
      // (30 + 12) / 2 = 21 MB
      expect(summary.averageBytes, 21 * _mib);
    });

    test('is empty when nothing is large enough', () {
      final LargePhotoSummary summary = LargePhotoSummary.from(<ScannedFile>[
        _photo(id: '1', name: 'small.jpg', sizeBytes: _mib),
      ], LargePhotoFilter.over5mb);

      expect(summary.isEmpty, isTrue);
      expect(summary.totalBytes, 0);
      expect(summary.largestFile, isNull);
      expect(summary.averageBytes, 0);
    });
  });

  group('Large Photos screen', () {
    testWidgets('scans only images, at the lowest threshold', (
      WidgetTester tester,
    ) async {
      final _StubScanner scanner = await _pumpLargePhotos(tester);

      expect(scanner.lastRequest?.categories, <FileCategory>[
        FileCategory.images,
      ]);
      expect(scanner.lastRequest?.minSizeBytes, LargePhotoFilter.lowestBound);
    });

    testWidgets('shows the three threshold chips', (WidgetTester tester) async {
      await _pumpLargePhotos(tester);

      for (final LargePhotoFilter option in LargePhotoFilter.values) {
        expect(
          find.byKey(Key('large_photo_filter_${option.name}')),
          findsOneWidget,
          reason: '${option.label} chip should be visible',
        );
      }
    });

    testWidgets('displays the count and total size', (
      WidgetTester tester,
    ) async {
      await _pumpLargePhotos(tester);

      expect(find.byKey(const Key('large_photos_total_card')), findsOneWidget);
      // 30 + 12 + 6 MB
      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_photos_total_bytes')))
            .data,
        '48.0 MB',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('large_photos_count'))).data,
        '3 photos over 5 MB',
      );
    });

    testWidgets('lists photos largest first and hides videos', (
      WidgetTester tester,
    ) async {
      await _pumpLargePhotos(tester);

      expect(find.text('raw-sunset.jpg'), findsOneWidget);
      expect(find.text('snapshot.jpg'), findsOneWidget);
      // Below the threshold.
      expect(find.text('thumbnail.jpg'), findsNothing);
      // A video, however large.
      expect(find.text('holiday.mp4'), findsNothing);

      expect(
        tester.getTopLeft(find.text('raw-sunset.jpg')).dy,
        lessThan(tester.getTopLeft(find.text('snapshot.jpg')).dy),
      );
    });

    testWidgets('raising the threshold narrows the list and total', (
      WidgetTester tester,
    ) async {
      await _pumpLargePhotos(tester);

      await tester.tap(find.byKey(const Key('large_photo_filter_over20mb')));
      await tester.pumpAndSettle();

      expect(find.text('raw-sunset.jpg'), findsOneWidget);
      expect(find.text('portrait.jpg'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_photos_total_bytes')))
            .data,
        '30.0 MB',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('large_photos_count'))).data,
        '1 photo over 20 MB',
      );
    });

    testWidgets('changing the threshold does not rescan', (
      WidgetTester tester,
    ) async {
      final _StubScanner scanner = await _pumpLargePhotos(tester);
      expect(scanner.scanCount, 1);

      await tester.tap(find.byKey(const Key('large_photo_filter_over10mb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('large_photo_filter_over20mb')));
      await tester.pumpAndSettle();

      expect(scanner.scanCount, 1);
    });

    testWidgets('selecting reveals the action bar with count and size', (
      WidgetTester tester,
    ) async {
      await _pumpLargePhotos(tester);
      expect(
        find.byKey(const Key('large_photos_selection_bar')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('large_photos_selection_bar')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_photos_selection_count')))
            .data,
        '1 selected',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_photos_selection_bytes')))
            .data,
        '30.0 MB',
      );
    });

    testWidgets('select all covers every visible photo', (
      WidgetTester tester,
    ) async {
      await _pumpLargePhotos(tester);

      await tester.tap(find.byKey(const Key('large_photos_select_all')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_photos_selection_count')))
            .data,
        '3 selected',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_photos_selection_bytes')))
            .data,
        '48.0 MB',
      );
    });

    testWidgets('raising the threshold drops now-hidden selections', (
      WidgetTester tester,
    ) async {
      await _pumpLargePhotos(tester);

      await tester.tap(find.byKey(const Key('large_photos_select_all')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('large_photo_filter_over20mb')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_photos_selection_count')))
            .data,
        '1 selected',
      );
    });

    testWidgets('delete is enabled once something is selected', (
      WidgetTester tester,
    ) async {
      await _pumpLargePhotos(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();

      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(const Key('large_photos_selection_delete')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows a reassuring empty state', (WidgetTester tester) async {
      await _pumpLargePhotos(
        tester,
        files: <ScannedFile>[
          _photo(id: '1', name: 'small.jpg', sizeBytes: _mib),
        ],
      );

      expect(find.byKey(const Key('large_photos_empty')), findsOneWidget);
      expect(find.text('No photos over 5 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
