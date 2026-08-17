import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/core/errors/app_failure.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_channel.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/storage/data/storage_repository.dart';

ScannedFile _file(String id) => ScannedFile(
  id: id,
  name: 'file_$id.jpg',
  path: '/storage/emulated/0/DCIM/file_$id.jpg',
  uri: 'content://media/external/images/media/$id',
  sizeBytes: 1024 * 1024,
  category: FileCategory.images,
  dateModified: DateTime(2026, 3, 1),
  mimeType: 'image/jpeg',
);

/// A channel that always throws the given error.
MethodChannel _throwingChannel(String name, Object error) {
  final MethodChannel channel = MethodChannel(name);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        throw error;
      });
  return channel;
}

/// A channel with no handler at all, which raises MissingPluginException.
MethodChannel _absentChannel(String name) {
  final MethodChannel channel = MethodChannel(name);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
  return channel;
}

Future<void> _pumpError(WidgetTester tester, Object error) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FilesErrorView(
          error: error,
          onRetry: () {},
          onPermissions: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Failure classification', () {
    test('permission denied is recognised and is not retryable', () {
      final AppFailure failure = AppFailure.from(
        PlatformException(
          code: 'SCAN_PERMISSION_DENIED',
          message: 'Storage permission is required to scan files.',
        ),
      );

      expect(failure.kind, FailureKind.permissionDenied);
      expect(failure.needsPermission, isTrue);
      // Retrying without the permission would fail identically.
      expect(failure.isRetryable, isFalse);
    });

    test('missing files, delete failures and cancellation are distinct', () {
      expect(
        AppFailure.from(PlatformException(code: 'FILE_NOT_FOUND')).kind,
        FailureKind.missingFile,
      );
      expect(
        AppFailure.from(PlatformException(code: 'DELETE_FAILED')).kind,
        FailureKind.deleteFailed,
      );
      expect(
        AppFailure.from(PlatformException(code: 'USER_CANCELLED')).kind,
        FailureKind.cancelled,
      );
    });

    test('storage problems are recognised in both forms', () {
      expect(
        AppFailure.from(PlatformException(code: 'STORAGE_UNAVAILABLE')).kind,
        FailureKind.storageUnavailable,
      );
      expect(
        AppFailure.from(PlatformException(code: 'INVALID_STORAGE_DATA')).kind,
        FailureKind.storageUnavailable,
      );
    });

    test('a missing native side is unsupported, not a crash', () {
      final AppFailure failure = AppFailure.from(
        MissingPluginException('No implementation found'),
      );
      expect(failure.kind, FailureKind.unsupported);
      // Nothing the user can do, so no pointless retry.
      expect(failure.isRetryable, isFalse);
    });

    test('an unrecognised error is still showable, never swallowed', () {
      final AppFailure failure = AppFailure.from(
        StateError('something odd'),
      );
      expect(failure.kind, FailureKind.unknown);
      expect(failure.message, isNotEmpty);
      // The original text survives for a bug report.
      expect(failure.technicalDetail, contains('something odd'));
    });

    test('classification never throws, whatever it is handed', () {
      final List<Object> weird = <Object>[
        'a bare string',
        42,
        <String, Object>{'not': 'an error'},
        Exception(),
        PlatformException(code: ''),
      ];
      for (final Object error in weird) {
        expect(() => AppFailure.from(error), returnsNormally);
        expect(AppFailure.from(error).message, isNotEmpty);
      }
    });

    test('an AppFailure passes through unchanged', () {
      const AppFailure original = AppFailure(
        kind: FailureKind.cancelled,
        message: 'Cancelled.',
      );
      expect(identical(AppFailure.from(original), original), isTrue);
    });

    test('the platform code is kept for diagnosis', () {
      final AppFailure failure = AppFailure.from(
        PlatformException(
          code: 'SCAN_FAILED',
          message: 'Unable to scan device files.',
          details: 'IllegalArgumentException: Invalid token LIMIT',
        ),
      );
      // Exactly the information that was missing when scans broke on
      // Android 11.
      expect(failure.technicalDetail, contains('SCAN_FAILED'));
      expect(failure.technicalDetail, contains('Invalid token LIMIT'));
    });
  });

  group('Repositories degrade instead of crashing', () {
    test('storage reports unavailable when the channel is missing', () async {
      _absentChannel('com.mobilecleaner.app/storage');

      await expectLater(
        PlatformStorageRepository().getStorageInfo(),
        throwsA(
          isA<PlatformException>().having(
            (PlatformException e) => e.code,
            'code',
            'STORAGE_UNAVAILABLE',
          ),
        ),
      );
    });

    test('storage rejects nonsense values rather than showing them', () async {
      final MethodChannel channel = MethodChannel(
        'com.mobilecleaner.app/storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            return <String, Object>{'totalBytes': 0, 'freeBytes': 0};
          });

      await expectLater(
        PlatformStorageRepository().getStorageInfo(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('the scanner reports unavailable rather than an empty library',
        () async {
      _absentChannel('com.mobilecleaner.app/file_scanner');

      // Returning "no files" here would look like a spotlessly clean device.
      await expectLater(
        MethodChannelFileScanner().scan(
          categories: const <FileCategory>[FileCategory.images],
          limitPerCategory: 10,
          minSizeBytes: 0,
          sortOrder: FileSortOrder.sizeDesc,
        ),
        throwsA(
          isA<PlatformException>().having(
            (PlatformException e) => e.code,
            'code',
            'SCAN_UNAVAILABLE',
          ),
        ),
      );
    });

    test('a failed delete reports every file, and throws nothing', () async {
      final MethodChannel channel = _throwingChannel(
        'com.mobilecleaner.app/delete',
        PlatformException(code: 'DELETE_FAILED', message: 'Denied.'),
      );
      final List<ScannedFile> files = <ScannedFile>[_file('1'), _file('2')];

      final DeleteResult result = await PlatformDeleteRepository(
        channel: channel,
      ).deleteFiles(files);

      // No exception escapes, and nothing is claimed as deleted.
      expect(result.deletedCount, 0);
      expect(result.failureCount, 2);
      expect(result.isFailure, isTrue);
    });

    test('deleting with no delete channel fails safely', () async {
      final MethodChannel channel = _absentChannel(
        'com.mobilecleaner.app/delete',
      );

      final DeleteResult result = await PlatformDeleteRepository(
        channel: channel,
      ).deleteFiles(<ScannedFile>[_file('1')]);

      expect(result.deletedCount, 0);
      expect(result.failureCount, 1);
    });

    test('deleting nothing is a no-op, not an error', () async {
      final DeleteResult result = await PlatformDeleteRepository(
        channel: _absentChannel('com.mobilecleaner.app/delete'),
      ).deleteFiles(const <ScannedFile>[]);

      expect(result.deletedCount, 0);
      expect(result.failureCount, 0);
    });
  });

  group('DeleteResult states', () {
    test('cancellation is not the same as failure', () {
      const DeleteResult cancelled = DeleteResult.cancelled();

      expect(cancelled.userCancelled, isTrue);
      expect(cancelled.deletedCount, 0);
      // Nothing was removed, but nothing went wrong either.
      expect(cancelled.isCompleteSuccess, isFalse);
      expect(cancelled.failureCount, 0);
    });

    test('a partial delete is reported honestly', () {
      final DeleteResult partial = DeleteResult(
        deletedFiles: <ScannedFile>[_file('1')],
        failures: const <DeleteFailure>[
          DeleteFailure(uri: 'content://2', reason: 'Denied'),
        ],
      );

      expect(partial.isPartialSuccess, isTrue);
      expect(partial.isCompleteSuccess, isFalse);
      // Only confirmed deletions count toward freed space.
      expect(partial.freedBytes, 1024 * 1024);
    });
  });

  group('Error screen', () {
    testWidgets('a permission problem offers settings, not a retry', (
      WidgetTester tester,
    ) async {
      await _pumpError(
        tester,
        PlatformException(code: 'SCAN_PERMISSION_DENIED'),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('files_error_headline')))
            .data,
        'Storage access is required',
      );
      expect(find.byKey(const Key('files_permission_button')), findsOneWidget);
      // A retry cannot help until the permission changes.
      expect(find.byKey(const Key('files_retry_button')), findsNothing);
    });

    testWidgets('storage unavailable says so specifically', (
      WidgetTester tester,
    ) async {
      await _pumpError(tester, PlatformException(code: 'STORAGE_UNAVAILABLE'));

      expect(
        tester
            .widget<Text>(find.byKey(const Key('files_error_headline')))
            .data,
        'Storage unavailable',
      );
      expect(find.byKey(const Key('files_retry_button')), findsOneWidget);
      expect(find.byKey(const Key('files_permission_button')), findsNothing);
    });

    testWidgets('an unsupported feature offers no action at all', (
      WidgetTester tester,
    ) async {
      await _pumpError(tester, MissingPluginException('none'));

      expect(
        tester
            .widget<Text>(find.byKey(const Key('files_error_headline')))
            .data,
        'Not available here',
      );
      expect(find.byKey(const Key('files_retry_button')), findsNothing);
      expect(find.byKey(const Key('files_permission_button')), findsNothing);
    });

    testWidgets('the technical detail is shown for a bug report', (
      WidgetTester tester,
    ) async {
      await _pumpError(
        tester,
        PlatformException(
          code: 'SCAN_FAILED',
          message: 'Unable to scan device files.',
          details: 'IllegalArgumentException: Invalid token LIMIT',
        ),
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('files_error_detail'))).data,
        contains('Invalid token LIMIT'),
      );
    });

    testWidgets('every failure kind renders without throwing', (
      WidgetTester tester,
    ) async {
      final List<Object> errors = <Object>[
        PlatformException(code: 'SCAN_PERMISSION_DENIED'),
        PlatformException(code: 'FILE_NOT_FOUND'),
        PlatformException(code: 'DELETE_FAILED'),
        PlatformException(code: 'STORAGE_UNAVAILABLE'),
        PlatformException(code: 'USER_CANCELLED'),
        MissingPluginException('none'),
        StateError('unexpected'),
      ];

      for (final Object error in errors) {
        await _pumpError(tester, error);
        expect(
          find.byKey(const Key('files_error_headline')),
          findsOneWidget,
          reason: 'no headline for $error',
        );
        expect(tester.takeException(), isNull, reason: 'threw on $error');
      }
    });
  });
}
