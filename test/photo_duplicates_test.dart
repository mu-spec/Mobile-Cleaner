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
import 'package:mobile_cleaner/features/files/domain/duplicate_keep_selection.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/photo_duplicates.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/photo_duplicates_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/photo_duplicates_screen.dart';

const int _mib = 1024 * 1024;

ScannedFile _file({
  required String id,
  required String name,
  required int sizeBytes,
  int daysOld = 10,
  FileCategory category = FileCategory.images,
  String mimeType = 'image/jpeg',
}) {
  final DateTime now = DateTime.now();
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/DCIM/$name',
    uri: 'content://media/external/images/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: DateTime(
      now.year,
      now.month,
      now.day,
      12,
    ).subtract(Duration(days: daysOld)),
    mimeType: mimeType,
    relativePath: 'DCIM/Camera/',
  );
}

/// Photo trio, a photo pair across categories, a same-size non-match, a
/// duplicated video pair that must be ignored, and a unique photo.
List<ScannedFile> _fixture() => <ScannedFile>[
  _file(id: '1', name: 'beach.jpg', sizeBytes: 5 * _mib, daysOld: 90),
  _file(id: '2', name: 'beach (1).jpg', sizeBytes: 5 * _mib, daysOld: 60),
  _file(id: '3', name: 'beach-copy.jpg', sizeBytes: 5 * _mib, daysOld: 30),
  // Same size, different content: never a duplicate.
  _file(id: '4', name: 'alpha.jpg', sizeBytes: 3 * _mib),
  _file(id: '5', name: 'beta.jpg', sizeBytes: 3 * _mib),
  // Identical video pair: the photo tool must not show it.
  _file(
    id: '6',
    name: 'clip.mp4',
    sizeBytes: 20 * _mib,
    category: FileCategory.videos,
    mimeType: 'video/mp4',
  ),
  _file(
    id: '7',
    name: 'clip (1).mp4',
    sizeBytes: 20 * _mib,
    category: FileCategory.videos,
    mimeType: 'video/mp4',
  ),
  // Same picture saved twice: once in the gallery, once in Downloads.
  _file(id: '8', name: 'receipt.jpg', sizeBytes: 8 * _mib, daysOld: 40),
  _file(
    id: '9',
    name: 'receipt (1).jpg',
    sizeBytes: 8 * _mib,
    daysOld: 5,
    category: FileCategory.downloads,
  ),
  _file(id: '10', name: 'unique.jpg', sizeBytes: 7 * _mib),
];

String _uri(String id) => 'content://media/external/images/media/$id';

Map<String, String> _hashes() => <String, String>{
  _uri('1'): 'aaa',
  _uri('2'): 'aaa',
  _uri('3'): 'aaa',
  _uri('4'): 'bbb',
  _uri('5'): 'ccc',
  _uri('6'): 'ddd',
  _uri('7'): 'ddd',
  _uri('8'): 'fff',
  _uri('9'): 'fff',
  _uri('10'): 'eee',
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

Future<_StubHasher> _pumpPhotoDuplicates(
  WidgetTester tester, {
  List<ScannedFile>? files,
}) async {
  // Wide enough that a three-copy strip is fully on screen.
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubHasher hasher = _StubHasher(_hashes());
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
      child: const MaterialApp(home: PhotoDuplicatesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return hasher;
}

DuplicateScanResult _photoResult() => DuplicateDetector.group(
  PhotoDuplicates.only(_fixture()),
  _hashes(),
);

void main() {
  group('PhotoDuplicates filter', () {
    test('keeps images and image MIME types only', () {
      final List<ScannedFile> photos = PhotoDuplicates.only(_fixture());
      expect(
        photos.map((ScannedFile f) => f.name),
        isNot(contains('clip.mp4')),
      );
      // A picture saved into Downloads is still a photo.
      expect(
        photos.map((ScannedFile f) => f.name),
        contains('receipt (1).jpg'),
      );
      expect(photos, hasLength(8));
    });

    test('the duplicate engine is reused unchanged, images only', () {
      final DuplicateScanResult result = _photoResult();

      // The 5 MB trio and the 8 MB cross-category pair. Not the video pair.
      expect(result.groupCount, 2);
      expect(
        <String>[
          for (final DuplicateGroup g in result.groups)
            for (final ScannedFile f in g.files) f.name,
        ],
        isNot(contains('clip.mp4')),
      );
    });

    test('only size-matched photos are hashed', () {
      final List<ScannedFile> candidates = DuplicateDetector.candidates(
        PhotoDuplicates.only(_fixture()),
      );
      // trio 3 + 3 MB pair 2 + 8 MB pair 2. Never the unique photo.
      expect(candidates, hasLength(7));
      expect(
        candidates.map((ScannedFile f) => f.name),
        isNot(contains('unique.jpg')),
      );
    });

    test('reclaimable space keeps one photo per set', () {
      // 5 MB x 2 spare + 8 MB x 1 spare.
      expect(_photoResult().reclaimableBytes, 18 * _mib);
    });
  });

  group('DuplicateKeepSelection', () {
    test('defaults to the oldest copy', () {
      final DuplicateGroup trio = _photoResult().groups.firstWhere(
        (DuplicateGroup g) => g.copyCount == 3,
      );
      const DuplicateKeepSelection keep = DuplicateKeepSelection.empty();

      expect(keep.kept(trio)?.name, 'beach.jpg');
      expect(keep.removable(trio), hasLength(2));
    });

    test('the user can keep a different copy', () {
      final DuplicateGroup trio = _photoResult().groups.firstWhere(
        (DuplicateGroup g) => g.copyCount == 3,
      );
      final DuplicateKeepSelection keep = const DuplicateKeepSelection.empty()
          .keep(trio, trio.files.last);

      expect(keep.kept(trio)?.name, 'beach-copy.jpg');
      expect(
        keep.removable(trio).map((ScannedFile f) => f.name),
        isNot(contains('beach-copy.jpg')),
      );
      expect(keep.removable(trio), hasLength(2));
    });

    test('one copy is always retained whatever the choice', () {
      final DuplicateScanResult result = _photoResult();
      DuplicateKeepSelection keep = const DuplicateKeepSelection.empty();
      for (final DuplicateGroup group in result.groups) {
        for (final ScannedFile file in group.files) {
          keep = keep.keep(group, file);
          expect(keep.removable(group).length, group.copyCount - 1);
          expect(keep.removable(group), isNot(contains(keep.kept(group))));
        }
      }
      expect(keep.removableAcross(result.groups), hasLength(3));
    });

    test('a file from another group is never recorded', () {
      final DuplicateScanResult result = _photoResult();
      final DuplicateGroup first = result.groups.first;
      final DuplicateGroup second = result.groups.last;

      final DuplicateKeepSelection keep = const DuplicateKeepSelection.empty()
          .keep(first, second.files.first);

      expect(keep.overrideCount, 0);
      expect(keep.kept(first), first.original);
    });

    test('reclaimable bytes are unaffected by which copy is kept', () {
      final DuplicateScanResult result = _photoResult();
      final DuplicateGroup trio = result.groups.firstWhere(
        (DuplicateGroup g) => g.copyCount == 3,
      );
      final DuplicateKeepSelection keep = const DuplicateKeepSelection.empty()
          .keep(trio, trio.files.last);

      expect(keep.reclaimableBytes(result.groups), 18 * _mib);
    });

    test('choices for vanished groups are pruned', () {
      final DuplicateScanResult result = _photoResult();
      final DuplicateGroup trio = result.groups.firstWhere(
        (DuplicateGroup g) => g.copyCount == 3,
      );
      final DuplicateKeepSelection keep = const DuplicateKeepSelection.empty()
          .keep(trio, trio.files.last);

      expect(keep.prune(<DuplicateGroup>[]).overrideCount, 0);
      expect(keep.prune(result.groups).overrideCount, 1);
    });
  });

  group('Photo duplicate providers', () {
    test('scans images and downloads with the hashing floor applied', () async {
      final _StubScanner scanner = _StubScanner(_fixture());
      final ProviderContainer container = ProviderContainer(
        overrides: [
          fileScannerRepositoryProvider.overrideWithValue(scanner),
          fileHashRepositoryProvider.overrideWithValue(_StubHasher(_hashes())),
        ],
      );
      addTearDown(container.dispose);

      final DuplicateScanResult result = await container.read(
        photoDuplicatesProvider.future,
      );

      expect(scanner.lastRequest?.categories, <FileCategory>[
        FileCategory.images,
        FileCategory.downloads,
      ]);
      expect(
        scanner.lastRequest?.minSizeBytes,
        DuplicateDetector.minimumFileBytes,
      );
      expect(result.groupCount, 2);
      expect(result.reclaimableBytes, 18 * _mib);
    });
  });

  group('Duplicate Photos screen', () {
    testWidgets('hashes only size-matched photos', (WidgetTester tester) async {
      final _StubHasher hasher = await _pumpPhotoDuplicates(tester);

      expect(hasher.requests, hasLength(1));
      expect(hasher.requests.single, hasLength(7));
      // The video pair is never read.
      expect(hasher.requests.single, isNot(contains(_uri('6'))));
    });

    testWidgets('shows the recoverable total for photos only', (
      WidgetTester tester,
    ) async {
      await _pumpPhotoDuplicates(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('photo_duplicates_total_bytes')),
            )
            .data,
        '18.0 MB',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('photo_duplicates_count')))
            .data,
        '3 extra photos across 2 sets',
      );
    });

    testWidgets('groups copies visually and hides non-photo duplicates', (
      WidgetTester tester,
    ) async {
      await _pumpPhotoDuplicates(tester);

      expect(find.byKey(const Key('photo_group_aaa')), findsOneWidget);
      expect(find.byKey(const Key('photo_group_fff')), findsOneWidget);
      // The identical video pair belongs to the general Duplicates tool.
      expect(find.byKey(const Key('photo_group_ddd')), findsNothing);
      // Every copy of the trio is rendered as its own picture cell.
      expect(find.byKey(const Key('photo_copy_1')), findsOneWidget);
      expect(find.byKey(const Key('photo_copy_2')), findsOneWidget);
      expect(find.byKey(const Key('photo_copy_3')), findsOneWidget);
    });

    testWidgets('the oldest copy is kept by default and cannot be tapped', (
      WidgetTester tester,
    ) async {
      await _pumpPhotoDuplicates(tester);

      expect(find.byKey(const Key('photo_copy_kept_1')), findsOneWidget);
      expect(find.byKey(const Key('photo_copy_keep_1')), findsNothing);
      expect(find.byKey(const Key('photo_copy_keep_2')), findsOneWidget);

      // Tapping the kept photo does nothing: no selection bar appears.
      await tester.tap(find.byKey(const Key('photo_copy_1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('photo_duplicates_selection_bar')),
        findsNothing,
      );
    });

    testWidgets('the user can choose which copy to keep', (
      WidgetTester tester,
    ) async {
      await _pumpPhotoDuplicates(tester);

      await tester.tap(find.byKey(const Key('photo_copy_keep_3')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('photo_copy_kept_3')), findsOneWidget);
      // The previous keeper becomes an ordinary, removable copy.
      expect(find.byKey(const Key('photo_copy_kept_1')), findsNothing);
      expect(find.byKey(const Key('photo_copy_keep_1')), findsOneWidget);
    });

    testWidgets('keeping a selected copy removes it from the selection', (
      WidgetTester tester,
    ) async {
      await _pumpPhotoDuplicates(tester);

      await tester.tap(find.byKey(const Key('photo_copy_2')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('photo_duplicates_selection_bar')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('photo_copy_keep_2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('photo_copy_kept_2')), findsOneWidget);
      expect(
        find.byKey(const Key('photo_duplicates_selection_bar')),
        findsNothing,
      );
    });

    testWidgets('select copies never selects a kept photo', (
      WidgetTester tester,
    ) async {
      await _pumpPhotoDuplicates(tester);

      await tester.tap(find.byKey(const Key('photo_duplicates_select_all')));
      await tester.pumpAndSettle();

      // 3 removable copies out of 5 photos, never all of them.
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('photo_duplicates_selection_count')),
            )
            .data,
        '3 selected',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('photo_duplicates_selection_bytes')),
            )
            .data,
        '18.0 MB',
      );
    });

    testWidgets('a set can be selected on its own', (
      WidgetTester tester,
    ) async {
      await _pumpPhotoDuplicates(tester);

      await tester.tap(find.byKey(const Key('photo_group_select_fff')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('photo_duplicates_selection_count')),
            )
            .data,
        '1 selected',
      );
      final FilledButton delete = tester.widget<FilledButton>(
        find.byKey(const Key('photo_duplicates_selection_delete')),
      );
      expect(delete.onPressed, isNotNull);
    });

    testWidgets('an empty library says so', (WidgetTester tester) async {
      await _pumpPhotoDuplicates(
        tester,
        files: <ScannedFile>[
          _file(id: '1', name: 'only.jpg', sizeBytes: 5 * _mib),
        ],
      );

      expect(find.byKey(const Key('photo_duplicates_empty')), findsOneWidget);
      expect(
        find.byKey(const Key('photo_duplicates_selection_bar')),
        findsNothing,
      );
    });
  });
}
