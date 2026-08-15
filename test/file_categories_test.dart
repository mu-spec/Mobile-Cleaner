import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/files_screen.dart';

const int _mib = 1024 * 1024;

ScannedFile _file({
  required String id,
  required String name,
  required FileCategory category,
  required int sizeBytes,
  String? mimeType,
  DateTime? modified,
  String? uri,
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/${category.key}/$name',
    uri: uri ?? 'content://media/external/${category.key}/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: modified ?? DateTime(2026, 3, 1),
    mimeType: mimeType,
  );
}

/// One realistic file in every category, mirroring a real test phone.
List<ScannedFile> _libraryFixture() {
  return <ScannedFile>[
    _file(
      id: 'i1',
      name: 'beach.jpg',
      category: FileCategory.images,
      sizeBytes: 4 * _mib,
      mimeType: 'image/jpeg',
      modified: DateTime(2026, 1, 5),
    ),
    _file(
      id: 'v1',
      name: 'birthday.mp4',
      category: FileCategory.videos,
      sizeBytes: 210 * _mib,
      mimeType: 'video/mp4',
      modified: DateTime(2026, 2, 20),
    ),
    _file(
      id: 'a1',
      name: 'podcast.mp3',
      category: FileCategory.audio,
      sizeBytes: 30 * _mib,
      mimeType: 'audio/mpeg',
      modified: DateTime(2025, 12, 1),
    ),
    _file(
      id: 'd1',
      name: 'contract.pdf',
      category: FileCategory.documents,
      sizeBytes: 3 * _mib,
      mimeType: 'application/pdf',
      modified: DateTime(2026, 4, 2),
    ),
    _file(
      id: 'w1',
      name: 'installer.zip',
      category: FileCategory.downloads,
      sizeBytes: 12 * _mib,
      mimeType: 'application/zip',
      modified: DateTime(2026, 3, 15),
    ),
    _file(
      id: 'k1',
      name: 'app-release.apk',
      category: FileCategory.apks,
      sizeBytes: 45 * _mib,
      mimeType: 'application/vnd.android.package-archive',
      modified: DateTime(2026, 5, 9),
    ),
  ];
}

/// The one file each category owns in [_libraryFixture].
const Map<FileCategory, String> _expectedFileFor = <FileCategory, String>{
  FileCategory.images: 'beach.jpg',
  FileCategory.videos: 'birthday.mp4',
  FileCategory.audio: 'podcast.mp3',
  FileCategory.documents: 'contract.pdf',
  FileCategory.downloads: 'installer.zip',
  FileCategory.apks: 'app-release.apk',
};

class _StubRepository implements FileScannerRepository {
  const _StubRepository(this.result);

  final FileScanResult result;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => result;
}

Widget _wrap(FileScanResult result) {
  return ProviderScope(
    overrides: [
      fileScannerRepositoryProvider.overrideWithValue(_StubRepository(result)),
    ],
    child: const MaterialApp(home: FilesScreen()),
  );
}

Future<void> _pumpFiles(WidgetTester tester, FileScanResult result) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_wrap(result));
  await tester.pumpAndSettle();
}

void main() {
  group('Phase 7 categories', () {
    test('exposes exactly the six required categories in order', () {
      expect(FileCategory.scannable, <FileCategory>[
        FileCategory.images,
        FileCategory.videos,
        FileCategory.audio,
        FileCategory.documents,
        FileCategory.downloads,
        FileCategory.apks,
      ]);
      expect(
        FileCategory.scannable.map((FileCategory c) => c.label).toList(),
        <String>[
          'Images',
          'Videos',
          'Audio',
          'Documents',
          'Downloads',
          'APKs',
        ],
      );
    });

    test('apks key round-trips through the platform contract', () {
      expect(FileCategory.fromKey('apks'), FileCategory.apks);
      expect(FileCategory.apks.key, 'apks');
    });

    test('recognises APKs by extension and by MIME type', () {
      final ScannedFile byExtension = _file(
        id: '1',
        name: 'game.apk',
        category: FileCategory.downloads,
        sizeBytes: _mib,
      );
      final ScannedFile byMime = _file(
        id: '2',
        name: 'package',
        category: FileCategory.downloads,
        sizeBytes: _mib,
        mimeType: 'application/vnd.android.package-archive',
      );
      final ScannedFile notApk = _file(
        id: '3',
        name: 'notes.apk.txt',
        category: FileCategory.documents,
        sizeBytes: _mib,
        mimeType: 'text/plain',
      );

      expect(byExtension.isApk, isTrue);
      expect(byMime.isApk, isTrue);
      expect(notApk.isApk, isFalse);
    });

    test('every category reports its own real files', () {
      final FileScanResult result = FileScanResult.fromFiles(_libraryFixture());

      for (final FileCategory category in FileCategory.scannable) {
        final List<ScannedFile> files = result.byCategory(category);
        expect(
          files,
          hasLength(1),
          reason: '${category.label} should contain its fixture file',
        );
        expect(files.single.category, category);
        expect(result.summaryFor(category).fileCount, 1);
      }

      expect(result.summaryFor(FileCategory.apks).totalBytes, 45 * _mib);
      expect(result.summaryFor(FileCategory.videos).totalBytes, 210 * _mib);
    });

    test('a downloaded APK counts in both lists but only once in totals', () {
      // The same physical file, surfaced by two MediaStore queries.
      const String sharedUri = 'content://media/external/file/media/77';
      final FileScanResult result = FileScanResult.fromFiles(<ScannedFile>[
        _file(
          id: '77',
          name: 'tool.apk',
          category: FileCategory.downloads,
          sizeBytes: 20 * _mib,
          uri: sharedUri,
        ),
        _file(
          id: '77',
          name: 'tool.apk',
          category: FileCategory.apks,
          sizeBytes: 20 * _mib,
          uri: sharedUri,
        ),
      ]);

      expect(result.byCategory(FileCategory.downloads), hasLength(1));
      expect(result.byCategory(FileCategory.apks), hasLength(1));
      // Counted once, not twice.
      expect(result.totalFiles, 1);
      expect(result.totalBytes, 20 * _mib);
      expect(result.largestFiles(), hasLength(1));
    });

    test('sorting a category applies the requested order', () {
      final FileScanResult result = FileScanResult.fromFiles(<ScannedFile>[
        _file(
          id: '1',
          name: 'zebra.jpg',
          category: FileCategory.images,
          sizeBytes: 9 * _mib,
          modified: DateTime(2024, 1, 1),
        ),
        _file(
          id: '2',
          name: 'apple.jpg',
          category: FileCategory.images,
          sizeBytes: 2 * _mib,
          modified: DateTime(2026, 6, 1),
        ),
      ]);

      expect(
        result
            .sortedCategory(FileCategory.images, sort: FileListSort.largest)
            .first
            .name,
        'zebra.jpg',
      );
      expect(
        result
            .sortedCategory(FileCategory.images, sort: FileListSort.newest)
            .first
            .name,
        'apple.jpg',
      );
      expect(
        result
            .sortedCategory(FileCategory.images, sort: FileListSort.name)
            .first
            .name,
        'apple.jpg',
      );
    });
  });

  group('Files tab', () {
    testWidgets('shows a card for all six categories', (
      WidgetTester tester,
    ) async {
      await _pumpFiles(tester, FileScanResult.fromFiles(_libraryFixture()));

      for (final FileCategory category in FileCategory.scannable) {
        expect(
          find.byKey(Key('category_card_${category.key}')),
          findsOneWidget,
          reason: '${category.label} needs a card',
        );
      }
      expect(find.text('APKs'), findsOneWidget);
    });

    // One independent test per category. Separate tests give each case a
    // fresh binding, so a pushed route can never leak into the next check.
    for (final FileCategory category in FileCategory.scannable) {
      testWidgets('opening ${category.label} shows its real files', (
        WidgetTester tester,
      ) async {
        await _pumpFiles(tester, FileScanResult.fromFiles(_libraryFixture()));

        await tester.tap(find.byKey(Key('category_card_${category.key}')));
        await tester.pumpAndSettle();

        // The right list opened...
        expect(
          find.byKey(Key('category_list_${category.key}')),
          findsOneWidget,
          reason: '${category.label} list should open',
        );
        // ...showing that category's file...
        expect(
          find.text(_expectedFileFor[category]!),
          findsOneWidget,
          reason:
              '${category.label} should list ${_expectedFileFor[category]}',
        );
        // ...and nothing belonging to a different category.
        for (final MapEntry<FileCategory, String> other
            in _expectedFileFor.entries) {
          if (other.key != category) {
            expect(
              find.text(other.value),
              findsNothing,
              reason: '${other.value} does not belong in ${category.label}',
            );
          }
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an empty category explains itself instead of failing', (
      WidgetTester tester,
    ) async {
      final FileScanResult result = FileScanResult.fromFiles(<ScannedFile>[
        _file(
          id: 'i1',
          name: 'only-image.jpg',
          category: FileCategory.images,
          sizeBytes: _mib,
        ),
      ]);
      await _pumpFiles(tester, result);

      await tester.tap(find.byKey(const Key('category_card_apks')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('category_empty_apks')), findsOneWidget);
      expect(find.text('No APK files found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('category header reports count and size', (
      WidgetTester tester,
    ) async {
      await _pumpFiles(tester, FileScanResult.fromFiles(_libraryFixture()));

      await tester.tap(find.byKey(const Key('category_card_videos')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('category_header_videos')), findsOneWidget);
      expect(find.text('1 file · 210.0 MB'), findsOneWidget);
    });

    testWidgets('sorting reorders the open category', (
      WidgetTester tester,
    ) async {
      final FileScanResult result = FileScanResult.fromFiles(<ScannedFile>[
        _file(
          id: '1',
          name: 'big-old.jpg',
          category: FileCategory.images,
          sizeBytes: 80 * _mib,
          modified: DateTime(2023, 1, 1),
        ),
        _file(
          id: '2',
          name: 'small-new.jpg',
          category: FileCategory.images,
          sizeBytes: 2 * _mib,
          modified: DateTime(2026, 7, 1),
        ),
      ]);
      await _pumpFiles(tester, result);

      await tester.tap(find.byKey(const Key('category_card_images')));
      await tester.pumpAndSettle();

      double yOf(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(yOf('big-old.jpg'), lessThan(yOf('small-new.jpg')));

      await tester.tap(find.byKey(const Key('category_sort_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort_option_newest')));
      await tester.pumpAndSettle();

      expect(yOf('small-new.jpg'), lessThan(yOf('big-old.jpg')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('search filters the open category', (
      WidgetTester tester,
    ) async {
      final FileScanResult result = FileScanResult.fromFiles(<ScannedFile>[
        _file(
          id: '1',
          name: 'holiday.jpg',
          category: FileCategory.images,
          sizeBytes: _mib,
        ),
        _file(
          id: '2',
          name: 'receipt.jpg',
          category: FileCategory.images,
          sizeBytes: _mib,
        ),
      ]);
      await _pumpFiles(tester, result);

      await tester.tap(find.byKey(const Key('category_card_images')));
      await tester.pumpAndSettle();
      expect(find.text('holiday.jpg'), findsOneWidget);

      await tester.tap(find.byKey(const Key('category_search_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category_search_field')),
        'receipt',
      );
      await tester.pumpAndSettle();

      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(find.text('holiday.jpg'), findsNothing);

      await tester.tap(find.byKey(const Key('category_search_close')));
      await tester.pumpAndSettle();
      expect(find.text('holiday.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
