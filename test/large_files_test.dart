import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_summary.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/large_files_screen.dart';

const int _mib = 1024 * 1024;
const int _gib = 1024 * 1024 * 1024;

ScannedFile _file({
  required String id,
  required String name,
  required FileCategory category,
  required int sizeBytes,
  String? uri,
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/${category.key}/$name',
    uri: uri ?? 'content://media/external/${category.key}/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: DateTime(2026, 5, 1),
  );
}

/// A spread of sizes straddling every threshold.
List<ScannedFile> _fixture() => <ScannedFile>[
  _file(
    id: '1',
    name: 'huge-movie.mp4',
    category: FileCategory.videos,
    sizeBytes: 2 * _gib,
  ),
  _file(
    id: '2',
    name: 'backup.zip',
    category: FileCategory.documents,
    sizeBytes: 700 * _mib,
  ),
  _file(
    id: '3',
    name: 'album.mp3',
    category: FileCategory.audio,
    sizeBytes: 150 * _mib,
  ),
  // Below every threshold; must never appear.
  _file(
    id: '4',
    name: 'small.jpg',
    category: FileCategory.images,
    sizeBytes: 4 * _mib,
  ),
];

class _StubRepository implements FileScannerRepository {
  _StubRepository(this.files);

  final List<ScannedFile> files;
  FileScanRequest? lastRequest;
  int scanCount = 0;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    scanCount++;
    lastRequest = request;
    // Mirror the native contract: the scanner honours minSizeBytes.
    return FileScanResult.fromFiles(
      files
          .where((ScannedFile f) => f.sizeBytes >= request.minSizeBytes)
          .toList(),
    );
  }
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

Future<_StubRepository> _pumpLargeFiles(
  WidgetTester tester, {
  List<ScannedFile>? files,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubRepository repository = _StubRepository(files ?? _fixture());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(repository),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
      ],
      child: const MaterialApp(home: LargeFilesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  group('LargeFileFilter', () {
    test('offers exactly the three required thresholds', () {
      expect(LargeFileFilter.values, <LargeFileFilter>[
        LargeFileFilter.over100mb,
        LargeFileFilter.over500mb,
        LargeFileFilter.over1gb,
      ]);
      expect(
        LargeFileFilter.values.map((LargeFileFilter f) => f.label).toList(),
        <String>['100 MB+', '500 MB+', '1 GB+'],
      );
    });

    test('uses correct byte bounds', () {
      expect(LargeFileFilter.over100mb.minBytes, 100 * _mib);
      expect(LargeFileFilter.over500mb.minBytes, 500 * _mib);
      expect(LargeFileFilter.over1gb.minBytes, _gib);
      expect(LargeFileFilter.lowestBound, 100 * _mib);
      expect(LargeFileFilter.defaultFilter, LargeFileFilter.over100mb);
    });

    test('matches on an inclusive bound', () {
      expect(LargeFileFilter.over100mb.matches(100 * _mib), isTrue);
      expect(LargeFileFilter.over100mb.matches(100 * _mib - 1), isFalse);
      expect(LargeFileFilter.over1gb.matches(_gib), isTrue);
    });
  });

  group('LargeFileSummary', () {
    test('filters and totals for each threshold', () {
      final List<ScannedFile> files = _fixture();

      final LargeFileSummary over100 = LargeFileSummary.from(
        files,
        LargeFileFilter.over100mb,
      );
      expect(over100.fileCount, 3);
      expect(over100.totalBytes, 2 * _gib + 700 * _mib + 150 * _mib);

      final LargeFileSummary over500 = LargeFileSummary.from(
        files,
        LargeFileFilter.over500mb,
      );
      expect(over500.fileCount, 2);
      expect(over500.totalBytes, 2 * _gib + 700 * _mib);

      final LargeFileSummary over1gb = LargeFileSummary.from(
        files,
        LargeFileFilter.over1gb,
      );
      expect(over1gb.fileCount, 1);
      expect(over1gb.totalBytes, 2 * _gib);
      expect(over1gb.largestFile?.name, 'huge-movie.mp4');
    });

    test('sorts matches largest first', () {
      final LargeFileSummary summary = LargeFileSummary.from(
        _fixture(),
        LargeFileFilter.over100mb,
      );
      expect(
        summary.files.map((ScannedFile f) => f.name).toList(),
        <String>['huge-movie.mp4', 'backup.zip', 'album.mp3'],
      );
    });

    test('counts a file shared by two categories only once', () {
      const String sharedUri = 'content://media/external/file/media/9';
      final LargeFileSummary summary = LargeFileSummary.from(<ScannedFile>[
        _file(
          id: '9',
          name: 'tool.apk',
          category: FileCategory.downloads,
          sizeBytes: 600 * _mib,
          uri: sharedUri,
        ),
        _file(
          id: '9',
          name: 'tool.apk',
          category: FileCategory.apks,
          sizeBytes: 600 * _mib,
          uri: sharedUri,
        ),
      ], LargeFileFilter.over500mb);

      expect(summary.fileCount, 1);
      expect(summary.totalBytes, 600 * _mib);
    });

    test('is empty when nothing is big enough', () {
      final LargeFileSummary summary = LargeFileSummary.from(<ScannedFile>[
        _file(
          id: '1',
          name: 'tiny.jpg',
          category: FileCategory.images,
          sizeBytes: _mib,
        ),
      ], LargeFileFilter.over100mb);

      expect(summary.isEmpty, isTrue);
      expect(summary.totalBytes, 0);
      expect(summary.largestFile, isNull);
    });

    test('breaks the total down by category, biggest first', () {
      final LargeFileSummary summary = LargeFileSummary.from(
        _fixture(),
        LargeFileFilter.over100mb,
      );
      final List<MapEntry<FileCategory, int>> breakdown =
          summary.bytesByCategory;

      expect(breakdown.first.key, FileCategory.videos);
      expect(breakdown.first.value, 2 * _gib);
      expect(breakdown.last.key, FileCategory.audio);
    });
  });

  group('Large Files screen', () {
    testWidgets('shows the three filter chips, defaulting to 100 MB+', (
      WidgetTester tester,
    ) async {
      await _pumpLargeFiles(tester);

      for (final LargeFileFilter option in LargeFileFilter.values) {
        expect(
          find.byKey(Key('large_filter_${option.name}')),
          findsOneWidget,
          reason: '${option.label} chip should be visible',
        );
      }
      expect(find.text('3 files over 100 MB'), findsOneWidget);
    });

    testWidgets('displays the total space used', (WidgetTester tester) async {
      await _pumpLargeFiles(tester);

      expect(find.byKey(const Key('large_files_total_card')), findsOneWidget);
      // 2 GB + 700 MB + 150 MB = 2.8 GB
      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_files_total_bytes')))
            .data,
        '2.8 GB',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists matching files biggest first', (
      WidgetTester tester,
    ) async {
      await _pumpLargeFiles(tester);

      expect(find.text('huge-movie.mp4'), findsOneWidget);
      expect(find.text('backup.zip'), findsOneWidget);
      expect(find.text('album.mp3'), findsOneWidget);
      // Below the threshold, so it must not be listed.
      expect(find.text('small.jpg'), findsNothing);

      expect(
        tester.getTopLeft(find.text('huge-movie.mp4')).dy,
        lessThan(tester.getTopLeft(find.text('album.mp3')).dy),
      );
    });

    testWidgets('switching to 500 MB+ narrows the list and total', (
      WidgetTester tester,
    ) async {
      await _pumpLargeFiles(tester);

      await tester.tap(find.byKey(const Key('large_filter_over500mb')));
      await tester.pumpAndSettle();

      expect(find.text('huge-movie.mp4'), findsOneWidget);
      expect(find.text('backup.zip'), findsOneWidget);
      expect(find.text('album.mp3'), findsNothing);
      // 2 GB + 700 MB = 2.7 GB
      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_files_total_bytes')))
            .data,
        '2.7 GB',
      );
      expect(find.text('2 files over 500 MB'), findsOneWidget);
    });

    testWidgets('switching to 1 GB+ keeps only the biggest file', (
      WidgetTester tester,
    ) async {
      await _pumpLargeFiles(tester);

      await tester.tap(find.byKey(const Key('large_filter_over1gb')));
      await tester.pumpAndSettle();

      expect(find.text('huge-movie.mp4'), findsOneWidget);
      expect(find.text('backup.zip'), findsNothing);
      // '2.0 GB' also appears in the category breakdown, so read the
      // headline widget directly rather than matching the string.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('large_files_total_bytes')))
            .data,
        '2.0 GB',
      );
      expect(find.text('1 file over 1 GB'), findsOneWidget);
    });

    testWidgets('changing a filter does not trigger another device scan', (
      WidgetTester tester,
    ) async {
      final _StubRepository repository = await _pumpLargeFiles(tester);
      expect(repository.scanCount, 1);

      await tester.tap(find.byKey(const Key('large_filter_over500mb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('large_filter_over1gb')));
      await tester.pumpAndSettle();

      // Still one scan: chips filter the cached result in memory.
      expect(repository.scanCount, 1);
    });

    testWidgets('asks the scanner for the lowest threshold', (
      WidgetTester tester,
    ) async {
      final _StubRepository repository = await _pumpLargeFiles(tester);

      expect(repository.lastRequest?.minSizeBytes, LargeFileFilter.lowestBound);
    });

    testWidgets('shows a reassuring empty state', (WidgetTester tester) async {
      await _pumpLargeFiles(
        tester,
        files: <ScannedFile>[
          _file(
            id: '1',
            name: 'tiny.jpg',
            category: FileCategory.images,
            sizeBytes: _mib,
          ),
        ],
      );

      expect(find.byKey(const Key('large_files_empty')), findsOneWidget);
      expect(find.text('No files over 100 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('breaks the total down by category', (
      WidgetTester tester,
    ) async {
      await _pumpLargeFiles(tester);

      expect(find.byKey(const Key('large_files_breakdown')), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Documents'), findsOneWidget);
    });
  });
}
