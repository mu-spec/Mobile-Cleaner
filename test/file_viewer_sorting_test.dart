import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/category_files_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';

const int _mib = 1024 * 1024;

/// A 1x1 transparent PNG, enough for `Image.memory` to decode successfully.
final Uint8List _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

ScannedFile _file({
  required String id,
  required String name,
  required FileCategory category,
  required int sizeBytes,
  DateTime? modified,
  String? mimeType,
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/${category.key}/$name',
    uri: 'content://media/external/${category.key}/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: modified ?? DateTime(2026, 3, 1),
    mimeType: mimeType,
  );
}

class _StubRepository implements FileScannerRepository {
  const _StubRepository(this.result);

  final FileScanResult result;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => result;
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

/// Returns real bytes for anything that supports a thumbnail.
class _FakeThumbnails implements ThumbnailRepository {
  _FakeThumbnails();

  final List<String> requested = <String>[];

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async {
    requested.add(file.uri);
    return file.supportsThumbnail ? _pngBytes : null;
  }
}

Future<void> _pumpCategory(
  WidgetTester tester,
  FileCategory category,
  List<ScannedFile> files, {
  ThumbnailRepository thumbnails = const _NoThumbnails(),
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(
          _StubRepository(FileScanResult.fromFiles(files)),
        ),
        thumbnailRepositoryProvider.overrideWithValue(thumbnails),
      ],
      child: MaterialApp(home: CategoryFilesScreen(category: category)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpFileTile(
  WidgetTester tester,
  ScannedFile file, {
  Size size = const Size(320, 640),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: ScannedFileTile(
              file: file,
              selectionMode: true,
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps a sort chip, scrolling it into view first.
Future<void> _tapSortChip(WidgetTester tester, FileListSort sort) async {
  final Finder chip = find.byKey(Key('sort_chip_${sort.name}'));
  await tester.scrollUntilVisible(
    chip,
    120,
    scrollable: find.descendant(
      of: find.byKey(const Key('sort_bar')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  group('Sort options', () {
    test('exposes the five required orders', () {
      expect(FileListSort.values, <FileListSort>[
        FileListSort.largest,
        FileListSort.smallest,
        FileListSort.newest,
        FileListSort.oldest,
        FileListSort.name,
      ]);
      expect(
        FileListSort.values.map((FileListSort s) => s.shortLabel).toList(),
        <String>['Largest', 'Smallest', 'Newest', 'Oldest', 'Name'],
      );
    });

    test('each comparator orders files correctly', () {
      final ScannedFile big = _file(
        id: '1',
        name: 'big.jpg',
        category: FileCategory.images,
        sizeBytes: 90 * _mib,
        modified: DateTime(2024, 1, 1),
      );
      final ScannedFile small = _file(
        id: '2',
        name: 'aaa-small.jpg',
        category: FileCategory.images,
        sizeBytes: 1 * _mib,
        modified: DateTime(2026, 6, 1),
      );
      final ScannedFile middle = _file(
        id: '3',
        name: 'mid.jpg',
        category: FileCategory.images,
        sizeBytes: 10 * _mib,
        modified: DateTime(2025, 5, 5),
      );

      List<String> ordered(FileListSort sort) {
        final List<ScannedFile> items = <ScannedFile>[big, small, middle]
          ..sort(FileScanResult.compareFiles(sort));
        return items.map((ScannedFile f) => f.name).toList();
      }

      expect(ordered(FileListSort.largest), <String>[
        'big.jpg',
        'mid.jpg',
        'aaa-small.jpg',
      ]);
      expect(ordered(FileListSort.smallest), <String>[
        'aaa-small.jpg',
        'mid.jpg',
        'big.jpg',
      ]);
      expect(ordered(FileListSort.newest), <String>[
        'aaa-small.jpg',
        'mid.jpg',
        'big.jpg',
      ]);
      expect(ordered(FileListSort.oldest), <String>[
        'big.jpg',
        'mid.jpg',
        'aaa-small.jpg',
      ]);
      expect(ordered(FileListSort.name), <String>[
        'aaa-small.jpg',
        'big.jpg',
        'mid.jpg',
      ]);
    });

    test('ties fall back to name for a stable order', () {
      final List<ScannedFile> items = <ScannedFile>[
        _file(
          id: '1',
          name: 'zulu.jpg',
          category: FileCategory.images,
          sizeBytes: 5 * _mib,
          modified: DateTime(2026, 1, 1),
        ),
        _file(
          id: '2',
          name: 'alpha.jpg',
          category: FileCategory.images,
          sizeBytes: 5 * _mib,
          modified: DateTime(2026, 1, 1),
        ),
      ]..sort(FileScanResult.compareFiles(FileListSort.largest));

      expect(items.first.name, 'alpha.jpg');
    });
  });

  group('DateFormatter', () {
    final DateTime now = DateTime(2026, 8, 15, 12);

    test('formats absolute dates', () {
      expect(DateFormatter.format(DateTime(2026, 8, 4)), '04 Aug 2026');
      expect(
        DateFormatter.format(DateTime.fromMillisecondsSinceEpoch(0)),
        'Unknown date',
      );
    });

    test('formats relative dates', () {
      expect(
        DateFormatter.relative(DateTime(2026, 8, 15, 9), now: now),
        'Today',
      );
      expect(
        DateFormatter.relative(DateTime(2026, 8, 14, 9), now: now),
        'Yesterday',
      );
      expect(
        DateFormatter.relative(DateTime(2026, 8, 10), now: now),
        '5 days ago',
      );
      // Beyond a month it falls back to the absolute date.
      expect(
        DateFormatter.relative(DateTime(2026, 1, 3), now: now),
        '03 Jan 2026',
      );
    });
  });

  group('ScannedFile.supportsThumbnail', () {
    test('is true for images and videos only', () {
      expect(
        _file(
          id: '1',
          name: 'a.jpg',
          category: FileCategory.images,
          sizeBytes: _mib,
        ).supportsThumbnail,
        isTrue,
      );
      expect(
        _file(
          id: '2',
          name: 'b.mp4',
          category: FileCategory.videos,
          sizeBytes: _mib,
        ).supportsThumbnail,
        isTrue,
      );
      expect(
        _file(
          id: '3',
          name: 'c.pdf',
          category: FileCategory.documents,
          sizeBytes: _mib,
        ).supportsThumbnail,
        isFalse,
      );
      // A picture sitting in Downloads is still previewable.
      expect(
        _file(
          id: '4',
          name: 'd.png',
          category: FileCategory.downloads,
          sizeBytes: _mib,
          mimeType: 'image/png',
        ).supportsThumbnail,
        isTrue,
      );
    });
  });

  group('File rows', () {
    testWidgets('show icon, name, size, and date', (WidgetTester tester) async {
      final ScannedFile doc = _file(
        id: 'd1',
        name: 'contract.pdf',
        category: FileCategory.documents,
        sizeBytes: 3 * _mib,
        modified: DateTime(2026, 2, 9),
      );
      await _pumpCategory(tester, FileCategory.documents, <ScannedFile>[doc]);

      expect(find.byKey(const Key('file_name_d1')), findsOneWidget);
      expect(find.text('contract.pdf'), findsOneWidget);
      expect(find.byKey(const Key('file_size_d1')), findsOneWidget);
      expect(find.text(ByteFormatter.format(3 * _mib)), findsOneWidget);
      expect(find.byKey(const Key('file_date_d1')), findsOneWidget);
      // A document has no preview, so it uses the category icon.
      expect(find.byKey(const Key('thumbnail_icon_d1')), findsOneWidget);
      expect(find.byKey(const Key('thumbnail_image_d1')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('metadata stays responsive on a narrow large-text screen', (
      WidgetTester tester,
    ) async {
      final ScannedFile doc = _file(
        id: 'd3',
        name: 'a-very-long-contract-filename.pdf',
        category: FileCategory.documents,
        sizeBytes: 300 * _mib,
        modified: DateTime(2026, 2, 9),
      );
      await _pumpFileTile(tester, doc, textScale: 1.8);

      expect(find.byKey(const Key('file_size_d3')), findsOneWidget);
      expect(find.byKey(const Key('file_date_d3')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('render a real thumbnail for images', (
      WidgetTester tester,
    ) async {
      final _FakeThumbnails thumbnails = _FakeThumbnails();
      final ScannedFile image = _file(
        id: 'i1',
        name: 'beach.jpg',
        category: FileCategory.images,
        sizeBytes: 4 * _mib,
      );

      await _pumpCategory(
        tester,
        FileCategory.images,
        <ScannedFile>[image],
        thumbnails: thumbnails,
      );
      // Image.memory decodes asynchronously; let the codec finish.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thumbnail_image_i1')), findsOneWidget);
      expect(find.byKey(const Key('thumbnail_icon_i1')), findsNothing);
      expect(thumbnails.requested, contains(image.uri));
      expect(tester.takeException(), isNull);
    });

    testWidgets('fall back to an icon when no thumbnail exists', (
      WidgetTester tester,
    ) async {
      final ScannedFile image = _file(
        id: 'i9',
        name: 'broken.jpg',
        category: FileCategory.images,
        sizeBytes: _mib,
      );
      await _pumpCategory(tester, FileCategory.images, <ScannedFile>[image]);

      expect(find.byKey(const Key('thumbnail_icon_i9')), findsOneWidget);
      expect(find.byKey(const Key('thumbnail_image_i9')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('open a details sheet on tap', (WidgetTester tester) async {
      final ScannedFile doc = _file(
        id: 'd2',
        name: 'notes.txt',
        category: FileCategory.documents,
        sizeBytes: 2048,
        modified: DateTime(2026, 4, 7),
      );
      await _pumpCategory(tester, FileCategory.documents, <ScannedFile>[doc]);

      await tester.tap(find.byKey(const Key('file_tile_d2')));
      await tester.pumpAndSettle();

      // Labels are unique to the sheet.
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Modified'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      // The absolute date may also appear in the row behind the sheet, so
      // assert presence rather than an exact count.
      expect(find.text('07 Apr 2026'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('Sorting the list', () {
    List<ScannedFile> fixture() => <ScannedFile>[
      _file(
        id: '1',
        name: 'medium.jpg',
        category: FileCategory.images,
        sizeBytes: 20 * _mib,
        modified: DateTime(2025, 6, 1),
      ),
      _file(
        id: '2',
        name: 'zeta-largest.jpg',
        category: FileCategory.images,
        sizeBytes: 90 * _mib,
        modified: DateTime(2024, 1, 1),
      ),
      _file(
        id: '3',
        name: 'alpha-smallest.jpg',
        category: FileCategory.images,
        sizeBytes: 2 * _mib,
        modified: DateTime(2026, 7, 1),
      ),
    ];

    double yOf(WidgetTester tester, String name) =>
        tester.getTopLeft(find.text(name)).dy;

    testWidgets('every sort chip is shown and defaults to largest', (
      WidgetTester tester,
    ) async {
      await _pumpCategory(tester, FileCategory.images, fixture());

      // The bar scrolls horizontally, so later chips are not laid out until
      // they are scrolled into view.
      for (final FileListSort option in FileListSort.values) {
        final Finder chip = find.byKey(Key('sort_chip_${option.name}'));
        await tester.scrollUntilVisible(
          chip,
          120,
          scrollable: find.descendant(
            of: find.byKey(const Key('sort_bar')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          chip,
          findsOneWidget,
          reason: '${option.shortLabel} chip should be visible',
        );
      }
      expect(find.text('Largest first'), findsOneWidget);
      expect(
        yOf(tester, 'zeta-largest.jpg'),
        lessThan(yOf(tester, 'alpha-smallest.jpg')),
      );
    });

    // Expected top row for each sort, given the fixture above.
    const Map<FileListSort, String> expectedFirst = <FileListSort, String>{
      FileListSort.smallest: 'alpha-smallest.jpg',
      FileListSort.newest: 'alpha-smallest.jpg',
      FileListSort.oldest: 'zeta-largest.jpg',
      FileListSort.name: 'alpha-smallest.jpg',
    };
    const Map<FileListSort, String> expectedLast = <FileListSort, String>{
      FileListSort.smallest: 'zeta-largest.jpg',
      FileListSort.newest: 'zeta-largest.jpg',
      FileListSort.oldest: 'alpha-smallest.jpg',
      FileListSort.name: 'zeta-largest.jpg',
    };

    for (final FileListSort sort in expectedFirst.keys) {
      testWidgets('tapping the ${sort.shortLabel} chip reorders the list', (
        WidgetTester tester,
      ) async {
        await _pumpCategory(tester, FileCategory.images, fixture());

        await _tapSortChip(tester, sort);

        final String first = expectedFirst[sort]!;
        final String last = expectedLast[sort]!;
        expect(
          yOf(tester, first),
          lessThan(yOf(tester, last)),
          reason: '$first should sort above $last',
        );
        expect(find.text(sort.label), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the app bar menu offers the same five orders', (
      WidgetTester tester,
    ) async {
      await _pumpCategory(tester, FileCategory.images, fixture());

      await tester.tap(find.byKey(const Key('category_sort_button')));
      await tester.pumpAndSettle();

      for (final FileListSort option in FileListSort.values) {
        expect(
          find.byKey(Key('sort_option_${option.name}')),
          findsOneWidget,
          reason: '${option.shortLabel} should be in the menu',
        );
      }

      await tester.tap(find.byKey(const Key('sort_option_oldest')));
      await tester.pumpAndSettle();

      expect(
        yOf(tester, 'zeta-largest.jpg'),
        lessThan(yOf(tester, 'alpha-smallest.jpg')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sorting survives searching', (WidgetTester tester) async {
      await _pumpCategory(tester, FileCategory.images, fixture());

      await _tapSortChip(tester, FileListSort.name);

      await tester.tap(find.byKey(const Key('category_search_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category_search_field')),
        'jpg',
      );
      await tester.pumpAndSettle();

      expect(
        yOf(tester, 'alpha-smallest.jpg'),
        lessThan(yOf(tester, 'zeta-largest.jpg')),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
