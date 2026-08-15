import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_channel.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/files_screen.dart';

const int _mib = 1024 * 1024;

Map<String, Object?> _row({
  required String id,
  required String name,
  required String category,
  required int sizeBytes,
  String? path,
  String? mimeType,
  int? dateModifiedMillis,
  String? relativePath,
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'path': path ?? '/storage/emulated/0/DCIM/Camera/$name',
    'uri': 'content://media/external/$category/media/$id',
    'sizeBytes': sizeBytes,
    'mimeType': mimeType,
    'dateModifiedMillis':
        dateModifiedMillis ?? DateTime(2026, 2, 14).millisecondsSinceEpoch,
    'relativePath': relativePath ?? 'DCIM/Camera/',
    'category': category,
  };
}

class _FakeScannerChannel implements FileScannerChannel {
  _FakeScannerChannel(this.payload);

  final Map<Object?, Object?> payload;
  int callCount = 0;
  List<FileCategory>? lastCategories;
  int? lastMinSize;

  @override
  Future<Map<Object?, Object?>> scan({
    required List<FileCategory> categories,
    required int limitPerCategory,
    required int minSizeBytes,
    required FileSortOrder sortOrder,
  }) async {
    callCount++;
    lastCategories = categories;
    lastMinSize = minSizeBytes;
    return payload;
  }
}

class _ThrowingChannel implements FileScannerChannel {
  @override
  Future<Map<Object?, Object?>> scan({
    required List<FileCategory> categories,
    required int limitPerCategory,
    required int minSizeBytes,
    required FileSortOrder sortOrder,
  }) async {
    throw Exception('SCAN_PERMISSION_DENIED');
  }
}

class _StubRepository implements FileScannerRepository {
  const _StubRepository(this.result);

  final FileScanResult result;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => result;
}

void main() {
  group('ScannedFile model', () {
    test('parses a platform row into every required field', () {
      final ScannedFile? file = ScannedFile.fromPlatformMap(
        _row(
          id: '42',
          name: 'IMG_0042.jpg',
          category: 'images',
          sizeBytes: 3 * _mib,
          mimeType: 'image/jpeg',
        ),
      );

      expect(file, isNotNull);
      expect(file!.id, '42');
      expect(file.name, 'IMG_0042.jpg');
      expect(file.path, '/storage/emulated/0/DCIM/Camera/IMG_0042.jpg');
      expect(file.uri, 'content://media/external/images/media/42');
      expect(file.sizeBytes, 3 * _mib);
      expect(file.category, FileCategory.images);
      expect(file.mimeType, 'image/jpeg');
      expect(file.dateModified.year, 2026);
      expect(file.extension, 'jpg');
      expect(file.folderName, 'Camera');
    });

    test('derives a name from the path and tolerates missing fields', () {
      final ScannedFile? file = ScannedFile.fromPlatformMap(<Object?, Object?>{
        'path': '/storage/emulated/0/Download/report.pdf',
        'uri': '',
        'category': 'downloads',
      });

      expect(file, isNotNull);
      expect(file!.name, 'report.pdf');
      expect(file.sizeBytes, 0);
      expect(file.uri, 'file:///storage/emulated/0/Download/report.pdf');
      expect(file.category, FileCategory.downloads);
    });

    test('rejects rows without any identity', () {
      expect(
        ScannedFile.fromPlatformMap(<Object?, Object?>{'name': 'ghost.txt'}),
        isNull,
      );
    });

    test('unknown category keys fall back to other', () {
      expect(FileCategory.fromKey('spreadsheets'), FileCategory.other);
      expect(FileCategory.fromKey('videos'), FileCategory.videos);
    });
  });

  group('FileScanResult', () {
    test('aggregates counts, sizes, and ordering', () {
      final FileScanResult result = FileScanResult.fromFiles(<ScannedFile>[
        ScannedFile.fromPlatformMap(
          _row(id: '1', name: 'a.jpg', category: 'images', sizeBytes: 2 * _mib),
        )!,
        ScannedFile.fromPlatformMap(
          _row(id: '2', name: 'b.jpg', category: 'images', sizeBytes: 4 * _mib),
        )!,
        ScannedFile.fromPlatformMap(
          _row(
            id: '3',
            name: 'clip.mp4',
            category: 'videos',
            sizeBytes: 90 * _mib,
          ),
        )!,
      ]);

      expect(result.totalFiles, 3);
      expect(result.totalBytes, 96 * _mib);
      expect(result.summaryFor(FileCategory.images).fileCount, 2);
      expect(result.summaryFor(FileCategory.images).totalBytes, 6 * _mib);
      expect(result.summaryFor(FileCategory.audio).isEmpty, isTrue);
      expect(result.summariesBySize.first.category, FileCategory.videos);
      expect(result.largestFiles(limit: 2).first.name, 'clip.mp4');
      expect(result.byCategory(FileCategory.videos), hasLength(1));
    });
  });

  group('MediaStoreFileScannerRepository', () {
    test('maps the payload, de-duplicates rows, and keeps metadata', () async {
      final _FakeScannerChannel channel = _FakeScannerChannel(
        <Object?, Object?>{
          'files': <Object?>[
            _row(id: '1', name: 'a.jpg', category: 'images', sizeBytes: _mib),
            // Duplicate id in the same category is dropped.
            _row(id: '1', name: 'a.jpg', category: 'images', sizeBytes: _mib),
            _row(
              id: '9',
              name: 'song.mp3',
              category: 'audio',
              sizeBytes: 5 * _mib,
            ),
            'not-a-map',
            <Object?, Object?>{'name': 'broken'},
          ],
          'truncated': true,
          'durationMillis': 137,
        },
      );

      final FileScanResult result = await MediaStoreFileScannerRepository(
        channel,
      ).scan();

      expect(channel.callCount, 1);
      expect(channel.lastCategories, FileCategory.scannable);
      expect(result.totalFiles, 2);
      expect(result.truncated, isTrue);
      expect(result.durationMillis, 137);
      expect(result.summaryFor(FileCategory.audio).totalBytes, 5 * _mib);
    });

    test('forwards request options to the channel', () async {
      final _FakeScannerChannel channel = _FakeScannerChannel(
        <Object?, Object?>{'files': <Object?>[]},
      );

      await MediaStoreFileScannerRepository(channel).scan(
        const FileScanRequest(
          categories: <FileCategory>[FileCategory.downloads],
          minSizeBytes: 10 * _mib,
        ),
      );

      expect(channel.lastCategories, <FileCategory>[FileCategory.downloads]);
      expect(channel.lastMinSize, 10 * _mib);
    });

    test('propagates scanner failures', () {
      expect(
        () => MediaStoreFileScannerRepository(_ThrowingChannel()).scan(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ByteFormatter', () {
    test('formats each unit', () {
      expect(ByteFormatter.format(512), '512 B');
      expect(ByteFormatter.format(2048), '2.0 KB');
      expect(ByteFormatter.format(5 * _mib), '5.0 MB');
      expect(ByteFormatter.format(3 * 1024 * _mib), '3.0 GB');
      expect(ByteFormatter.format(-4), '0 B');
    });
  });

  group('Files screen', () {
    Widget wrap(Widget child, FileScanResult result) {
      return ProviderScope(
        overrides: [
          fileScannerRepositoryProvider.overrideWithValue(
            _StubRepository(result),
          ),
        ],
        child: MaterialApp(home: child),
      );
    }

    testWidgets('renders discovered categories and largest files', (
      WidgetTester tester,
    ) async {
      final FileScanResult result = FileScanResult.fromFiles(<ScannedFile>[
        ScannedFile.fromPlatformMap(
          _row(
            id: '1',
            name: 'holiday.jpg',
            category: 'images',
            sizeBytes: 8 * _mib,
          ),
        )!,
        ScannedFile.fromPlatformMap(
          _row(
            id: '2',
            name: 'movie.mp4',
            category: 'videos',
            sizeBytes: 120 * _mib,
          ),
        )!,
        ScannedFile.fromPlatformMap(
          _row(
            id: '3',
            name: 'invoice.pdf',
            category: 'documents',
            sizeBytes: 2 * _mib,
          ),
        )!,
      ]);

      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const FilesScreen(), result));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('files_overview')), findsOneWidget);
      expect(find.text('3 files · 130.0 MB'), findsOneWidget);

      // Every category has a card, including the ones with no files.
      for (final FileCategory category in FileCategory.scannable) {
        expect(
          find.byKey(Key('category_card_${category.key}')),
          findsOneWidget,
          reason: '${category.label} card should always be shown',
        );
      }

      await tester.scrollUntilVisible(
        find.text('movie.mp4'),
        320,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('files_overview')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('movie.mp4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens the category detail list', (WidgetTester tester) async {
      final FileScanResult result = FileScanResult.fromFiles(<ScannedFile>[
        ScannedFile.fromPlatformMap(
          _row(
            id: '7',
            name: 'track.mp3',
            category: 'audio',
            sizeBytes: 6 * _mib,
          ),
        )!,
      ]);

      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const FilesScreen(), result));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('category_card_audio')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('category_list_audio')), findsOneWidget);
      expect(find.text('track.mp3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the empty state when nothing is found', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        wrap(const FilesScreen(), FileScanResult.fromFiles(<ScannedFile>[])),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('files_overview')), findsOneWidget);
      expect(find.text('No files found'), findsOneWidget);
    });
  });
}
