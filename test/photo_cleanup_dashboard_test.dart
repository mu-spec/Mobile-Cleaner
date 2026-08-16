import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/file_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/perceptual_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_detector.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_summary.dart';
import 'package:mobile_cleaner/features/files/domain/photo_cleanup_summary.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_summary.dart';
import 'package:mobile_cleaner/features/files/domain/similar_photo_detector.dart';
import 'package:mobile_cleaner/features/photos/presentation/screens/photos_screen.dart';

const int _mib = 1024 * 1024;

ScannedFile _file({
  required String id,
  required String name,
  required int sizeBytes,
  int daysOld = 10,
  String folder = 'DCIM/Camera/',
}) {
  final DateTime now = DateTime.now();
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/$folder$name',
    uri: 'content://media/external/images/media/$id',
    sizeBytes: sizeBytes,
    category: FileCategory.images,
    dateModified: DateTime(
      now.year,
      now.month,
      now.day,
      12,
    ).subtract(Duration(days: daysOld)),
    mimeType: 'image/jpeg',
    relativePath: folder,
  );
}

/// A library exercising all three tools, including one photo that belongs to
/// two of them at once.
List<ScannedFile> _fixture() => <ScannedFile>[
  // Duplicate pair, 6 MB each: 6 MB reclaimable.
  _file(id: '1', name: 'trip.jpg', sizeBytes: 6 * _mib, daysOld: 80),
  _file(id: '2', name: 'trip (1).jpg', sizeBytes: 6 * _mib, daysOld: 20),
  // Two screenshots, 2 MB and 3 MB: 5 MB.
  _file(
    id: '3',
    name: 'Screenshot_1.png',
    sizeBytes: 2 * _mib,
    folder: 'Pictures/Screenshots/',
  ),
  _file(
    id: '4',
    name: 'Screenshot_2.png',
    sizeBytes: 3 * _mib,
    folder: 'Pictures/Screenshots/',
  ),
  // A big photo, 30 MB, unique.
  _file(id: '5', name: 'panorama.jpg', sizeBytes: 30 * _mib),
  // Small and unremarkable: counted by nothing.
  _file(id: '6', name: 'thumb.jpg', sizeBytes: 200 * 1024),
];

String _uri(String id) => 'content://media/external/images/media/$id';

Map<String, String> _hashes() => <String, String>{
  _uri('1'): 'aaa',
  _uri('2'): 'aaa',
};

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);

  final List<ScannedFile> files;
  final List<FileScanRequest> requests = <FileScanRequest>[];

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    requests.add(request);
    return FileScanResult.fromFiles(
      files
          .where((ScannedFile f) => f.sizeBytes >= request.minSizeBytes)
          .toList(),
      categories: request.categories,
    );
  }
}

class _StubHasher implements FileHashRepository {
  _StubHasher(this.hashes);

  final Map<String, String> hashes;

  @override
  Future<Map<String, String>> hashFiles(List<ScannedFile> files) async =>
      <String, String>{
        for (final ScannedFile f in files)
          if (hashes.containsKey(f.uri)) f.uri: hashes[f.uri]!,
      };
}

/// No two photos in the dashboard fixture look alike, so Similar Photos
/// reports nothing and the other rows stay isolated from it.
class _NoFingerprints implements PerceptualHashRepository {
  const _NoFingerprints();

  @override
  Future<Map<String, String>> hashImages(List<ScannedFile> files) async =>
      const <String, String>{};
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

Future<void> _pumpPhotos(
  WidgetTester tester, {
  List<ScannedFile>? files,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(
          _StubScanner(files ?? _fixture()),
        ),
        fileHashRepositoryProvider.overrideWithValue(_StubHasher(_hashes())),
        perceptualHashRepositoryProvider.overrideWithValue(
          const _NoFingerprints(),
        ),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
      ],
      child: const MaterialApp(home: PhotosScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Builds the summary directly, without widgets.
PhotoCleanupSummary _summary({
  List<ScannedFile>? files,
  Map<String, String>? similar,
}) {
  final List<ScannedFile> source = files ?? _fixture();
  return PhotoCleanupSummary.from(
    duplicates: DuplicateDetector.group(source, _hashes()),
    screenshots: ScreenshotSummary.from(source, ScreenshotGroup.all),
    largePhotos: LargePhotoSummary.from(source, LargePhotoFilter.over5mb),
    similarPhotos: SimilarPhotoDetector.group(
      source,
      similar ?? const <String, String>{},
    ),
  );
}

void main() {
  group('PhotoCleanupSummary', () {
    test('lists the four tools in dashboard order', () {
      expect(
        _summary().entries.map((PhotoCleanupEntry e) => e.tool),
        <PhotoCleanupTool>[
          PhotoCleanupTool.duplicatePhotos,
          PhotoCleanupTool.screenshots,
          PhotoCleanupTool.largePhotos,
          PhotoCleanupTool.similarPhotos,
        ],
      );
    });

    test('duplicates report reclaimable space, not occupied space', () {
      final PhotoCleanupEntry entry = _summary().entryFor(
        PhotoCleanupTool.duplicatePhotos,
      );
      // Two 6 MB copies occupy 12 MB but only one can go.
      expect(entry.bytes, 6 * _mib);
      expect(entry.itemCount, 1);
    });

    test('screenshots and large photos report their own totals', () {
      final PhotoCleanupSummary summary = _summary();
      expect(summary.entryFor(PhotoCleanupTool.screenshots).bytes, 5 * _mib);
      // 6 + 6 + 30 MB are all at or over the 5 MB threshold.
      expect(summary.entryFor(PhotoCleanupTool.largePhotos).bytes, 42 * _mib);
    });

    test('Similar Photos now carries a real figure, marked as an estimate', () {
      // trip.jpg and trip (1).jpg given near-identical fingerprints.
      final PhotoCleanupSummary summary = _summary(
        similar: <String, String>{
          _uri('1'): 'f0f0f0f0f0f0f0f0aaaaaaaaaaaaaaaa',
          _uri('2'): 'f0f0f0f0f0f0f0f1aaaaaaaaaaaaaaab',
        },
      );
      final PhotoCleanupEntry entry = summary.entryFor(
        PhotoCleanupTool.similarPhotos,
      );

      expect(entry.hasFigure, isTrue);
      expect(entry.isEstimate, isTrue);
      // Same size, so keeping the larger leaves one 6 MB shot removable.
      expect(entry.bytes, 6 * _mib);
      expect(PhotoCleanupTool.similarPhotos.isAvailable, isTrue);
    });

    test('similar photos never inflate the headline total', () {
      final PhotoCleanupSummary withSimilar = _summary(
        similar: <String, String>{
          _uri('1'): 'f0f0f0f0f0f0f0f0aaaaaaaaaaaaaaaa',
          _uri('2'): 'f0f0f0f0f0f0f0f1aaaaaaaaaaaaaaab',
        },
      );
      // The headline is unchanged: similar shots are not interchangeable, so
      // their space is not promised as recoverable.
      expect(withSimilar.totalBytes, _summary().totalBytes);
    });

    test('the headline counts an overlapping photo once', () {
      final PhotoCleanupSummary summary = _summary();
      // Rows sum to 6 + 5 + 42 = 53 MB, but the duplicate copies are also
      // large photos, so the truthful total is lower.
      expect(summary.hasOverlap, isTrue);
      // Unique: trip 6 + trip(1) 6 + two screenshots 5 + panorama 30.
      expect(summary.totalBytes, 47 * _mib);
      expect(summary.totalPhotos, 5);
    });

    test('findings are ranked by size, pending tools excluded', () {
      expect(
        _summary().rankedFindings.map((PhotoCleanupEntry e) => e.tool),
        <PhotoCleanupTool>[
          PhotoCleanupTool.largePhotos,
          PhotoCleanupTool.duplicatePhotos,
          PhotoCleanupTool.screenshots,
        ],
      );
    });

    test('a tidy library is empty but still lists every tool', () {
      final PhotoCleanupSummary summary = _summary(
        files: <ScannedFile>[
          _file(id: '1', name: 'a.jpg', sizeBytes: 100 * 1024),
        ],
      );
      expect(summary.isEmpty, isTrue);
      expect(summary.totalBytes, 0);
      expect(summary.entries, hasLength(4));
      expect(summary.hasOverlap, isFalse);
    });
  });

  group('Photo Cleanup dashboard', () {
    testWidgets('shows the Photo Cleanup heading and headline total', (
      WidgetTester tester,
    ) async {
      await _pumpPhotos(tester);

      expect(find.byKey(const Key('photo_cleanup_card')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('photo_cleanup_heading')))
            .data,
        'Photo Cleanup',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('photo_cleanup_total_bytes')))
            .data,
        '47.0 MB',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('photo_cleanup_total_photos')))
            .data,
        'across 5 photos',
      );
    });

    testWidgets('lists all four tools with their figures', (
      WidgetTester tester,
    ) async {
      await _pumpPhotos(tester);

      String value(String tool) => tester
          .widget<Text>(find.byKey(Key('photo_tool_value_$tool')))
          .data!;

      expect(value('duplicatePhotos'), '6.0 MB');
      expect(value('screenshots'), '5.0 MB');
      expect(value('largePhotos'), '42.0 MB');
      // Nothing looks alike in this fixture.
      expect(value('similarPhotos'), 'None');
    });

    testWidgets('all four tools are named', (WidgetTester tester) async {
      await _pumpPhotos(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('photo_tool_note_similarPhotos')),
            )
            .data,
        'Near-identical shots of the same scene',
      );
      expect(find.text('Duplicate Photos'), findsOneWidget);
      expect(find.text('Screenshots'), findsOneWidget);
      expect(find.text('Large Photos'), findsOneWidget);
      expect(find.text('Similar Photos'), findsOneWidget);
    });

    testWidgets('overlap is disclosed rather than hidden', (
      WidgetTester tester,
    ) async {
      await _pumpPhotos(tester);

      expect(
        find.byKey(const Key('photo_cleanup_overlap_note')),
        findsOneWidget,
      );
    });

    testWidgets('every tool row is tappable', (
      WidgetTester tester,
    ) async {
      await _pumpPhotos(tester);

      for (final String tool in <String>[
        'duplicatePhotos',
        'screenshots',
        'largePhotos',
        'similarPhotos',
      ]) {
        final InkWell row = tester.widget<InkWell>(
          find.byKey(Key('photo_tool_$tool')),
        );
        expect(row.onTap, isNotNull);
      }
    });

    testWidgets('Review Photos is enabled when something was found', (
      WidgetTester tester,
    ) async {
      await _pumpPhotos(tester);

      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(const Key('photo_review_button')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('a tidy library disables Review and says so', (
      WidgetTester tester,
    ) async {
      await _pumpPhotos(
        tester,
        files: <ScannedFile>[
          _file(id: '1', name: 'a.jpg', sizeBytes: 100 * 1024),
        ],
      );

      expect(find.byKey(const Key('photo_cleanup_clean')), findsOneWidget);
      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(const Key('photo_review_button')),
      );
      expect(button.onPressed, isNull);
      // The tools are still listed, so the tab is never blank.
      expect(find.byKey(const Key('photo_tool_screenshots')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('photo_tool_value_screenshots')))
            .data,
        'None',
      );
    });

    testWidgets('the dashboard reuses the tool scans, never its own', (
      WidgetTester tester,
    ) async {
      final _StubScanner scanner = _StubScanner(_fixture());
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileScannerRepositoryProvider.overrideWithValue(scanner),
            fileHashRepositoryProvider.overrideWithValue(
              _StubHasher(_hashes()),
            ),
            perceptualHashRepositoryProvider.overrideWithValue(
              const _NoFingerprints(),
            ),
            thumbnailRepositoryProvider.overrideWithValue(
              const _NoThumbnails(),
            ),
          ],
          child: const MaterialApp(home: PhotosScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly the four tool scans: duplicates, screenshots, large photos,
      // similar photos. Never a fifth scan of its own.
      expect(scanner.requests, hasLength(4));
    });
  });
}
