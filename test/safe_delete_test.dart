import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/apk_summary.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/apk_cleaner_screen.dart';
import 'package:mobile_cleaner/features/storage/data/storage_repository.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';

const int _mib = 1024 * 1024;

ScannedFile _file({
  required String id,
  required String name,
  required int sizeBytes,
  FileCategory category = FileCategory.apks,
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/Download/$name',
    uri: 'content://media/external/${category.key}/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: DateTime(2026, 4, 10),
    mimeType: 'application/vnd.android.package-archive',
  );
}

List<ScannedFile> _fixture() => <ScannedFile>[
  _file(id: '1', name: 'big.apk', sizeBytes: 60 * _mib),
  _file(id: '2', name: 'medium.apk', sizeBytes: 30 * _mib),
  _file(id: '3', name: 'small.apk', sizeBytes: 10 * _mib),
];

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);

  List<ScannedFile> files;
  int scanCount = 0;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    scanCount++;
    return FileScanResult.fromFiles(files, categories: request.categories);
  }
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

/// The completion screen reads free space, which needs a platform channel
/// that does not exist in tests.
class _FakeStorage implements StorageRepository {
  const _FakeStorage([this.freeBytes = 20 * 1024 * 1024 * 1024]);

  final int freeBytes;

  @override
  Future<StorageInfo> getStorageInfo() async =>
      StorageInfo(totalBytes: 64 * 1024 * 1024 * 1024, freeBytes: freeBytes);
}

/// Storage that cannot be read, to prove the screen degrades gracefully.
class _FailingStorage implements StorageRepository {
  const _FailingStorage();

  @override
  Future<StorageInfo> getStorageInfo() async =>
      throw Exception('STORAGE_UNAVAILABLE');
}

/// Deletes only the first file, leaving the rest as failures.
class _PartialDelete implements DeleteRepository {
  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async {
    return DeleteResult(
      deletedFiles: files.take(1).toList(),
      failures: <DeleteFailure>[
        for (final ScannedFile f in files.skip(1))
          DeleteFailure(uri: f.uri, reason: 'Access was denied.'),
      ],
    );
  }
}

/// Configurable fake so each outcome can be exercised.
class _FakeDelete implements DeleteRepository {
  _FakeDelete({this.cancelled = false, this.failEvery = false});

  final bool cancelled;
  final bool failEvery;
  final List<List<ScannedFile>> requests = <List<ScannedFile>>[];

  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async {
    requests.add(files);
    if (cancelled) {
      return const DeleteResult.cancelled();
    }
    if (failEvery) {
      return DeleteResult(
        deletedFiles: const <ScannedFile>[],
        failures: <DeleteFailure>[
          for (final ScannedFile f in files)
            DeleteFailure(uri: f.uri, reason: 'Access was denied.'),
        ],
      );
    }
    return DeleteResult(deletedFiles: files, failures: const <DeleteFailure>[]);
  }
}

Future<_StubScanner> _pump(
  WidgetTester tester,
  DeleteRepository deleter, {
  List<ScannedFile>? files,
  StorageRepository storage = const _FakeStorage(),
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubScanner scanner = _StubScanner(files ?? _fixture());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(scanner),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
        deleteRepositoryProvider.overrideWithValue(deleter),
        storageRepositoryProvider.overrideWithValue(storage),
      ],
      child: const MaterialApp(home: ApkCleanerScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return scanner;
}

void main() {
  group('DeleteResult', () {
    final ScannedFile a = _file(id: '1', name: 'a.apk', sizeBytes: 10 * _mib);
    final ScannedFile b = _file(id: '2', name: 'b.apk', sizeBytes: 5 * _mib);

    test('reports a complete success', () {
      final DeleteResult result = DeleteResult(
        deletedFiles: <ScannedFile>[a, b],
        failures: const <DeleteFailure>[],
      );

      expect(result.isCompleteSuccess, isTrue);
      expect(result.isPartialSuccess, isFalse);
      expect(result.isFailure, isFalse);
      expect(result.deletedCount, 2);
      expect(result.freedBytes, 15 * _mib);
    });

    test('reports a partial success', () {
      final DeleteResult result = DeleteResult(
        deletedFiles: <ScannedFile>[a],
        failures: <DeleteFailure>[DeleteFailure(uri: b.uri, reason: 'Denied')],
      );

      expect(result.isCompleteSuccess, isFalse);
      expect(result.isPartialSuccess, isTrue);
      // Freed space counts only what really went.
      expect(result.freedBytes, 10 * _mib);
      expect(result.failureCount, 1);
    });

    test('a cancelled delete frees nothing', () {
      const DeleteResult result = DeleteResult.cancelled();

      expect(result.userCancelled, isTrue);
      expect(result.deletedCount, 0);
      expect(result.freedBytes, 0);
      expect(result.isFailure, isTrue);
      expect(result.isCompleteSuccess, isFalse);
    });

    test('an empty delete is not a success', () {
      const DeleteResult result = DeleteResult(
        deletedFiles: <ScannedFile>[],
        failures: <DeleteFailure>[],
      );
      expect(result.isCompleteSuccess, isFalse);
      expect(result.isFailure, isTrue);
    });
  });

  group('PlatformDeleteRepository.parseResult', () {
    final List<ScannedFile> requested = _fixture();

    test('maps deleted uris back to their files', () {
      final DeleteResult result = PlatformDeleteRepository.parseResult(
        <Object?, Object?>{
          'deletedUris': <Object?>[requested[0].uri, requested[1].uri],
          'failed': <Object?>[],
          'userCancelled': false,
        },
        requested,
      );

      expect(result.deletedCount, 2);
      expect(result.freedBytes, 90 * _mib);
      expect(result.failureCount, 0);
    });

    test('records failures with their reason', () {
      final DeleteResult result = PlatformDeleteRepository.parseResult(
        <Object?, Object?>{
          'deletedUris': <Object?>[requested[0].uri],
          'failed': <Object?>[
            <Object?, Object?>{
              'uri': requested[1].uri,
              'reason': 'Access was denied.',
            },
          ],
        },
        requested,
      );

      expect(result.deletedCount, 1);
      expect(result.failures.single.reason, 'Access was denied.');
      expect(result.isPartialSuccess, isTrue);
    });

    test('a uri reported both deleted and failed is treated as failed', () {
      // Safer reading: never claim a file is gone when the platform is
      // ambiguous about it.
      final DeleteResult result = PlatformDeleteRepository.parseResult(
        <Object?, Object?>{
          'deletedUris': <Object?>[requested[0].uri],
          'failed': <Object?>[
            <Object?, Object?>{'uri': requested[0].uri, 'reason': 'Locked'},
          ],
        },
        requested,
      );

      expect(result.deletedCount, 0);
      expect(result.failureCount, 1);
      expect(result.freedBytes, 0);
    });

    test('propagates cancellation', () {
      final DeleteResult result = PlatformDeleteRepository.parseResult(
        <Object?, Object?>{
          'deletedUris': <Object?>[],
          'failed': <Object?>[],
          'userCancelled': true,
        },
        requested,
      );

      expect(result.userCancelled, isTrue);
      expect(result.deletedCount, 0);
    });

    test('ignores malformed rows and unknown uris', () {
      final DeleteResult result = PlatformDeleteRepository.parseResult(
        <Object?, Object?>{
          'deletedUris': <Object?>['content://not-requested', '', 42],
          'failed': <Object?>[
            'not-a-map',
            <Object?, Object?>{'reason': 'x'},
          ],
        },
        requested,
      );

      expect(result.deletedCount, 0);
      expect(result.failureCount, 0);
    });

    test('defaults a missing failure reason', () {
      final DeleteResult result = PlatformDeleteRepository.parseResult(
        <Object?, Object?>{
          'failed': <Object?>[
            <Object?, Object?>{'uri': requested[0].uri},
          ],
        },
        requested,
      );

      expect(result.failures.single.reason, 'Could not delete this file.');
    });
  });

  group('PlatformDeleteRepository channel', () {
    const MethodChannel channel = MethodChannel('delete-test');
    final List<MethodCall> calls = <MethodCall>[];

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      calls.clear();
    });

    void mock(Object? Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            return handler(call);
          });
    }

    test('an empty selection never reaches the platform', () async {
      mock((MethodCall call) => <Object?, Object?>{});
      final PlatformDeleteRepository repository = PlatformDeleteRepository(
        channel: channel,
      );

      final DeleteResult result = await repository.deleteFiles(<ScannedFile>[]);

      expect(calls, isEmpty);
      expect(result.deletedCount, 0);
    });

    test('sends every selected uri', () async {
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[],
          'failed': <Object?>[],
        },
      );
      final PlatformDeleteRepository repository = PlatformDeleteRepository(
        channel: channel,
      );

      await repository.deleteFiles(_fixture());

      final Map<Object?, Object?> args =
          calls.single.arguments as Map<Object?, Object?>;
      expect(calls.single.method, 'deleteFiles');
      expect((args['uris']! as List<Object?>), hasLength(3));
    });

    test(
      'a platform error fails every file rather than claiming success',
      () async {
        mock(
          (MethodCall call) => throw PlatformException(code: 'DELETE_FAILED'),
        );
        final PlatformDeleteRepository repository = PlatformDeleteRepository(
          channel: channel,
        );

        final DeleteResult result = await repository.deleteFiles(_fixture());

        expect(result.deletedCount, 0);
        expect(result.failureCount, 3);
        expect(result.freedBytes, 0);
      },
    );

    test('a missing plugin fails safely', () async {
      mock((MethodCall call) => throw MissingPluginException());
      final PlatformDeleteRepository repository = PlatformDeleteRepository(
        channel: channel,
      );

      final DeleteResult result = await repository.deleteFiles(_fixture());

      expect(result.deletedCount, 0);
      expect(result.failureCount, 3);
    });
  });

  group('Cleanup flow', () {
    testWidgets('Select -> Review shows the count and size', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _FakeDelete());

      await tester.tap(find.byKey(const Key('apk_select_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete_review_title')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('delete_review_summary')))
            .data,
        'Selected items can be safely removed from your device.',
      );
      expect(find.text('Clean Now (100.0 MB)'), findsOneWidget);
      expect(find.byKey(const Key('cleanup_breakdown_apks')), findsOneWidget);
      expect(find.text('APK Installers'), findsOneWidget);
      expect(find.textContaining('cannot be restored'), findsOneWidget);
    });

    testWidgets('Cancel deletes nothing', (WidgetTester tester) async {
      final _FakeDelete deleter = _FakeDelete();
      await _pump(tester, deleter);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_cancel')));
      await tester.pumpAndSettle();

      // Never reached the repository, and the selection survives.
      expect(deleter.requests, isEmpty);
      expect(find.byKey(const Key('apk_selection_bar')), findsOneWidget);
    });

    testWidgets('Confirm deletes and reports what was freed', (
      WidgetTester tester,
    ) async {
      final _FakeDelete deleter = _FakeDelete();
      await _pump(tester, deleter);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));

      // The reference-style live screen is a real stage, not a flash frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('delete_progress')), findsOneWidget);
      expect(find.byKey(const Key('cleanup_progress_bar')), findsOneWidget);
      expect(find.text('Cleaning...'), findsWidgets);

      await tester.pumpAndSettle();

      expect(deleter.requests.single, hasLength(1));
      expect(find.byKey(const Key('cleanup_complete_screen')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('cleanup_title'))).data,
        'Cleaned Successfully!',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cleanup_storage_recovered')))
            .data,
        '60.0 MB',
      );
    });

    testWidgets('the selection clears after a successful delete', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _FakeDelete());

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cleanup_done')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('apk_selection_bar')), findsNothing);
    });

    testWidgets('declining the system dialog reports nothing deleted', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _FakeDelete(cancelled: true));

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('delete_result_title'))).data,
        'Nothing cleaned',
      );
      expect(find.byKey(const Key('delete_result_freed')), findsNothing);
    });

    testWidgets('a blocked delete is reported as a failure', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _FakeDelete(failEvery: true));

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('delete_result_title'))).data,
        'Could not clean',
      );
      expect(find.byKey(const Key('delete_result_failed')), findsOneWidget);
      expect(find.text('Access was denied.'), findsOneWidget);
    });

    testWidgets('a large selection is grouped into one real breakdown row', (
      WidgetTester tester,
    ) async {
      final List<ScannedFile> many = <ScannedFile>[
        for (int i = 0; i < 12; i++)
          _file(id: '$i', name: 'pkg$i.apk', sizeBytes: _mib),
      ];
      await _pump(tester, _FakeDelete(), files: many);

      await tester.tap(find.byKey(const Key('apk_select_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cleanup_breakdown_apks')), findsOneWidget);
      expect(find.text('12 items'), findsOneWidget);
    });

    testWidgets('deleting rescans so the list reflects the device', (
      WidgetTester tester,
    ) async {
      final _StubScanner scanner = await _pump(tester, _FakeDelete());
      expect(scanner.scanCount, 1);

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();

      // Drop the deleted file from what the next scan will return.
      scanner.files = scanner.files
          .where((ScannedFile f) => f.id != '1')
          .toList();

      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cleanup_done')));
      await tester.pumpAndSettle();

      expect(scanner.scanCount, greaterThan(1));
      expect(find.text('big.apk'), findsNothing);
      expect(find.text('medium.apk'), findsOneWidget);
    });
  });

  group('Selection primitives back the flow', () {
    test('select all, deselect all, and running size', () {
      final List<ScannedFile> files = _fixture();
      FileSelection selection = const FileSelection.empty();

      selection = selection.selectAll(files);
      expect(selection.count, 3);
      expect(selection.totalBytes, 100 * _mib);
      expect(selection.containsAll(files), isTrue);

      selection = selection.deselectAll(files);
      expect(selection.isEmpty, isTrue);
      expect(selection.totalBytes, 0);
    });

    test('deleted files are dropped from the selection', () {
      final List<ScannedFile> files = _fixture();
      final FileSelection selection = const FileSelection.empty()
          .selectAll(files)
          .deselectAll(<ScannedFile>[files.first]);

      expect(selection.count, 2);
      expect(selection.totalBytes, 40 * _mib);
    });
  });

  group('ApkSummary stays consistent after deletion', () {
    test('removing files shrinks the total', () {
      final ApkSummary before = ApkSummary.from(_fixture());
      expect(before.totalBytes, 100 * _mib);

      final ApkSummary after = ApkSummary.from(
        _fixture().where((ScannedFile f) => f.id != '1'),
      );
      expect(after.totalBytes, 40 * _mib);
      expect(after.fileCount, 2);
    });
  });

  group('Cleanup Complete screen', () {
    testWidgets('reports items removed, space freed, and elapsed time', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _FakeDelete(),
        // 25 GB free after the cleanup.
        storage: const _FakeStorage(25 * 1024 * 1024 * 1024),
      );

      await tester.tap(find.byKey(const Key('apk_select_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cleanup_complete_screen')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('cleanup_title'))).data,
        'Cleaned Successfully!',
      );
      // Files deleted.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cleanup_files_deleted')))
            .data,
        '3 items',
      );
      // Storage recovered: 60 + 30 + 10 MB.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cleanup_storage_recovered')))
            .data,
        '100.0 MB',
      );
      expect(find.byKey(const Key('cleanup_time_saved')), findsOneWidget);
      expect(find.byKey(const Key('cleanup_share')), findsOneWidget);
      expect(find.byKey(const Key('cleanup_particles')), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the singular form for one file', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _FakeDelete());

      await tester.tap(find.byKey(const Key('file_checkbox_3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('cleanup_files_deleted')))
            .data,
        '1 item',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cleanup_storage_recovered')))
            .data,
        '10.0 MB',
      );
    });

    testWidgets('completion does not depend on another storage read', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _FakeDelete(), storage: const _FailingStorage());

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();

      // The cleanup still reports what it knows.
      expect(find.byKey(const Key('cleanup_complete_screen')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cleanup_storage_recovered')))
            .data,
        '60.0 MB',
      );
      expect(find.byKey(const Key('cleanup_complete_screen')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a partial delete is flagged on the screen', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _PartialDelete());

      await tester.tap(find.byKey(const Key('apk_select_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cleanup_complete_screen')), findsOneWidget);
      expect(find.byKey(const Key('cleanup_partial_notice')), findsOneWidget);
      // Only the file that really went is counted.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cleanup_files_deleted')))
            .data,
        '1 item',
      );
      expect(find.textContaining('could not'), findsOneWidget);
    });

    testWidgets('cancelling never reaches the completion screen', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _FakeDelete(cancelled: true));

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cleanup_complete_screen')), findsNothing);
      expect(find.byKey(const Key('delete_result_dialog')), findsOneWidget);
    });

    testWidgets('Done returns to the cleaner', (WidgetTester tester) async {
      await _pump(tester, _FakeDelete());

      await tester.tap(find.byKey(const Key('file_checkbox_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apk_selection_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cleanup_done')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cleanup_complete_screen')), findsNothing);
      expect(find.byKey(const Key('apk_list')), findsOneWidget);
    });
  });
}
