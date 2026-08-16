import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_detector.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/duplicates_screen.dart';

const int _mib = 1024 * 1024;

ScannedFile _file({
  required String id,
  required String name,
  required int sizeBytes,
  int daysOld = 10,
  FileCategory category = FileCategory.images,
  String? uri,
}) {
  final DateTime now = DateTime.now();
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/DCIM/$name',
    uri: uri ?? 'content://media/external/images/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: DateTime(now.year, now.month, now.day, 12)
        .subtract(Duration(days: daysOld)),
    mimeType: 'image/jpeg',
  );
}

/// Two real duplicate pairs, one size-collision that is NOT a duplicate,
/// and one unique file.
List<ScannedFile> _fixture() => <ScannedFile>[
  // Trio of identical 5 MB photos; oldest is id 1.
  _file(id: '1', name: 'holiday.jpg', sizeBytes: 5 * _mib, daysOld: 90),
  _file(id: '2', name: 'holiday (1).jpg', sizeBytes: 5 * _mib, daysOld: 60),
  _file(id: '3', name: 'holiday-copy.jpg', sizeBytes: 5 * _mib, daysOld: 30),
  // Same size as each other but different content: must NOT group.
  _file(id: '4', name: 'alpha.jpg', sizeBytes: 3 * _mib),
  _file(id: '5', name: 'beta.jpg', sizeBytes: 3 * _mib),
  // Identical pair, larger.
  _file(id: '6', name: 'clip.mp4', sizeBytes: 20 * _mib, daysOld: 50),
  _file(id: '7', name: 'clip (1).mp4', sizeBytes: 20 * _mib, daysOld: 20),
  // Unique size entirely.
  _file(id: '8', name: 'unique.jpg', sizeBytes: 7 * _mib),
  // Below the floor: never a candidate.
  _file(id: '9', name: 'tiny-a.jpg', sizeBytes: 1024),
  _file(id: '10', name: 'tiny-b.jpg', sizeBytes: 1024),
];

/// Hashes matching the fixture: 1/2/3 identical, 6/7 identical, 4/5 differ.
Map<String, String> _hashes() => <String, String>{
  'content://media/external/images/media/1': 'aaa',
  'content://media/external/images/media/2': 'aaa',
  'content://media/external/images/media/3': 'aaa',
  'content://media/external/images/media/4': 'bbb',
  'content://media/external/images/media/5': 'ccc',
  'content://media/external/images/media/6': 'ddd',
  'content://media/external/images/media/7': 'ddd',
  'content://media/external/images/media/8': 'eee',
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

class _StubHasher implements FileHashRepository {
  _StubHasher(this.hashes);

  final Map<String, String> hashes;
  final List<List<String>> requests = <List<String>>[];

  @override
  Future<Map<String, String>> hashFiles(List<ScannedFile> files) async {
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

Future<_StubHasher> _pumpDuplicates(
  WidgetTester tester, {
  List<ScannedFile>? files,
  Map<String, String>? hashes,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubHasher hasher = _StubHasher(hashes ?? _hashes());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(
          _StubScanner(files ?? _fixture()),
        ),
        fileHashRepositoryProvider.overrideWithValue(hasher),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
        deleteRepositoryProvider.overrideWithValue(_NoopDelete()),
      ],
      child: const MaterialApp(home: DuplicatesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return hasher;
}

void main() {
  group('Stage 1: candidate grouping by size', () {
    test('only sizes shared by two or more files become candidates', () {
      final List<List<ScannedFile>> groups = DuplicateDetector.candidateGroups(
        _fixture(),
      );

      // 5 MB trio, 3 MB pair, 20 MB pair. Not the unique 7 MB file.
      expect(groups, hasLength(3));
      final Set<int> sizes = groups
          .map((List<ScannedFile> g) => g.first.sizeBytes)
          .toSet();
      expect(sizes, <int>{5 * _mib, 3 * _mib, 20 * _mib});
    });

    test('files below the floor are never candidates', () {
      final List<ScannedFile> candidates = DuplicateDetector.candidates(
        _fixture(),
      );
      expect(
        candidates.map((ScannedFile f) => f.name),
        isNot(contains('tiny-a.jpg')),
      );
      // 3 + 2 + 2 = 7 files worth hashing.
      expect(candidates, hasLength(7));
    });

    test('a unique size is never hashed', () {
      final List<ScannedFile> candidates = DuplicateDetector.candidates(
        _fixture(),
      );
      expect(
        candidates.map((ScannedFile f) => f.name),
        isNot(contains('unique.jpg')),
      );
    });

    test('a file reported twice is not its own duplicate', () {
      // The same physical file surfaced by two categories.
      const String shared = 'content://media/external/file/media/77';
      final List<ScannedFile> files = <ScannedFile>[
        _file(id: '77', name: 'a.jpg', sizeBytes: 5 * _mib, uri: shared),
        _file(
          id: '77',
          name: 'a.jpg',
          sizeBytes: 5 * _mib,
          category: FileCategory.downloads,
          uri: shared,
        ),
      ];
      expect(DuplicateDetector.candidateGroups(files), isEmpty);
    });
  });

  group('Stage 2: hash confirms exact duplicates', () {
    test('same size but different content does not group', () {
      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        _hashes(),
      );
      final List<String> names = <String>[
        for (final DuplicateGroup g in result.groups)
          for (final ScannedFile f in g.files) f.name,
      ];
      // alpha and beta share a size but hash differently.
      expect(names, isNot(contains('alpha.jpg')));
      expect(names, isNot(contains('beta.jpg')));
    });

    test('identical content groups together', () {
      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        _hashes(),
      );
      expect(result.groupCount, 2);
      // Two extra copies of the trio, one of the pair.
      expect(result.duplicateCount, 3);
    });

    test('reclaimable space keeps one copy of each set', () {
      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        _hashes(),
      );
      // 5 MB x 2 spare + 20 MB x 1 spare
      expect(result.reclaimableBytes, (5 * 2 + 20) * _mib);
    });

    test('groups are ordered by biggest saving', () {
      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        _hashes(),
      );
      // 20 MB single spare beats 10 MB across two spares.
      expect(result.groups.first.fileBytes, 20 * _mib);
    });

    test('an unhashable file is dropped, never assumed identical', () {
      final Map<String, String> partial = Map<String, String>.of(_hashes())
        ..remove('content://media/external/images/media/3');

      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        partial,
      );
      final DuplicateGroup trio = result.groups.firstWhere(
        (DuplicateGroup g) => g.fileBytes == 5 * _mib,
      );
      expect(trio.copyCount, 2);
    });

    test('no hashes at all yields no duplicates', () {
      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        const <String, String>{},
      );
      expect(result.isEmpty, isTrue);
      expect(result.reclaimableBytes, 0);
    });

    test('reports how much work was done', () {
      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        _hashes(),
      );
      expect(result.candidatesConsidered, 7);
      expect(result.filesHashed, 7);
    });
  });

  group('DuplicateGroup safety', () {
    test('the oldest copy is kept and never listed as removable', () {
      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        _hashes(),
      );
      final DuplicateGroup trio = result.groups.firstWhere(
        (DuplicateGroup g) => g.copyCount == 3,
      );

      expect(trio.original?.name, 'holiday.jpg');
      expect(trio.duplicates, hasLength(2));
      expect(
        trio.duplicates.map((ScannedFile f) => f.name),
        isNot(contains('holiday.jpg')),
      );
    });

    test('one copy is always excluded from the removable set', () {
      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        _hashes(),
      );
      for (final DuplicateGroup group in result.groups) {
        expect(group.duplicates.length, group.copyCount - 1);
      }
      // Across the whole result, never every copy.
      expect(result.allDuplicates.length, lessThan(5));
    });

    test('totals distinguish occupied from reclaimable space', () {
      final DuplicateScanResult result = DuplicateDetector.group(
        _fixture(),
        _hashes(),
      );
      final DuplicateGroup trio = result.groups.firstWhere(
        (DuplicateGroup g) => g.copyCount == 3,
      );
      expect(trio.totalBytes, 15 * _mib);
      expect(trio.reclaimableBytes, 10 * _mib);
    });
  });

  group('Duplicates screen', () {
    testWidgets('hashes only the size-matched candidates', (
      WidgetTester tester,
    ) async {
      final _StubHasher hasher = await _pumpDuplicates(tester);

      expect(hasher.requests, hasLength(1));
      // 7 candidates, not the whole library.
      expect(hasher.requests.single, hasLength(7));
    });

    testWidgets('shows the recoverable total and counts', (
      WidgetTester tester,
    ) async {
      await _pumpDuplicates(tester);

      expect(find.byKey(const Key('duplicates_total_card')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('duplicates_total_bytes')))
            .data,
        '30.0 MB',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('duplicates_count'))).data,
        '3 extra copies across 2 sets',
      );
    });

    testWidgets('the kept copy is shown and cannot be selected', (
      WidgetTester tester,
    ) async {
      await _pumpDuplicates(tester);

      // The oldest of the trio is marked kept.
      expect(find.byKey(const Key('duplicate_kept_1')), findsOneWidget);
      // And has no checkbox.
      expect(find.byKey(const Key('file_checkbox_1')), findsNothing);
      // Its copies do.
      expect(find.byKey(const Key('file_checkbox_2')), findsOneWidget);
      expect(find.byKey(const Key('file_checkbox_3')), findsOneWidget);
    });

    testWidgets('select copies never selects the kept file', (
      WidgetTester tester,
    ) async {
      await _pumpDuplicates(tester);

      await tester.tap(find.byKey(const Key('duplicates_select_all')));
      await tester.pumpAndSettle();

      // 3 removable copies, never 5.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('duplicates_selection_count')))
            .data,
        '3 selected',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('duplicates_selection_bytes')))
            .data,
        '30.0 MB',
      );
    });

    testWidgets('selecting a copy reveals the action bar', (
      WidgetTester tester,
    ) async {
      await _pumpDuplicates(tester);
      expect(find.byKey(const Key('duplicates_selection_bar')), findsNothing);

      await tester.tap(find.byKey(const Key('file_checkbox_2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('duplicates_selection_bar')), findsOneWidget);
      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(const Key('duplicates_selection_delete')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows an empty state when nothing matches', (
      WidgetTester tester,
    ) async {
      await _pumpDuplicates(
        tester,
        files: <ScannedFile>[
          _file(id: '1', name: 'only.jpg', sizeBytes: 5 * _mib),
        ],
      );

      expect(find.byKey(const Key('duplicates_empty')), findsOneWidget);
      expect(find.text('No duplicates found'), findsOneWidget);
    });

    testWidgets('same size but different content shows no duplicates', (
      WidgetTester tester,
    ) async {
      await _pumpDuplicates(
        tester,
        files: <ScannedFile>[
          _file(id: '4', name: 'alpha.jpg', sizeBytes: 3 * _mib),
          _file(id: '5', name: 'beta.jpg', sizeBytes: 3 * _mib),
        ],
      );

      // Both were hashed, neither matched.
      expect(find.byKey(const Key('duplicates_empty')), findsOneWidget);
    });
  });

  group('PlatformFileHashRepository.parseHashes', () {
    test('keeps well-formed entries', () {
      final Map<String, String> parsed =
          PlatformFileHashRepository.parseHashes(<Object?, Object?>{
            'content://a': 'abc123',
            'content://b': 'def456',
          });
      expect(parsed, hasLength(2));
      expect(parsed['content://a'], 'abc123');
    });

    test('drops malformed rows and a null payload', () {
      expect(PlatformFileHashRepository.parseHashes(null), isEmpty);
      final Map<String, String> parsed =
          PlatformFileHashRepository.parseHashes(<Object?, Object?>{
            'content://a': '',
            '': 'abc',
            42: 'abc',
            'content://b': 99,
            'content://c': 'ok',
          });
      expect(parsed, hasLength(1));
      expect(parsed['content://c'], 'ok');
    });
  });
}
