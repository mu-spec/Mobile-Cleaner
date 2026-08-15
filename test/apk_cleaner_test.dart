import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/apk_summary.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/apk_cleaner_screen.dart';

const int _mib = 1024 * 1024;
const String _apkMime = 'application/vnd.android.package-archive';

ScannedFile _file({
  required String id,
  required String name,
  required int sizeBytes,
  FileCategory category = FileCategory.apks,
  String? mimeType,
  DateTime? modified,
  String? uri,
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/Download/$name',
    uri: uri ?? 'content://media/external/${category.key}/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: modified ?? DateTime(2026, 4, 10),
    mimeType: mimeType,
  );
}

/// Installers of varied size and age, plus non-APKs that must be excluded.
List<ScannedFile> _fixture() => <ScannedFile>[
  _file(
    id: '1',
    name: 'maps-update.apk',
    sizeBytes: 90 * _mib,
    mimeType: _apkMime,
    modified: DateTime(2025, 11, 2),
  ),
  _file(
    id: '2',
    name: 'alpha-game.apk',
    sizeBytes: 30 * _mib,
    category: FileCategory.downloads,
    modified: DateTime(2026, 6, 20),
  ),
  _file(
    id: '3',
    name: 'zeta-tool.apk',
    sizeBytes: 5 * _mib,
    category: FileCategory.documents,
    modified: DateTime(2026, 1, 15),
  ),
  // Not installers; must never appear.
  _file(
    id: '4',
    name: 'notes.apk.txt',
    sizeBytes: 2 * _mib,
    category: FileCategory.documents,
    mimeType: 'text/plain',
  ),
  _file(
    id: '5',
    name: 'holiday.jpg',
    sizeBytes: 8 * _mib,
    category: FileCategory.images,
    mimeType: 'image/jpeg',
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
    return FileScanResult.fromFiles(files, categories: request.categories);
  }
}

/// Deletion is confirmed by a real platform dialog, which does not exist in
/// tests. Recording the request keeps these suites hermetic.
class _RecordingDeleteRepository implements DeleteRepository {
  final List<List<ScannedFile>> requests = <List<ScannedFile>>[];

  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async {
    requests.add(files);
    return DeleteResult(
      deletedFiles: files,
      failures: const <DeleteFailure>[],
    );
  }
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

Future<_StubRepository> _pumpApkCleaner(
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
        deleteRepositoryProvider.overrideWithValue(_RecordingDeleteRepository()),
      ],
      child: const MaterialApp(home: ApkCleanerScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  group('ApkSummary', () {
    test('keeps only real installers', () {
      final ApkSummary summary = ApkSummary.from(_fixture());

      expect(summary.fileCount, 3);
      expect(
        summary.files.map((ScannedFile f) => f.name),
        isNot(contains('notes.apk.txt')),
      );
      expect(
        summary.files.map((ScannedFile f) => f.name),
        isNot(contains('holiday.jpg')),
      );
    });

    test('finds installers regardless of category', () {
      final ApkSummary summary = ApkSummary.from(_fixture());
      final Set<FileCategory> categories = summary.files
          .map((ScannedFile f) => f.category)
          .toSet();

      // One from APKs, one from Downloads, one from Documents.
      expect(categories, hasLength(3));
    });

    test('detects an installer by MIME type alone', () {
      final ApkSummary summary = ApkSummary.from(<ScannedFile>[
        _file(
          id: '1',
          name: 'package-no-extension',
          sizeBytes: _mib,
          mimeType: _apkMime,
        ),
      ]);

      expect(summary.fileCount, 1);
    });

    test('totals the space installers occupy', () {
      final ApkSummary summary = ApkSummary.from(_fixture());
      expect(summary.totalBytes, (90 + 30 + 5) * _mib);
    });

    test('counts a package reported twice only once', () {
      const String sharedUri = 'content://media/external/file/media/9';
      final ApkSummary summary = ApkSummary.from(<ScannedFile>[
        _file(
          id: '9',
          name: 'tool.apk',
          sizeBytes: 40 * _mib,
          category: FileCategory.downloads,
          uri: sharedUri,
        ),
        _file(
          id: '9',
          name: 'tool.apk',
          sizeBytes: 40 * _mib,
          uri: sharedUri,
        ),
      ]);

      expect(summary.fileCount, 1);
      expect(summary.totalBytes, 40 * _mib);
    });

    test('applies each sort order', () {
      List<String> namesFor(FileListSort sort) =>
          ApkSummary.from(_fixture(), sort: sort)
              .files
              .map((ScannedFile f) => f.name)
              .toList();

      expect(namesFor(FileListSort.largest).first, 'maps-update.apk');
      expect(namesFor(FileListSort.smallest).first, 'zeta-tool.apk');
      expect(namesFor(FileListSort.newest).first, 'alpha-game.apk');
      expect(namesFor(FileListSort.oldest).first, 'maps-update.apk');
      expect(namesFor(FileListSort.name).first, 'alpha-game.apk');
    });

    test('reports the largest installer', () {
      expect(ApkSummary.from(_fixture()).largestFile?.name, 'maps-update.apk');
    });

    test('is empty when no installers exist', () {
      final ApkSummary summary = ApkSummary.from(<ScannedFile>[
        _file(
          id: '1',
          name: 'photo.jpg',
          sizeBytes: _mib,
          category: FileCategory.images,
          mimeType: 'image/jpeg',
        ),
      ]);

      expect(summary.isEmpty, isTrue);
      expect(summary.totalBytes, 0);
      expect(summary.largestFile, isNull);
    });
  });

  group('APK cleaner screen', () {
    testWidgets('scans everywhere an installer can appear', (
      WidgetTester tester,
    ) async {
      final _StubRepository repository = await _pumpApkCleaner(tester);

      expect(repository.lastRequest?.categories, <FileCategory>[
        FileCategory.apks,
        FileCategory.downloads,
        FileCategory.documents,
      ]);
    });

    testWidgets('shows each installer name, size, and date', (
      WidgetTester tester,
    ) async {
      await _pumpApkCleaner(tester);

      // Name.
      expect(
        tester.widget<Text>(find.byKey(const Key('file_name_1'))).data,
        'maps-update.apk',
      );
      // Size. Read the keyed widget rather than matching the string, which
      // the selection bar can also render once a row is picked.
      expect(
        tester.widget<Text>(find.byKey(const Key('file_size_1'))).data,
        '90.0 MB',
      );
      // Date.
      expect(
        tester.widget<Text>(find.byKey(const Key('file_date_1'))).data,
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('excludes files that only look like installers', (
      WidgetTester tester,
    ) async {
      await _pumpApkCleaner(tester);

      expect(find.text('notes.apk.txt'), findsNothing);
      expect(find.text('holiday.jpg'), findsNothing);
    });

    testWidgets('displays the combined installer size', (
      WidgetTester tester,
    ) async {
      await _pumpApkCleaner(tester);

      expect(find.byKey(const Key('apk_total_card')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('apk_total_bytes'))).data,
        '125.0 MB',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('apk_count'))).data,
        '3 installers found',
      );
    });

    testWidgets('lists largest first by default', (WidgetTester tester) async {
      await _pumpApkCleaner(tester);

      expect(
        tester.getTopLeft(find.text('maps-update.apk')).dy,
        lessThan(tester.getTopLeft(find.text('zeta-tool.apk')).dy),
      );
    });

    testWidgets('sorting reorders without rescanning', (
      WidgetTester tester,
    ) async {
      final _StubRepository repository = await _pumpApkCleaner(tester);
      expect(repository.scanCount, 1);

      await tester.tap(find.byKey(const Key('apk_sort_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_sort_smallest')));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('zeta-tool.apk')).dy,
        lessThan(tester.getTopLeft(find.text('maps-update.apk')).dy),
      );
      // Sorting filters the cached scan in memory.
      expect(repository.scanCount, 1);
    });

    testWidgets('selecting a row reveals the selection bar', (
      WidgetTester tester,
    ) async {
      await _pumpApkCleaner(tester);
      expect(find.byKey(const Key('apk_selection_bar')), findsNothing);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('apk_selection_bar')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('apk_selection_count'))).data,
        '1 selected',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('apk_selection_bytes'))).data,
        '90.0 MB',
      );
    });

    testWidgets('selecting several installers totals their size', (
      WidgetTester tester,
    ) async {
      await _pumpApkCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('file_checkbox_2')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('apk_selection_count'))).data,
        '2 selected',
      );
      // 90 MB + 30 MB
      expect(
        tester.widget<Text>(find.byKey(const Key('apk_selection_bytes'))).data,
        '120.0 MB',
      );
    });

    testWidgets('tapping a selected row deselects it', (
      WidgetTester tester,
    ) async {
      await _pumpApkCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('apk_selection_bar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('apk_selection_bar')), findsNothing);
    });

    testWidgets('select all then clear all', (WidgetTester tester) async {
      await _pumpApkCleaner(tester);

      await tester.tap(find.byKey(const Key('apk_select_all')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('apk_selection_count'))).data,
        '3 selected',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('apk_selection_bytes'))).data,
        '125.0 MB',
      );

      await tester.tap(find.byKey(const Key('apk_select_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('apk_selection_bar')), findsNothing);
    });

    testWidgets('the app bar reflects the selection count', (
      WidgetTester tester,
    ) async {
      await _pumpApkCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('apk_title'))).data,
        '1 selected',
      );

      await tester.tap(find.byKey(const Key('apk_cancel_selection')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('apk_title'))).data,
        'APK Cleaner',
      );
    });

    testWidgets('the clear button empties the selection', (
      WidgetTester tester,
    ) async {
      await _pumpApkCleaner(tester);

      await tester.tap(find.byKey(const Key('apk_select_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('apk_selection_bar')), findsNothing);
    });

    testWidgets('delete is enabled once something is selected', (
      WidgetTester tester,
    ) async {
      await _pumpApkCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();

      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(const Key('apk_selection_delete')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows a reassuring empty state', (WidgetTester tester) async {
      await _pumpApkCleaner(
        tester,
        files: <ScannedFile>[
          _file(
            id: '1',
            name: 'photo.jpg',
            sizeBytes: _mib,
            category: FileCategory.images,
            mimeType: 'image/jpeg',
          ),
        ],
      );

      expect(find.byKey(const Key('apk_empty')), findsOneWidget);
      expect(find.text('No installer files found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
