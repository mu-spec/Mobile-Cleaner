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
import 'package:mobile_cleaner/features/files/presentation/screens/screenshot_cleaner_screen.dart';

const int _mib = 1024 * 1024;

/// A realistically large screenshot library. The scanner allows 1000.
const int _libraryCount = 600;

ScannedFile _shot(int i) {
  final DateTime now = DateTime.now();
  return ScannedFile(
    id: '$i',
    name: 'Screenshot_$i.png',
    path: '/storage/emulated/0/Pictures/Screenshots/Screenshot_$i.png',
    uri: 'content://media/external/images/media/$i',
    sizeBytes: _mib,
    category: FileCategory.images,
    dateModified: DateTime(now.year, now.month, now.day, 12)
        .subtract(Duration(days: i)),
    mimeType: 'image/png',
    relativePath: 'Pictures/Screenshots/',
  );
}

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);

  final List<ScannedFile> files;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => FileScanResult.fromFiles(files, categories: request.categories);
}

/// Counts how many rows actually asked for a thumbnail.
///
/// With a lazy list this stays near the number of visible rows. With the old
/// eager `ListView(children: ...)` it was the whole library.
class _CountingThumbnails implements ThumbnailRepository {
  int requests = 0;

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async {
    requests++;
    return null;
  }
}

class _NoopDelete implements DeleteRepository {
  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async =>
      DeleteResult(deletedFiles: files, failures: const <DeleteFailure>[]);
}

Future<_CountingThumbnails> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _CountingThumbnails thumbnails = _CountingThumbnails();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(
          _StubScanner(<ScannedFile>[
            for (int i = 1; i <= _libraryCount; i++) _shot(i),
          ]),
        ),
        thumbnailRepositoryProvider.overrideWithValue(thumbnails),
        deleteRepositoryProvider.overrideWithValue(_NoopDelete()),
      ],
      child: const MaterialApp(home: ScreenshotCleanerScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return thumbnails;
}

void main() {
  group('Screenshot Cleaner stays responsive with a large library', () {
    testWidgets('only builds the rows that are on screen', (
      WidgetTester tester,
    ) async {
      await _pump(tester);

      // A lazy list realises roughly a screenful, not the whole library.
      final int built = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .length;
      expect(
        built,
        lessThan(50),
        reason:
            'built $built of $_libraryCount rows; the list is not lazy, which '
            'is what froze the UI on device',
      );
    });

    testWidgets('does not request a thumbnail for every file in the library', (
      WidgetTester tester,
    ) async {
      final _CountingThumbnails thumbnails = await _pump(tester);

      expect(
        thumbnails.requests,
        lessThan(50),
        reason:
            '${thumbnails.requests} thumbnail requests for $_libraryCount '
            'files; every off-screen row is hitting the platform channel',
      );
    });

    testWidgets('selecting stays cheap and the UI keeps responding', (
      WidgetTester tester,
    ) async {
      final _CountingThumbnails thumbnails = await _pump(tester);
      final int afterFirstBuild = thumbnails.requests;

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();

      // The header reflects the tap...
      expect(
        tester.widget<Text>(find.byKey(const Key('screenshot_title'))).data,
        '1 selected',
      );
      // ...and the rebuild did not fan out across the whole library.
      expect(
        thumbnails.requests - afterFirstBuild,
        lessThan(50),
        reason: 'selecting one item re-requested thumbnails library-wide',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the list still scrolls after selecting', (
      WidgetTester tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();

      final Finder list = find.byKey(const Key('screenshot_list'));
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      final double before = scrollable.position.pixels;

      await tester.drag(list, const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(
        scrollable.position.pixels,
        greaterThan(before),
        reason: 'the list must still scroll once an item is selected',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('more items can be selected after the first', (
      WidgetTester tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('file_checkbox_2')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('screenshot_title'))).data,
        '2 selected',
      );
      expect(
        find.byKey(const Key('screenshot_selection_bar')),
        findsOneWidget,
      );
    });
  });
}
