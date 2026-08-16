import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/perceptual_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_keep_selection.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/perceptual_hash.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/similar_photo_detector.dart';
import 'package:mobile_cleaner/features/files/domain/similar_photo_group.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/similar_photos_screen.dart';

const int _mib = 1024 * 1024;

/// Gradient hashes at known Hamming distances from [_dA].
///
/// Distances verified independently: A-B 4, A-C 8, B-C 4, A-CHAIN 16,
/// C-CHAIN 8, A-FLAT 2, A-FAR 40.
const String _dA = '0000000000000000';
const String _dB = '000000000000000f';
const String _dC = '00000000000000ff';
const String _dChain = '000000000000ffff';
const String _dFlat = '0000000000000003';
const String _dFar = '000000ffffffffff';

/// Average hashes. `_aVeto` is 20 bits away, past every strength's bound.
const String _aBase = '0000000000000000';
const String _aClose = '0000000000000003';
const String _aVeto = '00000000000fffff';

String _fingerprint(String difference, [String average = _aBase]) =>
    '$difference$average';

ScannedFile _file({
  required String id,
  required String name,
  required int sizeBytes,
  int minutesOld = 0,
  FileCategory category = FileCategory.images,
  String mimeType = 'image/jpeg',
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/DCIM/Camera/$name',
    uri: 'content://media/external/images/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: DateTime(
      2026,
      3,
      1,
      12,
    ).subtract(Duration(minutes: minutesOld)),
    mimeType: mimeType,
    relativePath: 'DCIM/Camera/',
  );
}

String _uri(String id) => 'content://media/external/images/media/$id';

/// A burst of three, a lone unrelated photo, a flat image the average hash
/// must veto, and a video that must never be considered.
List<ScannedFile> _fixture() => <ScannedFile>[
  // Burst: oldest is id 1, so it leads.
  _file(id: '1', name: 'burst_a.jpg', sizeBytes: 4 * _mib, minutesOld: 30),
  _file(id: '2', name: 'burst_b.jpg', sizeBytes: 5 * _mib, minutesOld: 29),
  _file(id: '3', name: 'burst_c.jpg', sizeBytes: 3 * _mib, minutesOld: 28),
  // Entirely different scene.
  _file(id: '4', name: 'sunset.jpg', sizeBytes: 6 * _mib, minutesOld: 500),
  // Close gradient to the burst, but a wildly different average: not similar.
  _file(id: '5', name: 'wall.jpg', sizeBytes: 2 * _mib, minutesOld: 400),
  // Video: never analysed, even if its fingerprint were supplied.
  _file(
    id: '6',
    name: 'clip.mp4',
    sizeBytes: 9 * _mib,
    minutesOld: 20,
    category: FileCategory.videos,
    mimeType: 'video/mp4',
  ),
  // Below the floor: too small to be worth comparing.
  _file(id: '7', name: 'icon.png', sizeBytes: 8 * 1024, minutesOld: 10),
];

Map<String, String> _fingerprints() => <String, String>{
  _uri('1'): _fingerprint(_dA),
  _uri('2'): _fingerprint(_dB),
  _uri('3'): _fingerprint(_dC),
  _uri('4'): _fingerprint(_dFar),
  // Gradient is 2 bits away, but the average hash vetoes it.
  _uri('5'): _fingerprint(_dFlat, _aVeto),
  _uri('6'): _fingerprint(_dA),
  _uri('7'): _fingerprint(_dA),
};

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);

  final List<ScannedFile> files;
  FileScanRequest? lastRequest;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    lastRequest = request;
    return FileScanResult.fromFiles(
      files
          .where((ScannedFile f) => f.sizeBytes >= request.minSizeBytes)
          .toList(),
      categories: request.categories,
    );
  }
}

class _StubFingerprinter implements PerceptualHashRepository {
  _StubFingerprinter(this.hashes);

  final Map<String, String> hashes;
  final List<List<String>> requests = <List<String>>[];

  @override
  Future<Map<String, String>> hashImages(List<ScannedFile> files) async {
    requests.add(files.map((ScannedFile f) => f.uri).toList());
    return <String, String>{
      for (final ScannedFile f in files)
        if (hashes.containsKey(f.uri)) f.uri: hashes[f.uri]!,
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

Future<_StubFingerprinter> _pumpSimilar(
  WidgetTester tester, {
  List<ScannedFile>? files,
  Map<String, String>? hashes,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubFingerprinter hasher = _StubFingerprinter(
    hashes ?? _fingerprints(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(
          _StubScanner(files ?? _fixture()),
        ),
        perceptualHashRepositoryProvider.overrideWithValue(hasher),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
        deleteRepositoryProvider.overrideWithValue(_NoopDelete()),
      ],
      child: const MaterialApp(home: SimilarPhotosScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return hasher;
}

SimilarPhotoScanResult _group({
  SimilarityStrength strength = SimilarityStrength.balanced,
  List<ScannedFile>? files,
  Map<String, String>? hashes,
}) => SimilarPhotoDetector.group(
  files ?? _fixture(),
  hashes ?? _fingerprints(),
  strength: strength,
);

void main() {
  group('PerceptualHash', () {
    test('parses 32 hex characters into two 64-bit halves', () {
      final PerceptualHash? hash = PerceptualHash.tryParse(
        _fingerprint(_dB, _aClose),
      );
      expect(hash, isNotNull);
      expect(hash!.difference, 0xf);
      expect(hash.average, 0x3);
    });

    test('a hash with the top bit set survives parsing', () {
      final PerceptualHash? hash = PerceptualHash.tryParse(
        'ffffffffffffffff${'0' * 16}',
      );
      expect(hash, isNotNull);
      // 64 differing bits from zero, so all bits round-tripped.
      expect(
        PerceptualHash.hammingDistance(hash!.difference, 0),
        PerceptualHash.bitCount,
      );
    });

    test('malformed input is rejected, never guessed at', () {
      expect(PerceptualHash.tryParse(null), isNull);
      expect(PerceptualHash.tryParse(''), isNull);
      // Too short.
      expect(PerceptualHash.tryParse(_dA), isNull);
      // Not hex.
      expect(PerceptualHash.tryParse('z' * 32), isNull);
    });

    test('Hamming distance counts differing bits', () {
      expect(PerceptualHash.hammingDistance(0, 0), 0);
      expect(PerceptualHash.hammingDistance(0, 0xf), 4);
      final PerceptualHash a = PerceptualHash.tryParse(_fingerprint(_dA))!;
      final PerceptualHash c = PerceptualHash.tryParse(_fingerprint(_dC))!;
      expect(a.differenceDistance(c), 8);
      expect(a.averageDistance(c), 0);
    });
  });

  group('SimilarityStrength', () {
    test('both hashes must agree before photos are called similar', () {
      final PerceptualHash burst = PerceptualHash.tryParse(
        _fingerprint(_dA),
      )!;
      final PerceptualHash flatWall = PerceptualHash.tryParse(
        _fingerprint(_dFlat, _aVeto),
      )!;

      // The gradient hash alone would group them.
      expect(burst.differenceDistance(flatWall), lessThanOrEqualTo(4));
      // The average hash vetoes it.
      expect(burst.averageDistance(flatWall), 20);
      expect(SimilarityStrength.balanced.matches(burst, flatWall), isFalse);
      expect(SimilarityStrength.relaxed.matches(burst, flatWall), isFalse);
    });

    test('strengths widen in order', () {
      expect(
        SimilarityStrength.strict.maxDifferenceDistance,
        lessThan(SimilarityStrength.balanced.maxDifferenceDistance),
      );
      expect(
        SimilarityStrength.balanced.maxDifferenceDistance,
        lessThan(SimilarityStrength.relaxed.maxDifferenceDistance),
      );
      expect(
        SimilarityStrength.defaultStrength,
        SimilarityStrength.balanced,
      );
    });
  });

  group('SimilarPhotoDetector candidates', () {
    test('only photos above the floor are analysed', () {
      final List<ScannedFile> candidates = SimilarPhotoDetector.candidates(
        _fixture(),
      );
      final Iterable<String> names = candidates.map((ScannedFile f) => f.name);

      expect(names, isNot(contains('clip.mp4')));
      expect(names, isNot(contains('icon.png')));
      // The three burst shots, the sunset, and the flat wall.
      expect(candidates, hasLength(5));
    });

    test('a photo reported twice is not its own twin', () {
      final ScannedFile photo = _file(
        id: '1',
        name: 'a.jpg',
        sizeBytes: 4 * _mib,
      );
      expect(
        SimilarPhotoDetector.candidates(<ScannedFile>[photo, photo]),
        hasLength(1),
      );
    });
  });

  group('SimilarPhotoDetector grouping', () {
    test('a burst is grouped, unrelated photos are not', () {
      final SimilarPhotoScanResult result = _group();

      expect(result.groupCount, 1);
      expect(
        result.groups.single.files.map((ScannedFile f) => f.name),
        <String>['burst_a.jpg', 'burst_b.jpg', 'burst_c.jpg'],
      );
      // The distinct scene and the vetoed flat image stay out.
      expect(result.extraPhotoCount, 2);
    });

    test('the group never chains beyond its leader', () {
      // A-C is 8 bits, C-CHAIN is 8 bits, but A-CHAIN is 16. Transitive
      // grouping would put A and CHAIN in one set despite them looking
      // nothing alike.
      final List<ScannedFile> files = <ScannedFile>[
        _file(id: '1', name: 'a.jpg', sizeBytes: 4 * _mib, minutesOld: 30),
        _file(id: '2', name: 'c.jpg', sizeBytes: 4 * _mib, minutesOld: 29),
        _file(id: '3', name: 'chain.jpg', sizeBytes: 4 * _mib, minutesOld: 28),
      ];
      final SimilarPhotoScanResult result = _group(
        files: files,
        hashes: <String, String>{
          _uri('1'): _fingerprint(_dA),
          _uri('2'): _fingerprint(_dC),
          _uri('3'): _fingerprint(_dChain),
        },
      );

      expect(result.groupCount, 1);
      expect(
        result.groups.single.files.map((ScannedFile f) => f.name),
        <String>['a.jpg', 'c.jpg'],
      );
    });

    test('strength changes how much is grouped', () {
      // Strict keeps only the 4-bit pair; C is 8 bits from the leader.
      final SimilarPhotoScanResult strict = _group(
        strength: SimilarityStrength.strict,
      );
      expect(strict.groups.single.photoCount, 2);

      final SimilarPhotoScanResult relaxed = _group(
        strength: SimilarityStrength.relaxed,
      );
      expect(relaxed.groups.single.photoCount, 3);
    });

    test('an unreadable photo is dropped, never grouped on a guess', () {
      final Map<String, String> partial = Map<String, String>.of(
        _fingerprints(),
      )..remove(_uri('3'));

      final SimilarPhotoScanResult result = _group(hashes: partial);
      expect(result.groups.single.photoCount, 2);
      expect(result.photosHashed, 4);
      expect(result.photosAnalyzed, 5);
    });

    test('no fingerprints at all yields no groups', () {
      expect(_group(hashes: const <String, String>{}).isEmpty, isTrue);
    });

    test('a lone photo is never a group of one', () {
      final SimilarPhotoScanResult result = _group(
        files: <ScannedFile>[
          _file(id: '1', name: 'only.jpg', sizeBytes: 4 * _mib),
        ],
      );
      expect(result.isEmpty, isTrue);
      expect(result.reclaimableBytes, 0);
    });
  });

  group('SimilarPhotoGroup', () {
    test('reclaimable space assumes the largest shot is kept', () {
      final SimilarPhotoGroup group = _group().groups.single;

      // 4 + 5 + 3 MB present; keeping the 5 MB shot frees 7 MB.
      expect(group.totalBytes, 12 * _mib);
      expect(group.reclaimableBytes, 7 * _mib);
    });

    test('members are chronological and the first shot leads', () {
      final SimilarPhotoGroup group = _group().groups.single;
      expect(group.original?.name, 'burst_a.jpg');
      expect(group.groupKey, group.key);
    });

    test('a burst is recognised by its timespan', () {
      final SimilarPhotoGroup group = _group().groups.single;
      // Two minutes apart: not inside the one-minute burst window.
      expect(group.timeSpan, const Duration(minutes: 2));
      expect(group.isBurst, isFalse);

      final SimilarPhotoScanResult tight = _group(
        files: <ScannedFile>[
          _file(id: '1', name: 'a.jpg', sizeBytes: 4 * _mib, minutesOld: 10),
          _file(id: '2', name: 'b.jpg', sizeBytes: 4 * _mib, minutesOld: 10),
        ],
        hashes: <String, String>{
          _uri('1'): _fingerprint(_dA),
          _uri('2'): _fingerprint(_dB),
        },
      );
      expect(tight.groups.single.isBurst, isTrue);
    });
  });

  group('Keep selection is shared with exact duplicates', () {
    test('one shot is always retained whatever the user picks', () {
      final SimilarPhotoGroup group = _group().groups.single;
      DuplicateKeepSelection keep = const DuplicateKeepSelection.empty();

      expect(keep.kept(group)?.name, 'burst_a.jpg');
      for (final ScannedFile file in group.files) {
        keep = keep.keep(group, file);
        expect(keep.kept(group), file);
        expect(keep.removable(group).length, group.photoCount - 1);
        expect(keep.removable(group), isNot(contains(file)));
      }
    });

    test('reclaimable bytes follow the chosen keeper', () {
      final SimilarPhotoGroup group = _group().groups.single;
      final List<SimilarPhotoGroup> groups = <SimilarPhotoGroup>[group];

      // Default keeper is the 4 MB first shot: 5 + 3 = 8 MB removable.
      const DuplicateKeepSelection base = DuplicateKeepSelection.empty();
      expect(base.reclaimableBytes(groups), 8 * _mib);

      // Keeping the 5 MB shot instead: 4 + 3 = 7 MB.
      final DuplicateKeepSelection best = base.keep(group, group.files[1]);
      expect(best.reclaimableBytes(groups), 7 * _mib);
    });
  });

  group('Similar Photos screen', () {
    testWidgets('analyses only the eligible photos', (
      WidgetTester tester,
    ) async {
      final _StubFingerprinter hasher = await _pumpSimilar(tester);

      expect(hasher.requests, hasLength(1));
      expect(hasher.requests.single, hasLength(5));
      expect(hasher.requests.single, isNot(contains(_uri('6'))));
      expect(hasher.requests.single, isNot(contains(_uri('7'))));
    });

    testWidgets('shows the total as an upper bound, not a promise', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('similar_photos_total_bytes')))
            .data,
        'up to 7.0 MB',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('similar_photos_count')))
            .data,
        '2 extra shots across 1 set',
      );
      expect(
        find.byKey(const Key('similar_photos_caution')),
        findsOneWidget,
      );
    });

    testWidgets('groups shots visually and leaves nothing pre-selected', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      expect(find.byKey(Key('similar_group_${_uri('1')}')), findsOneWidget);
      expect(find.byKey(const Key('similar_shot_1')), findsOneWidget);
      expect(find.byKey(const Key('similar_shot_2')), findsOneWidget);
      expect(find.byKey(const Key('similar_shot_3')), findsOneWidget);
      // Nothing selected on arrival: similar shots are not interchangeable.
      expect(
        find.byKey(const Key('similar_photos_selection_bar')),
        findsNothing,
      );
      // The first shot is kept by default and cannot be selected.
      expect(find.byKey(const Key('similar_shot_kept_1')), findsOneWidget);
      expect(find.byKey(const Key('similar_shot_keep_1')), findsNothing);
    });

    testWidgets('sizes are shown, because similar shots differ in size', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('similar_shot_size_2')))
            .data,
        '5.0 MB',
      );
    });

    testWidgets('the user can change which shot is kept', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      await tester.tap(find.byKey(const Key('similar_shot_keep_2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('similar_shot_kept_2')), findsOneWidget);
      expect(find.byKey(const Key('similar_shot_kept_1')), findsNothing);
      expect(find.byKey(const Key('similar_shot_keep_1')), findsOneWidget);
    });

    testWidgets('tapping the kept shot does nothing', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      await tester.tap(find.byKey(const Key('similar_shot_1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('similar_photos_selection_bar')),
        findsNothing,
      );
    });

    testWidgets('a set can be selected, never the whole library', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester);

      // There is deliberately no global select-all on this screen.
      expect(find.byKey(const Key('similar_photos_select_all')), findsNothing);

      await tester.tap(
        find.byKey(Key('similar_group_select_${_uri('1')}')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('similar_photos_selection_count')),
            )
            .data,
        '2 selected',
      );
      final FilledButton delete = tester.widget<FilledButton>(
        find.byKey(const Key('similar_photos_selection_delete')),
      );
      expect(delete.onPressed, isNotNull);
    });

    testWidgets('changing strength regroups without re-analysing', (
      WidgetTester tester,
    ) async {
      final _StubFingerprinter hasher = await _pumpSimilar(tester);
      expect(hasher.requests, hasLength(1));

      await tester.tap(find.byKey(const Key('similarity_strict')));
      await tester.pumpAndSettle();

      // Strict drops the 8-bit shot from the set.
      expect(find.byKey(const Key('similar_shot_3')), findsNothing);
      // Decoding is expensive, so it must not have run again.
      expect(hasher.requests, hasLength(1));
    });

    testWidgets('an empty result explains the strength setting', (
      WidgetTester tester,
    ) async {
      await _pumpSimilar(tester, hashes: const <String, String>{});

      expect(find.byKey(const Key('similar_photos_empty')), findsOneWidget);
      expect(
        find.byKey(const Key('similar_photos_selection_bar')),
        findsNothing,
      );
    });
  });
}
