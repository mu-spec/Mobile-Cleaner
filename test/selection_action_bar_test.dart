import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/apk_cleaner_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/category_files_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/downloads_cleaner_screen.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/screenshot_cleaner_screen.dart';
import 'package:mobile_cleaner/features/storage/data/storage_repository.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';

const int _mib = 1024 * 1024;

DateTime _daysAgo(int days) {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 12)
      .subtract(Duration(days: days));
}

ScannedFile _file({
  required String id,
  required String name,
  required FileCategory category,
  int sizeBytes = 30 * _mib,
  int daysOld = 200,
  String relativePath = 'Download/',
  String? mimeType,
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/$relativePath$name',
    uri: 'content://media/external/${category.key}/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: _daysAgo(daysOld),
    mimeType: mimeType,
    relativePath: relativePath,
  );
}

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);

  final List<ScannedFile> files;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => FileScanResult.fromFiles(
    files.where((ScannedFile f) => request.categories.contains(f.category))
        .toList(),
    categories: request.categories,
  );
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

class _FakeStorage implements StorageRepository {
  const _FakeStorage();

  @override
  Future<StorageInfo> getStorageInfo() async => const StorageInfo(
    totalBytes: 64 * 1024 * 1024 * 1024,
    freeBytes: 20 * 1024 * 1024 * 1024,
  );
}

class _RecordingDelete implements DeleteRepository {
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

/// One screen under test, with the keys its selection bar uses.
class _Case {
  const _Case({
    required this.name,
    required this.screen,
    required this.files,
    required this.barKey,
    required this.countKey,
    required this.bytesKey,
    required this.deleteKey,
    required this.selectAllKey,
  });

  final String name;
  final Widget screen;
  final List<ScannedFile> files;
  final String barKey;
  final String countKey;
  final String bytesKey;
  final String deleteKey;
  final String selectAllKey;
}

final List<_Case> _cases = <_Case>[
  _Case(
    name: 'Downloads Cleaner',
    screen: const DownloadsCleanerScreen(),
    files: <ScannedFile>[
      _file(id: '1', name: 'old.zip', category: FileCategory.downloads),
      _file(
        id: '2',
        name: 'older.pdf',
        category: FileCategory.downloads,
        sizeBytes: 20 * _mib,
      ),
    ],
    barKey: 'downloads_selection_bar',
    countKey: 'selection_count',
    bytesKey: 'selection_bytes',
    deleteKey: 'selection_delete',
    selectAllKey: 'downloads_select_all',
  ),
  _Case(
    name: 'APK Cleaner',
    screen: const ApkCleanerScreen(),
    files: <ScannedFile>[
      _file(
        id: '1',
        name: 'game.apk',
        category: FileCategory.apks,
        mimeType: 'application/vnd.android.package-archive',
      ),
      _file(
        id: '2',
        name: 'tool.apk',
        category: FileCategory.apks,
        sizeBytes: 20 * _mib,
        mimeType: 'application/vnd.android.package-archive',
      ),
    ],
    barKey: 'apk_selection_bar',
    countKey: 'apk_selection_count',
    bytesKey: 'apk_selection_bytes',
    deleteKey: 'apk_selection_delete',
    selectAllKey: 'apk_select_all',
  ),
  _Case(
    name: 'Images browser',
    screen: const CategoryFilesScreen(category: FileCategory.images),
    files: <ScannedFile>[
      _file(
        id: '1',
        name: 'a.jpg',
        category: FileCategory.images,
        relativePath: 'DCIM/Camera/',
        mimeType: 'image/jpeg',
      ),
      _file(
        id: '2',
        name: 'b.jpg',
        category: FileCategory.images,
        sizeBytes: 20 * _mib,
        relativePath: 'DCIM/Camera/',
        mimeType: 'image/jpeg',
      ),
    ],
    barKey: 'category_selection_bar',
    countKey: 'category_selection_count',
    bytesKey: 'category_selection_bytes',
    deleteKey: 'category_selection_delete',
    selectAllKey: 'category_select_all',
  ),
  _Case(
    name: 'Screenshot Cleaner',
    screen: const ScreenshotCleanerScreen(),
    files: <ScannedFile>[
      _file(
        id: '1',
        name: 'Screenshot_1.png',
        category: FileCategory.images,
        relativePath: 'Pictures/Screenshots/',
        mimeType: 'image/png',
      ),
      _file(
        id: '2',
        name: 'Screenshot_2.png',
        category: FileCategory.images,
        sizeBytes: 20 * _mib,
        relativePath: 'Pictures/Screenshots/',
        mimeType: 'image/png',
      ),
    ],
    barKey: 'screenshot_selection_bar',
    countKey: 'screenshot_selection_count',
    bytesKey: 'screenshot_selection_bytes',
    deleteKey: 'screenshot_selection_delete',
    selectAllKey: 'screenshot_select_all',
  ),
];

/// Builds the fixture for one case, optionally long or undeletable.
List<ScannedFile> _filesFor(_Case testCase, bool undeletable, bool manyFiles) {
  List<ScannedFile> files = testCase.files;
  if (manyFiles) {
    final ScannedFile template = files.first;
    files = <ScannedFile>[
      for (int i = 1; i <= 40; i++)
        template.copyWith(
          id: '$i',
          name: '$i-${template.name}',
          uri: 'content://media/external/f/media/$i',
        ),
    ];
  }
  if (undeletable) {
    files = files
        .map((ScannedFile f) => f.copyWith(uri: 'file://${f.path}'))
        .toList();
  }
  return files;
}

Future<_RecordingDelete> _pump(
  WidgetTester tester,
  _Case testCase, {
  Size size = const Size(420, 900),
  bool undeletable = false,
  bool manyFiles = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _RecordingDelete deleter = _RecordingDelete();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(
          _StubScanner(_filesFor(testCase, undeletable, manyFiles)),
        ),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
        storageRepositoryProvider.overrideWithValue(const _FakeStorage()),
        deleteRepositoryProvider.overrideWithValue(deleter),
      ],
      child: MaterialApp(home: testCase.screen),
    ),
  );
  await tester.pumpAndSettle();
  return deleter;
}

/// Taps the first row's checkbox, scrolling it into view first.
Future<void> _selectFirst(WidgetTester tester) async {
  final Finder checkbox = find.byKey(const Key('file_checkbox_1'));
  await tester.scrollUntilVisible(checkbox, 150);
  await tester.pumpAndSettle();
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
}

void main() {
  for (final _Case testCase in _cases) {
    group(testCase.name, () {
      testWidgets('no action bar until something is selected', (
        WidgetTester tester,
      ) async {
        await _pump(tester, testCase);
        expect(find.byKey(Key(testCase.barKey)), findsNothing);
      });

      testWidgets('selecting one item reveals a visible Delete action', (
        WidgetTester tester,
      ) async {
        await _pump(tester, testCase);

        await _selectFirst(tester);

        final Finder deleteButton = find.byKey(Key(testCase.deleteKey));
        expect(find.byKey(Key(testCase.barKey)), findsOneWidget);
        expect(deleteButton, findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(deleteButton).onPressed,
          isNotNull,
          reason: 'Delete must be tappable once something is selected',
        );

        // The regression: the button must actually be on screen.
        final Rect rect = tester.getRect(deleteButton);
        final Size screen = tester.view.physicalSize /
            tester.view.devicePixelRatio;
        expect(
          rect.right <= screen.width + 0.5,
          isTrue,
          reason: 'Delete button is cut off horizontally',
        );
        expect(
          rect.bottom <= screen.height + 0.5,
          isTrue,
          reason: 'Delete button is below the visible area',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('shows the selected count and size', (
        WidgetTester tester,
      ) async {
        await _pump(tester, testCase);

        await _selectFirst(tester);
        expect(
          tester.widget<Text>(find.byKey(Key(testCase.countKey))).data,
          '1 selected',
        );
        expect(
          tester.widget<Text>(find.byKey(Key(testCase.bytesKey))).data,
          '30.0 MB',
        );

        await tester.tap(find.byKey(Key(testCase.selectAllKey)));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(Key(testCase.countKey))).data,
          '2 selected',
        );
        // 30 MB + 20 MB
        expect(
          tester.widget<Text>(find.byKey(Key(testCase.bytesKey))).data,
          '50.0 MB',
        );
      });

      testWidgets('Delete opens the Review step, not an instant delete', (
        WidgetTester tester,
      ) async {
        final _RecordingDelete deleter = await _pump(tester, testCase);

        await _selectFirst(tester);
        await tester.tap(find.byKey(Key(testCase.deleteKey)));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('delete_review_title')), findsOneWidget);
        expect(find.byKey(const Key('delete_confirm')), findsOneWidget);
        // Nothing removed until the user confirms.
        expect(deleter.requests, isEmpty);
      });

      testWidgets('Review -> Confirm reaches Cleanup Complete', (
        WidgetTester tester,
      ) async {
        final _RecordingDelete deleter = await _pump(tester, testCase);

        await _selectFirst(tester);
        await tester.tap(find.byKey(Key(testCase.deleteKey)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('delete_confirm')));
        await tester.pumpAndSettle();

        expect(deleter.requests.single, hasLength(1));
        expect(
          find.byKey(const Key('cleanup_complete_screen')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('cleanup_storage_recovered')))
              .data,
          '30.0 MB',
        );
      });

      testWidgets('Delete is disabled when nothing selected is deletable', (
        WidgetTester tester,
      ) async {
        await _pump(tester, testCase, undeletable: true);
        await _selectFirst(tester);

        expect(
          tester
              .widget<FilledButton>(find.byKey(Key(testCase.deleteKey)))
              .onPressed,
          isNull,
          reason: 'Android cannot delete a file:// row, so Delete must be off',
        );
      });

      testWidgets('the list still scrolls while selecting', (
        WidgetTester tester,
      ) async {
        // The reported bug: after selecting, the body stopped receiving
        // pointer events and the list could not be scrolled.
        await _pump(tester, testCase, manyFiles: true);
        await _selectFirst(tester);

        final Finder list = find.byType(Scrollable).last;
        final double before =
            tester.state<ScrollableState>(list).position.pixels;

        await tester.drag(list, const Offset(0, -300));
        await tester.pumpAndSettle();

        final double after =
            tester.state<ScrollableState>(list).position.pixels;
        expect(
          after,
          greaterThan(before),
          reason: 'list must remain scrollable while items are selected',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('more items can be selected after the bar appears', (
        WidgetTester tester,
      ) async {
        await _pump(tester, testCase);
        await _selectFirst(tester);

        final Finder second = find.byKey(const Key('file_checkbox_2'));
        await tester.scrollUntilVisible(second, 150);
        await tester.pumpAndSettle();
        await tester.tap(second);
        await tester.pumpAndSettle();

        expect(
          tester.widget<Text>(find.byKey(Key(testCase.countKey))).data,
          '2 selected',
        );
      });

      testWidgets('the bar does not overlap the list', (
        WidgetTester tester,
      ) async {
        await _pump(tester, testCase);
        await _selectFirst(tester);

        final Rect bar = tester.getRect(find.byKey(Key(testCase.barKey)));
        final Rect list = tester.getRect(find.byType(Scrollable).last);
        expect(
          list.bottom <= bar.top + 0.5,
          isTrue,
          reason: 'the list should end where the bar begins, not underneath it',
        );
      });

      testWidgets('the Delete action survives a narrow screen', (
        WidgetTester tester,
      ) async {
        // A small phone in portrait, where the old fixed Row overflowed.
        await _pump(tester, testCase, size: const Size(320, 640));

        await _selectFirst(tester);

        expect(find.byKey(Key(testCase.deleteKey)), findsOneWidget);
        // An overflowing Row throws during layout; this catches it.
        expect(tester.takeException(), isNull);
      });

      testWidgets('the Delete action survives a large system font', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(360, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final _RecordingDelete deleter = _RecordingDelete();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              fileScannerRepositoryProvider.overrideWithValue(
                _StubScanner(testCase.files),
              ),
              thumbnailRepositoryProvider.overrideWithValue(
                const _NoThumbnails(),
              ),
              storageRepositoryProvider.overrideWithValue(
                const _FakeStorage(),
              ),
              deleteRepositoryProvider.overrideWithValue(deleter),
            ],
            child: MediaQuery(
              // Accessibility font scaling is a common real-device setting.
              data: const MediaQueryData(
                textScaler: TextScaler.linear(1.5),
              ),
              child: MaterialApp(home: testCase.screen),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _selectFirst(tester);

        expect(find.byKey(Key(testCase.deleteKey)), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
