import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/download_age_filter.dart';
import 'package:mobile_cleaner/features/files/domain/downloads_summary.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/downloads_cleaner_screen.dart';

const int _mib = 1024 * 1024;

/// Fixed clock for the pure domain tests.
final DateTime _now = DateTime(2026, 8, 15, 12);

/// Midday today, so a daylight-saving shift can never move a fixture across
/// a day boundary and change its computed age.
DateTime _middayToday() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 12);
}

ScannedFile _download({
  required String id,
  required String name,
  required int daysOld,
  int sizeBytes = 10 * _mib,
  FileCategory category = FileCategory.downloads,
  String? uri,
  DateTime? base,
}) {
  final DateTime reference = base ?? _middayToday();
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/Download/$name',
    uri: uri ?? 'content://media/external/downloads/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: reference.subtract(Duration(days: daysOld)),
  );
}

/// One download either side of every threshold.
///
/// Widget tests leave [base] null so ages are relative to the real clock,
/// which is what the provider uses. Domain tests pin both to [_now].
List<ScannedFile> _fixture({DateTime? base}) => <ScannedFile>[
  _download(id: '1', name: 'fresh.pdf', daysOld: 3, sizeBytes: 5 * _mib, base: base),
  _download(id: '2', name: 'month-old.zip', daysOld: 45, sizeBytes: 20 * _mib, base: base),
  _download(id: '3', name: 'quarter.apk', daysOld: 120, sizeBytes: 30 * _mib, base: base),
  _download(id: '4', name: 'half-year.mp4', daysOld: 200, sizeBytes: 40 * _mib, base: base),
  _download(id: '5', name: 'ancient.iso', daysOld: 400, sizeBytes: 50 * _mib, base: base),
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

Future<_StubRepository> _pumpCleaner(
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
      child: const MaterialApp(home: DownloadsCleanerScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

/// Scrolls a chip into view inside the horizontal filter bar.
Future<void> _scrollToAgeChip(
  WidgetTester tester,
  DownloadAgeFilter filter,
) async {
  await tester.scrollUntilVisible(
    find.byKey(Key('age_filter_${filter.name}')),
    120,
    scrollable: find.descendant(
      of: find.byKey(const Key('downloads_filter_bar')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapAgeChip(WidgetTester tester, DownloadAgeFilter filter) async {
  await _scrollToAgeChip(tester, filter);
  await tester.tap(find.byKey(Key('age_filter_${filter.name}')));
  await tester.pumpAndSettle();
}

void main() {
  group('DownloadAgeFilter', () {
    test('offers exactly the four required thresholds', () {
      expect(DownloadAgeFilter.values, <DownloadAgeFilter>[
        DownloadAgeFilter.days30,
        DownloadAgeFilter.days90,
        DownloadAgeFilter.months6,
        DownloadAgeFilter.year1,
      ]);
      expect(
        DownloadAgeFilter.values.map((DownloadAgeFilter f) => f.label).toList(),
        <String>['30+ days', '90+ days', '6+ months', '1+ year'],
      );
    });

    test('uses correct day bounds', () {
      expect(DownloadAgeFilter.days30.minDays, 30);
      expect(DownloadAgeFilter.days90.minDays, 90);
      expect(DownloadAgeFilter.months6.minDays, 182);
      expect(DownloadAgeFilter.year1.minDays, 365);
      expect(DownloadAgeFilter.lowestBoundDays, 30);
      expect(DownloadAgeFilter.defaultFilter, DownloadAgeFilter.days30);
    });

    test('matches on an inclusive bound', () {
      final DateTime exactly30 = _now.subtract(const Duration(days: 30));
      final DateTime justUnder = _now.subtract(const Duration(days: 29));

      expect(DownloadAgeFilter.days30.matches(exactly30, now: _now), isTrue);
      expect(DownloadAgeFilter.days30.matches(justUnder, now: _now), isFalse);
    });

    test('ignores clock time within a day', () {
      final DateTime lateThatDay = DateTime(2026, 7, 16, 23, 59);
      // 30 days before 2026-08-15 is 2026-07-16.
      expect(
        DownloadAgeFilter.days30.matches(lateThatDay, now: _now),
        isTrue,
      );
    });

    test('never treats a future date as old', () {
      final DateTime future = _now.add(const Duration(days: 5));
      expect(DownloadAgeFilter.ageInDays(future, now: _now), 0);
      expect(DownloadAgeFilter.days30.matches(future, now: _now), isFalse);
    });

    test('excludes files with an unknown timestamp', () {
      final DateTime unknown = DateTime.fromMillisecondsSinceEpoch(0);
      for (final DownloadAgeFilter filter in DownloadAgeFilter.values) {
        expect(
          filter.matches(unknown, now: _now),
          isFalse,
          reason: '${filter.label} must not match an unknown date',
        );
      }
    });
  });

  group('DownloadsSummary', () {
    test('filters and totals at each threshold', () {
      final List<ScannedFile> files = _fixture(base: _now);

      DownloadsSummary summaryFor(DownloadAgeFilter filter) =>
          DownloadsSummary.from(files, filter, now: _now);

      final DownloadsSummary d30 = summaryFor(DownloadAgeFilter.days30);
      expect(d30.fileCount, 4);
      expect(d30.totalBytes, (20 + 30 + 40 + 50) * _mib);

      final DownloadsSummary d90 = summaryFor(DownloadAgeFilter.days90);
      expect(d90.fileCount, 3);
      expect(d90.totalBytes, (30 + 40 + 50) * _mib);

      final DownloadsSummary m6 = summaryFor(DownloadAgeFilter.months6);
      expect(m6.fileCount, 2);
      expect(m6.totalBytes, (40 + 50) * _mib);

      final DownloadsSummary y1 = summaryFor(DownloadAgeFilter.year1);
      expect(y1.fileCount, 1);
      expect(y1.totalBytes, 50 * _mib);
      expect(y1.oldestFile?.name, 'ancient.iso');
    });

    test('sorts oldest first', () {
      final DownloadsSummary summary = DownloadsSummary.from(
        _fixture(base: _now),
        DownloadAgeFilter.days30,
        now: _now,
      );
      expect(
        summary.files.map((ScannedFile f) => f.name).toList(),
        <String>['ancient.iso', 'half-year.mp4', 'quarter.apk', 'month-old.zip'],
      );
    });

    test('counts a file shared by two categories only once', () {
      const String sharedUri = 'content://media/external/file/media/77';
      final DownloadsSummary summary = DownloadsSummary.from(<ScannedFile>[
        _download(id: '77', name: 'tool.apk', daysOld: 100, uri: sharedUri, base: _now),
        _download(
          id: '77',
          name: 'tool.apk',
          daysOld: 100,
          uri: sharedUri,
          category: FileCategory.apks,
          base: _now,
        ),
      ], DownloadAgeFilter.days90, now: _now);

      expect(summary.fileCount, 1);
      expect(summary.totalBytes, 10 * _mib);
    });

    test('reports the largest matching download', () {
      final DownloadsSummary summary = DownloadsSummary.from(
        _fixture(base: _now),
        DownloadAgeFilter.days30,
        now: _now,
      );
      expect(summary.largestFile?.name, 'ancient.iso');
    });

    test('is empty when nothing is old enough', () {
      final DownloadsSummary summary = DownloadsSummary.from(<ScannedFile>[
        _download(id: '1', name: 'today.pdf', daysOld: 0, base: _now),
      ], DownloadAgeFilter.days30, now: _now);

      expect(summary.isEmpty, isTrue);
      expect(summary.totalBytes, 0);
      expect(summary.oldestFile, isNull);
      expect(summary.largestFile, isNull);
    });
  });

  group('FileSelection', () {
    final ScannedFile a = _download(id: 'a', name: 'a.zip', daysOld: 40, base: _now);
    final ScannedFile b = _download(id: 'b', name: 'b.zip', daysOld: 50, base: _now);
    final ScannedFile c = _download(id: 'c', name: 'c.zip', daysOld: 60, base: _now);

    test('starts empty', () {
      const FileSelection selection = FileSelection.empty();
      expect(selection.isEmpty, isTrue);
      expect(selection.count, 0);
      expect(selection.totalBytes, 0);
    });

    test('toggles a file on and off', () {
      FileSelection selection = const FileSelection.empty().toggle(a);
      expect(selection.contains(a), isTrue);
      expect(selection.count, 1);

      selection = selection.toggle(a);
      expect(selection.contains(a), isFalse);
      expect(selection.isEmpty, isTrue);
    });

    test('totals the size of every selected file', () {
      final FileSelection selection = const FileSelection.empty()
          .toggle(a)
          .toggle(b);
      expect(selection.count, 2);
      expect(selection.totalBytes, 20 * _mib);
    });

    test('select all and deselect all', () {
      final List<ScannedFile> all = <ScannedFile>[a, b, c];
      final FileSelection selected = const FileSelection.empty().selectAll(all);
      expect(selected.count, 3);
      expect(selected.containsAll(all), isTrue);

      final FileSelection cleared = selected.deselectAll(all);
      expect(cleared.isEmpty, isTrue);
    });

    test('containsAll is false for an empty list', () {
      expect(
        const FileSelection.empty().containsAll(<ScannedFile>[]),
        isFalse,
      );
    });

    test('is keyed by URI, so a rebuilt instance stays selected', () {
      final FileSelection selection = const FileSelection.empty().toggle(a);
      final ScannedFile rebuilt = _download(
        id: 'a',
        name: 'a.zip',
        daysOld: 41,
        base: _now,
      );
      expect(selection.contains(rebuilt), isTrue);
    });

    test('retainWhereVisible drops files outside the new list', () {
      final FileSelection selection = const FileSelection.empty()
          .selectAll(<ScannedFile>[a, b, c]);
      final FileSelection pruned = selection.retainWhereVisible(
        <ScannedFile>[a, c],
      );

      expect(pruned.count, 2);
      expect(pruned.contains(b), isFalse);
      expect(pruned.totalBytes, 20 * _mib);
    });

    test('clear removes everything', () {
      final FileSelection selection = const FileSelection.empty()
          .selectAll(<ScannedFile>[a, b])
          .clear();
      expect(selection.isEmpty, isTrue);
    });
  });

  group('Downloads cleaner screen', () {
    testWidgets('shows the four age chips, defaulting to 30+ days', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      // The bar scrolls horizontally, so later chips need scrolling in.
      for (final DownloadAgeFilter option in DownloadAgeFilter.values) {
        final Finder chip = find.byKey(Key('age_filter_${option.name}'));
        await _scrollToAgeChip(tester, option);
        expect(
          chip,
          findsOneWidget,
          reason: '${option.label} chip should be visible',
        );
      }
      expect(find.byKey(const Key('downloads_total_card')), findsOneWidget);
    });

    testWidgets('scans only the Downloads category', (
      WidgetTester tester,
    ) async {
      final _StubRepository repository = await _pumpCleaner(tester);

      expect(repository.lastRequest?.categories, <FileCategory>[
        FileCategory.downloads,
      ]);
    });

    testWidgets('lists stale downloads and hides recent ones', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      expect(find.text('ancient.iso'), findsOneWidget);
      expect(find.text('month-old.zip'), findsOneWidget);
      // Three days old, so below the 30 day threshold.
      expect(find.text('fresh.pdf'), findsNothing);
    });

    testWidgets('narrowing the threshold shrinks the list', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);
      expect(find.text('month-old.zip'), findsOneWidget);

      await _tapAgeChip(tester, DownloadAgeFilter.year1);

      expect(find.text('ancient.iso'), findsOneWidget);
      expect(find.text('month-old.zip'), findsNothing);
      expect(find.text('quarter.apk'), findsNothing);
    });

    testWidgets('changing a filter does not trigger another scan', (
      WidgetTester tester,
    ) async {
      final _StubRepository repository = await _pumpCleaner(tester);
      expect(repository.scanCount, 1);

      await _tapAgeChip(tester, DownloadAgeFilter.days90);
      await _tapAgeChip(tester, DownloadAgeFilter.months6);

      expect(repository.scanCount, 1);
    });

    testWidgets('selecting a row reveals the selection bar', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);
      expect(find.byKey(const Key('downloads_selection_bar')), findsNothing);

      await tester.tap(find.byKey(const Key('file_checkbox_5')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('downloads_selection_bar')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('selection_count'))).data,
        '1 selected',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('selection_bytes'))).data,
        '50.0 MB',
      );
    });

    testWidgets('selecting several rows totals their size', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('file_checkbox_4')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('selection_count'))).data,
        '2 selected',
      );
      // 50 MB + 40 MB
      expect(
        tester.widget<Text>(find.byKey(const Key('selection_bytes'))).data,
        '90.0 MB',
      );
    });

    testWidgets('tapping a selected row deselects it', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_5')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('downloads_selection_bar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('file_checkbox_5')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('downloads_selection_bar')), findsNothing);
    });

    testWidgets('select all selects every visible row, then clears', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('downloads_select_all')));
      await tester.pumpAndSettle();

      // Four downloads are older than 30 days.
      expect(
        tester.widget<Text>(find.byKey(const Key('selection_count'))).data,
        '4 selected',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('selection_bytes'))).data,
        '140.0 MB',
      );

      await tester.tap(find.byKey(const Key('downloads_select_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('downloads_selection_bar')), findsNothing);
    });

    testWidgets('the clear button empties the selection', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('downloads_select_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('selection_clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('downloads_selection_bar')), findsNothing);
    });

    testWidgets('the app bar reflects the selection count', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_5')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('downloads_title'))).data,
        '1 selected',
      );

      await tester.tap(find.byKey(const Key('downloads_cancel_selection')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('downloads_title'))).data,
        'Downloads Cleaner',
      );
    });

    testWidgets('narrowing the filter drops now-hidden selections', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      // Select every download older than 30 days.
      await tester.tap(find.byKey(const Key('downloads_select_all')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('selection_count'))).data,
        '4 selected',
      );

      // Only the 400 day old file survives this threshold.
      await _tapAgeChip(tester, DownloadAgeFilter.year1);

      expect(
        tester.widget<Text>(find.byKey(const Key('selection_count'))).data,
        '1 selected',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('selection_bytes'))).data,
        '50.0 MB',
      );
    });

    testWidgets('delete is enabled once something is selected', (
      WidgetTester tester,
    ) async {
      await _pumpCleaner(tester);

      await tester.tap(find.byKey(const Key('file_checkbox_5')));
      await tester.pumpAndSettle();

      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(const Key('selection_delete')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows a reassuring empty state', (WidgetTester tester) async {
      await _pumpCleaner(
        tester,
        files: <ScannedFile>[
          _download(id: '1', name: 'today.pdf', daysOld: 1),
        ],
      );

      expect(find.byKey(const Key('downloads_empty')), findsOneWidget);
      expect(find.text('No downloads older than 30 days'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
