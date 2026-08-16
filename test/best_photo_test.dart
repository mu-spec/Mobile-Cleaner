import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/perceptual_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/photo_quality_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/best_photo_scorer.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/photo_quality.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/similar_photos_screen.dart';

const int _mib = 1024 * 1024;
const int _mp = 1000000;

/// Gradient hashes 4 bits apart, so the three shots form one group.
const String _dA = '0000000000000000';
const String _dB = '000000000000000f';
const String _dC = '00000000000000ff';
const String _aBase = '0000000000000000';

ScannedFile _file({
  required String id,
  required String name,
  int sizeBytes = 4 * _mib,
  int minutesOld = 0,
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/DCIM/Camera/$name',
    uri: 'content://media/external/images/media/$id',
    sizeBytes: sizeBytes,
    category: FileCategory.images,
    dateModified: DateTime(
      2026,
      3,
      1,
      12,
    ).subtract(Duration(minutes: minutesOld)),
    mimeType: 'image/jpeg',
    relativePath: 'DCIM/Camera/',
  );
}

String _uri(String id) => 'content://media/external/images/media/$id';

PhotoQuality _quality({
  required double sharpness,
  int width = 4000,
  int height = 3000,
}) => PhotoQuality(
  width: width,
  height: height,
  pixels: width * height,
  sharpness: sharpness,
);

/// Three shots of one scene: id 1 sharp, id 2 badly soft, id 3 middling.
List<ScannedFile> _fixture() => <ScannedFile>[
  _file(id: '1', name: 'shot_a.jpg', minutesOld: 30),
  _file(id: '2', name: 'shot_b.jpg', minutesOld: 29),
  _file(id: '3', name: 'shot_c.jpg', minutesOld: 28),
];

Map<String, String> _fingerprints() => <String, String>{
  _uri('1'): '$_dA$_aBase',
  _uri('2'): '$_dB$_aBase',
  _uri('3'): '$_dC$_aBase',
};

/// Equal resolution, so sharpness alone decides.
/// Ratios: 1.0, 0.25, 0.75. Scores: 1.0, 0.5125, 0.8375. Lead 0.1625.
Map<String, PhotoQuality> _qualities() => <String, PhotoQuality>{
  _uri('1'): _quality(sharpness: 400),
  _uri('2'): _quality(sharpness: 100),
  _uri('3'): _quality(sharpness: 300),
};

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

class _StubFingerprinter implements PerceptualHashRepository {
  _StubFingerprinter(this.hashes);

  final Map<String, String> hashes;

  @override
  Future<Map<String, String>> hashImages(List<ScannedFile> files) async =>
      <String, String>{
        for (final ScannedFile f in files)
          if (hashes.containsKey(f.uri)) f.uri: hashes[f.uri]!,
      };
}

class _StubQuality implements PhotoQualityRepository {
  _StubQuality(this.qualities);

  final Map<String, PhotoQuality> qualities;
  final List<List<String>> requests = <List<String>>[];

  @override
  Future<Map<String, PhotoQuality>> analyzePhotos(
    List<ScannedFile> files,
  ) async {
    requests.add(files.map((ScannedFile f) => f.uri).toList());
    return <String, PhotoQuality>{
      for (final ScannedFile f in files)
        if (qualities.containsKey(f.uri)) f.uri: qualities[f.uri]!,
    };
  }
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

class _NoopDelete implements DeleteRepository {
  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async =>
      DeleteResult(deletedFiles: files, failures: const <DeleteFailure>[]);
}

Future<_StubQuality> _pumpSimilar(
  WidgetTester tester, {
  List<ScannedFile>? files,
  Map<String, PhotoQuality>? qualities,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubQuality quality = _StubQuality(qualities ?? _qualities());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(
          _StubScanner(files ?? _fixture()),
        ),
        perceptualHashRepositoryProvider.overrideWithValue(
          _StubFingerprinter(_fingerprints()),
        ),
        photoQualityRepositoryProvider.overrideWithValue(quality),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
        deleteRepositoryProvider.overrideWithValue(_NoopDelete()),
      ],
      child: const MaterialApp(home: SimilarPhotosScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return quality;
}

BestPhotoRecommendation _rank({
  List<ScannedFile>? files,
  Map<String, PhotoQuality>? qualities,
}) => BestPhotoScorer.rank(files ?? _fixture(), qualities ?? _qualities());

void main() {
  group('PhotoQuality parsing', () {
    test('reads a well-formed platform row', () {
      final PhotoQuality? quality = PhotoQuality.fromPlatformMap(
        <Object?, Object?>{
          'width': 4000,
          'height': 3000,
          'pixels': 12 * _mp,
          'sharpness': 312.5,
        },
      );

      expect(quality, isNotNull);
      expect(quality!.width, 4000);
      expect(quality.longestEdge, 4000);
      expect(quality.megapixels, 12);
      expect(quality.sharpness, 312.5);
      expect(quality.isEmpty, isFalse);
    });

    test('a row without usable dimensions is dropped, never defaulted', () {
      expect(
        PhotoQuality.fromPlatformMap(<Object?, Object?>{'sharpness': 100}),
        isNull,
      );
      expect(
        PhotoQuality.fromPlatformMap(<Object?, Object?>{
          'width': 0,
          'height': 3000,
        }),
        isNull,
      );
    });

    test('a negative sharpness reads as unmeasured, not blurred', () {
      final PhotoQuality? quality = PhotoQuality.fromPlatformMap(
        <Object?, Object?>{'width': 100, 'height': 100, 'sharpness': -5},
      );
      expect(quality?.sharpness, 0);
      // Pixels derived when the platform omits them.
      expect(quality?.pixels, 10000);
    });

    test('the repository drops malformed rows and keeps good ones', () {
      final Map<String, PhotoQuality> parsed =
          PlatformPhotoQualityRepository.parseQualities(<Object?, Object?>{
            _uri('1'): <Object?, Object?>{
              'width': 4000,
              'height': 3000,
              'pixels': 12 * _mp,
              'sharpness': 200.0,
            },
            _uri('2'): <Object?, Object?>{'width': 0, 'height': 0},
            _uri('3'): 'not a map',
            '': <Object?, Object?>{'width': 10, 'height': 10},
          });

      expect(parsed.keys, <String>[_uri('1')]);
    });

    test('a null payload is empty, not an error', () {
      expect(PlatformPhotoQualityRepository.parseQualities(null), isEmpty);
    });
  });

  group('BestPhotoScorer', () {
    test('suggests the sharpest when resolution is equal', () {
      final BestPhotoRecommendation result = _rank();

      expect(result.hasSuggestion, isTrue);
      expect(result.suggested?.name, 'shot_a.jpg');
      expect(result.reason, BestPhotoReason.sharpest);
      // Verified independently: 1.0, 0.8375, 0.5125.
      expect(result.scores.map((PhotoScore s) => s.file.name), <String>[
        'shot_a.jpg',
        'shot_c.jpg',
        'shot_b.jpg',
      ]);
    });

    test('suggests the highest resolution when sharpness is equal', () {
      final BestPhotoRecommendation result = _rank(
        files: <ScannedFile>[
          _file(id: '1', name: 'big.jpg'),
          _file(id: '2', name: 'small.jpg'),
        ],
        qualities: <String, PhotoQuality>{
          _uri('1'): _quality(sharpness: 400),
          _uri('2'): _quality(sharpness: 400, width: 2000, height: 1500),
        },
      );

      expect(result.suggested?.name, 'big.jpg');
      expect(result.reason, BestPhotoReason.highestResolution);
    });

    test('names it best overall when both factors lead', () {
      final BestPhotoRecommendation result = _rank(
        files: <ScannedFile>[
          _file(id: '1', name: 'good.jpg'),
          _file(id: '2', name: 'poor.jpg'),
        ],
        qualities: <String, PhotoQuality>{
          _uri('1'): _quality(sharpness: 400),
          _uri('2'): _quality(sharpness: 200, width: 2000, height: 1500),
        },
      );

      expect(result.suggested?.name, 'good.jpg');
      expect(result.reason, BestPhotoReason.bestOverall);
    });

    test('refuses to pick a winner when the shots are too close', () {
      final BestPhotoRecommendation result = _rank(
        files: <ScannedFile>[
          _file(id: '1', name: 'a.jpg'),
          _file(id: '2', name: 'b.jpg'),
        ],
        qualities: <String, PhotoQuality>{
          _uri('1'): _quality(sharpness: 400),
          _uri('2'): _quality(sharpness: 390),
        },
      );

      // A lead of 0.016 is well under the 0.08 margin.
      expect(result.hasSuggestion, isFalse);
      expect(result.suggested, isNull);
      expect(result.reason, BestPhotoReason.tooClose);
      // The ranking is still available; only the verdict is withheld.
      expect(result.scores, hasLength(2));
    });

    test('blur is judged relative to the group, never absolutely', () {
      final BestPhotoRecommendation result = _rank();

      // 0.25 of the group's best.
      expect(result.scoreFor(_fixture()[1])?.looksBlurred, isTrue);
      // 0.75 of the group's best.
      expect(result.scoreFor(_fixture()[2])?.looksBlurred, isFalse);

      // The same absolute sharpness in a softer group is not blurred.
      final BestPhotoRecommendation softGroup = _rank(
        files: <ScannedFile>[
          _file(id: '1', name: 'a.jpg'),
          _file(id: '2', name: 'b.jpg'),
        ],
        qualities: <String, PhotoQuality>{
          _uri('1'): _quality(sharpness: 110),
          _uri('2'): _quality(sharpness: 100),
        },
      );
      expect(
        softGroup.scoreFor(_file(id: '2', name: 'b.jpg'))?.looksBlurred,
        isFalse,
      );
    });

    test('an unmeasured photo is omitted, not scored as blurred', () {
      final Map<String, PhotoQuality> partial = Map<String, PhotoQuality>.of(
        _qualities(),
      )..remove(_uri('2'));

      final BestPhotoRecommendation result = _rank(qualities: partial);

      expect(result.scores, hasLength(2));
      expect(result.scoreFor(_fixture()[1]), isNull);
      expect(
        result.scores.map((PhotoScore s) => s.file.name),
        isNot(contains('shot_b.jpg')),
      );
    });

    test('no measurements at all yields no opinion', () {
      final BestPhotoRecommendation result = _rank(
        qualities: const <String, PhotoQuality>{},
      );
      expect(result.hasSuggestion, isFalse);
      expect(result.scores, isEmpty);
      expect(result.reason, BestPhotoReason.tooClose);
    });

    test('a single measured photo is not a comparison', () {
      final BestPhotoRecommendation result = _rank(
        qualities: <String, PhotoQuality>{
          _uri('1'): _quality(sharpness: 400),
        },
      );
      expect(result.hasSuggestion, isFalse);
    });

    test('ties are broken stably, so a rebuild cannot change the advice', () {
      final Map<String, PhotoQuality> identical = <String, PhotoQuality>{
        _uri('1'): _quality(sharpness: 400),
        _uri('2'): _quality(sharpness: 400),
        _uri('3'): _quality(sharpness: 400),
      };

      final BestPhotoRecommendation first = _rank(qualities: identical);
      final BestPhotoRecommendation second = _rank(qualities: identical);

      expect(
        first.scores.map((PhotoScore s) => s.file.uri),
        second.scores.map((PhotoScore s) => s.file.uri),
      );
      // Identical shots are, correctly, too close to call.
      expect(first.hasSuggestion, isFalse);
    });

    test('sharpness outweighs resolution, as a person would judge it', () {
      expect(
        BestPhotoScorer.sharpnessWeight,
        greaterThan(BestPhotoScorer.resolutionWeight),
      );
      expect(
        BestPhotoScorer.sharpnessWeight + BestPhotoScorer.resolutionWeight,
        closeTo(1, 0.0001),
      );
    });
  });

  group('Suggested Keep in the UI', () {
    testWidgets('marks one shot and names the reason', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      expect(
        find.byKey(const Key('similar_shot_suggested_1')),
        findsOneWidget,
      );
      // Exactly one per group.
      expect(find.text('Suggested Keep'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(Key('similar_group_reason_${_uri('1')}')))
            .data,
        'Sharpest shot suggested. Nothing is selected for you.',
      );
    });

    testWidgets('the suggestion never selects or deletes anything', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      // No selection bar, so nothing is queued for deletion.
      expect(
        find.byKey(const Key('similar_photos_selection_bar')),
        findsNothing,
      );
      // The suggested shot is not the protected one either: the keeper is
      // still the user's own default, and the badge changes neither.
      expect(find.byKey(const Key('similar_shot_kept_1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a suggested shot can still be selected by the user', (
      WidgetTester tester,
    ) async {
      // Make the middle shot the suggestion so it is not also the keeper.
      await _pumpSimilar(
        tester,
        qualities: <String, PhotoQuality>{
          _uri('1'): _quality(sharpness: 100),
          _uri('2'): _quality(sharpness: 400),
          _uri('3'): _quality(sharpness: 150),
        },
      );

      expect(
        find.byKey(const Key('similar_shot_suggested_2')),
        findsOneWidget,
      );

      // Advice, not a lock: the user overrules it.
      await tester.tap(find.byKey(const Key('similar_shot_2')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('similar_photos_selection_count')),
            )
            .data,
        '1 selected',
      );
    });

    testWidgets('a soft shot is flagged relative to the best', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      expect(find.byKey(const Key('similar_shot_soft_2')), findsOneWidget);
      // The middling shot is not flagged.
      expect(find.byKey(const Key('similar_shot_soft_3')), findsNothing);
    });

    testWidgets('resolution is shown once a shot has been measured', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('similar_shot_detail_1')))
            .data,
        '4000 x 3000',
      );
    });

    testWidgets('too close to call is stated, not papered over', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(
        tester,
        qualities: <String, PhotoQuality>{
          _uri('1'): _quality(sharpness: 400),
          _uri('2'): _quality(sharpness: 398),
          _uri('3'): _quality(sharpness: 396),
        },
      );

      expect(find.text('Suggested Keep'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(Key('similar_group_reason_${_uri('1')}')))
            .data,
        'These shots are too close to call. Your choice.',
      );
    });

    testWidgets('only grouped photos are measured', (
      WidgetTester tester,
    ) async {
      final _StubQuality quality = await _pumpSimilar(tester);

      expect(quality.requests, hasLength(1));
      // The three grouped shots, and nothing else in the library.
      expect(quality.requests.single, hasLength(3));
    });

    testWidgets('an unmeasurable library simply shows no advice', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester, qualities: const <String, PhotoQuality>{});

      expect(find.text('Suggested Keep'), findsNothing);
      expect(
        find.byKey(Key('similar_group_reason_${_uri('1')}')),
        findsNothing,
      );
      // The groups themselves still render and stay reviewable.
      expect(find.byKey(const Key('similar_shot_1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
