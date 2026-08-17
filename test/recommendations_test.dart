import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/file_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation_engine.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/recommendations_card.dart';

const int _mib = 1024 * 1024;
const int _gib = 1024 * 1024 * 1024;

ScannedFile _file({
  required String id,
  required String name,
  required int sizeBytes,
  FileCategory category = FileCategory.images,
  String mimeType = 'image/png',
  int daysOld = 200,
  String folder = 'Pictures/Screenshots/',
}) {
  final DateTime now = DateTime.now();
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/$folder$name',
    uri: 'content://media/external/file/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: DateTime(
      now.year,
      now.month,
      now.day,
      12,
    ).subtract(Duration(days: daysOld)),
    mimeType: mimeType,
    relativePath: folder,
  );
}

RecommendationInputs _inputs({
  int oldScreenshotCount = 0,
  int oldScreenshotBytes = 0,
  int duplicateReclaimableBytes = 0,
  int duplicateGroupCount = 0,
  ScannedFile? largestVideo,
  int largeVideoCount = 0,
  int largeVideoBytes = 0,
}) => RecommendationInputs(
  oldScreenshotCount: oldScreenshotCount,
  oldScreenshotBytes: oldScreenshotBytes,
  duplicateReclaimableBytes: duplicateReclaimableBytes,
  duplicateGroupCount: duplicateGroupCount,
  largestVideo: largestVideo,
  largeVideoCount: largeVideoCount,
  largeVideoBytes: largeVideoBytes,
);

ScannedFile _video(int sizeBytes, {String name = 'holiday.mp4'}) => _file(
  id: 'v1',
  name: name,
  sizeBytes: sizeBytes,
  category: FileCategory.videos,
  mimeType: 'video/mp4',
  folder: 'DCIM/Camera/',
);

List<RecommendationKind> _kinds(List<Recommendation> found) =>
    found.map((Recommendation r) => r.kind).toList();

// --------------------------------------------------------------- widget stubs

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);

  final List<ScannedFile> files;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => FileScanResult.fromFiles(
    files
        .where((ScannedFile f) => f.sizeBytes >= request.minSizeBytes)
        .toList(),
    categories: request.categories,
  );
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

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

Future<List<RecommendationKind>> _pumpCard(
  WidgetTester tester, {
  required List<ScannedFile> files,
  Map<String, String> hashes = const <String, String>{},
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final List<RecommendationKind> opened = <RecommendationKind>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(_StubScanner(files)),
        fileHashRepositoryProvider.overrideWithValue(_StubHasher(hashes)),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecommendationsCard(
              onScan: () {},
              onOpen: opened.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  group('Screenshot rule: > 20 older than 90 days', () {
    test('fires above the threshold', () {
      final List<Recommendation> found = RecommendationEngine.evaluate(
        _inputs(oldScreenshotCount: 34, oldScreenshotBytes: 210 * _mib),
      );

      expect(_kinds(found), <RecommendationKind>[
        RecommendationKind.screenshotReview,
      ]);
      expect(found.single.title, 'Review old screenshots');
      // The evidence is stated, so the advice is checkable.
      expect(
        found.single.detail,
        '34 screenshots older than 90 days · 210.0 MB',
      );
    });

    test('exactly 20 does not fire, 21 does', () {
      // The rule is "> 20", not ">= 20".
      expect(
        RecommendationEngine.evaluate(_inputs(oldScreenshotCount: 20)),
        isEmpty,
      );
      expect(
        RecommendationEngine.evaluate(_inputs(oldScreenshotCount: 21)),
        hasLength(1),
      );
    });
  });

  group('Duplicate rule: > 500 MB', () {
    test('fires above the threshold and names the sets', () {
      final List<Recommendation> found = RecommendationEngine.evaluate(
        _inputs(
          duplicateReclaimableBytes: 700 * _mib,
          duplicateGroupCount: 12,
        ),
      );

      expect(_kinds(found), <RecommendationKind>[
        RecommendationKind.duplicateCleanup,
      ]);
      expect(
        found.single.detail,
        '700.0 MB recoverable across 12 sets · one copy of each is always '
        'kept',
      );
    });

    test('exactly 500 MB does not fire', () {
      expect(
        RecommendationEngine.evaluate(
          _inputs(duplicateReclaimableBytes: 500 * _mib),
        ),
        isEmpty,
      );
      expect(
        RecommendationEngine.evaluate(
          _inputs(duplicateReclaimableBytes: 500 * _mib + 1),
        ),
        hasLength(1),
      );
    });

    test('one set is described in the singular', () {
      final List<Recommendation> found = RecommendationEngine.evaluate(
        _inputs(
          duplicateReclaimableBytes: 600 * _mib,
          duplicateGroupCount: 1,
        ),
      );
      expect(found.single.detail, contains('across 1 set ·'));
    });
  });

  group('Large video rule: one video > 1 GB', () {
    test('a single oversized video is enough to fire', () {
      final List<Recommendation> found = RecommendationEngine.evaluate(
        _inputs(
          largestVideo: _video(2 * _gib),
          largeVideoCount: 1,
          largeVideoBytes: 2 * _gib,
        ),
      );

      expect(_kinds(found), <RecommendationKind>[
        RecommendationKind.largeVideoReview,
      ]);
      expect(found.single.detail, 'holiday.mp4 is 2.0 GB');
    });

    test('other large videos are mentioned when present', () {
      final List<Recommendation> found = RecommendationEngine.evaluate(
        _inputs(
          largestVideo: _video(3 * _gib),
          largeVideoCount: 3,
          largeVideoBytes: 6 * _gib,
        ),
      );
      expect(found.single.detail, contains('2 other videos over 1 GB'));
    });

    test('a video just under 1 GB does not fire', () {
      expect(
        RecommendationEngine.evaluate(
          _inputs(
            largestVideo: _video(_gib - 1),
            largeVideoCount: 0,
            largeVideoBytes: 0,
          ),
        ),
        isEmpty,
      );
      // Exactly 1 GB does fire: the tool calls that large.
      expect(
        RecommendationEngine.evaluate(
          _inputs(
            largestVideo: _video(_gib),
            largeVideoCount: 1,
            largeVideoBytes: _gib,
          ),
        ),
        hasLength(1),
      );
    });

    test('no videos at all is not an error', () {
      expect(RecommendationEngine.evaluate(_inputs()), isEmpty);
    });
  });

  group('Engine behaviour', () {
    test('a tidy device yields no advice rather than filler', () {
      final List<Recommendation> found = RecommendationEngine.evaluate(
        _inputs(
          oldScreenshotCount: 3,
          duplicateReclaimableBytes: 10 * _mib,
          largestVideo: _video(100 * _mib),
        ),
      );
      expect(found, isEmpty);
    });

    test('every rule can fire at once, biggest saving first', () {
      final List<Recommendation> found = RecommendationEngine.evaluate(
        _inputs(
          oldScreenshotCount: 40,
          oldScreenshotBytes: 300 * _mib,
          duplicateReclaimableBytes: 2 * _gib,
          duplicateGroupCount: 30,
          largestVideo: _video(4 * _gib),
          largeVideoCount: 2,
          largeVideoBytes: 5 * _gib,
        ),
      );

      // High priority (>= 1 GB) leads, ordered by size: videos 5 GB, then
      // duplicates 2 GB. Screenshots at 300 MB are medium, so they come last.
      expect(_kinds(found), <RecommendationKind>[
        RecommendationKind.largeVideoReview,
        RecommendationKind.duplicateCleanup,
        RecommendationKind.screenshotReview,
      ]);
      expect(found.first.priority, RecommendationPriority.high);
      expect(found.last.priority, RecommendationPriority.medium);
    });

    test('ordering is stable across repeated evaluation', () {
      final RecommendationInputs inputs = _inputs(
        oldScreenshotCount: 25,
        oldScreenshotBytes: 100 * _mib,
        duplicateReclaimableBytes: 600 * _mib,
        duplicateGroupCount: 4,
      );
      expect(
        _kinds(RecommendationEngine.evaluate(inputs)),
        _kinds(RecommendationEngine.evaluate(inputs)),
      );
    });

    test('the result cannot be mutated by a caller', () {
      final List<Recommendation> found = RecommendationEngine.evaluate(
        _inputs(oldScreenshotCount: 30, oldScreenshotBytes: 50 * _mib),
      );
      expect(() => found.clear(), throwsUnsupportedError);
    });

    test('thresholds match the phase spec exactly', () {
      expect(RecommendationEngine.screenshotAgeDays, 90);
      expect(RecommendationEngine.screenshotCountThreshold, 20);
      expect(RecommendationEngine.duplicateBytesThreshold, 500 * _mib);
      expect(RecommendationEngine.largeVideoBytes, _gib);
    });
  });

  group('Recommendations card', () {
    testWidgets('shows advice derived from a real scan', (
      WidgetTester tester,
    ) async {
      // 25 stale screenshots, comfortably past the count threshold.
      final List<ScannedFile> files = <ScannedFile>[
        for (int i = 0; i < 25; i++)
          _file(
            id: 's$i',
            name: 'Screenshot_$i.png',
            sizeBytes: 4 * _mib,
            daysOld: 200,
          ),
      ];

      await _pumpCard(tester, files: files);

      expect(find.byKey(const Key('recommendations_section')), findsOneWidget);
      expect(
        find.byKey(const Key('recommendation_screenshotReview')),
        findsOneWidget,
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

    testWidgets('tapping a recommendation reports its kind, nothing more', (
      WidgetTester tester,
    ) async {
      final List<ScannedFile> files = <ScannedFile>[
        for (int i = 0; i < 25; i++)
          _file(id: 's$i', name: 'Screenshot_$i.png', sizeBytes: 4 * _mib),
      ];

      final List<RecommendationKind> opened = await _pumpCard(
        tester,
        files: files,
      );

      await tester.tap(
        find.byKey(const Key('recommendation_screenshotReview')),
      );
      await tester.pumpAndSettle();

      // Advice only: the card routes, it never deletes or selects.
      expect(opened, <RecommendationKind>[
        RecommendationKind.screenshotReview,
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large video is picked up from the video scan', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        files: <ScannedFile>[
          _file(
            id: 'v1',
            name: 'wedding.mp4',
            sizeBytes: 3 * _gib,
            category: FileCategory.videos,
            mimeType: 'video/mp4',
            folder: 'DCIM/Camera/',
          ),
        ],
      );

      expect(
        find.byKey(const Key('recommendation_largeVideoReview')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('recommendation_detail_largeVideoReview')),
            )
            .data,
        'wedding.mp4 is 3.0 GB',
      );
    });

    testWidgets('a tidy device says so instead of inventing advice', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        files: <ScannedFile>[
          _file(id: 's1', name: 'Screenshot_1.png', sizeBytes: _mib),
        ],
      );

      expect(find.byKey(const Key('recommendations_section')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('recommendations_message')))
            .data,
        'Nothing needs attention right now. Your storage looks tidy.',
      );
      expect(find.byKey(const Key('recommendations_count')), findsNothing);
    });

    testWidgets('an empty device renders without error', (
      WidgetTester tester,
    ) async {
      await _pumpCard(tester, files: const <ScannedFile>[]);

      expect(find.byKey(const Key('recommendations_section')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
