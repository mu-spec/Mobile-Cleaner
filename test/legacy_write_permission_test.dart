import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

const int _mib = 1024 * 1024;

ScannedFile _mediaFile({String id = '1', int sizeBytes = 8 * _mib}) {
  return ScannedFile(
    id: id,
    name: 'IMG_$id.jpg',
    path: '/storage/emulated/0/DCIM/Camera/IMG_$id.jpg',
    uri: 'content://media/external/images/media/$id',
    sizeBytes: sizeBytes,
    category: FileCategory.images,
    dateModified: DateTime(2026, 5, 1),
    mimeType: 'image/jpeg',
  );
}

/// Mirrors what `DeleteBridge` returns on API 28 once the runtime
/// `WRITE_EXTERNAL_STORAGE` request has been answered.
///
/// The Kotlin gate itself cannot run under `flutter test`, so these cover the
/// contract the bridge promises: on grant the legacy delete proceeds, on
/// denial nothing is removed and the existing access-denied failure is
/// reported for every item.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('legacy-write-test');
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

  PlatformDeleteRepository repository() =>
      PlatformDeleteRepository(channel: channel);

  group('API 28 legacy write permission', () {
    test('granted: the legacy delete proceeds and reports freed space',
        () async {
      final ScannedFile file = _mediaFile();
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[file.uri],
          'failed': <Object?>[],
          'userCancelled': false,
        },
      );

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[file],
      );

      expect(calls.single.method, 'deleteFiles');
      expect(result.deletedCount, 1);
      expect(result.freedBytes, 8 * _mib);
      expect(result.isCompleteSuccess, isTrue);
    });

    test('denied: nothing is deleted and access-denied is reported', () async {
      final ScannedFile file = _mediaFile();
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[],
          'failed': <Object?>[
            <Object?, Object?>{
              'uri': file.uri,
              'reason': 'Access to this file was denied.',
            },
          ],
          // A permission refusal is not a system-dialog cancellation.
          'userCancelled': false,
        },
      );

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[file],
      );

      expect(result.deletedCount, 0);
      expect(result.freedBytes, 0);
      expect(result.failureCount, 1);
      expect(result.failures.single.reason, 'Access to this file was denied.');
      expect(result.isFailure, isTrue);
      expect(result.userCancelled, isFalse);
    });

    test('denied: every item in the batch is kept and reported', () async {
      final List<ScannedFile> files = <ScannedFile>[
        _mediaFile(id: '1'),
        _mediaFile(id: '2', sizeBytes: 4 * _mib),
        _mediaFile(id: '3', sizeBytes: 2 * _mib),
      ];
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[],
          'failed': <Object?>[
            for (final ScannedFile f in files)
              <Object?, Object?>{
                'uri': f.uri,
                'reason': 'Access to this file was denied.',
              },
          ],
        },
      );

      final DeleteResult result = await repository().deleteFiles(files);

      expect(result.deletedCount, 0);
      expect(result.failureCount, 3);
      expect(result.freedBytes, 0);
    });

    test('granted: a partly blocked batch still reports each half', () async {
      final ScannedFile ok = _mediaFile(id: '1');
      final ScannedFile blocked = _mediaFile(id: '2', sizeBytes: 3 * _mib);
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[ok.uri],
          'failed': <Object?>[
            <Object?, Object?>{
              'uri': blocked.uri,
              'reason': 'Access to this file was denied.',
            },
          ],
        },
      );

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[ok, blocked],
      );

      expect(result.isPartialSuccess, isTrue);
      expect(result.deletedCount, 1);
      // Only the confirmed deletion counts toward reclaimed space.
      expect(result.freedBytes, 8 * _mib);
      expect(result.failureCount, 1);
    });

    test('a permission denial is distinguishable from a cancelled dialog',
        () async {
      final ScannedFile file = _mediaFile();

      // Denial: reported as a failure, not a cancellation.
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[],
          'failed': <Object?>[
            <Object?, Object?>{
              'uri': file.uri,
              'reason': 'Access to this file was denied.',
            },
          ],
        },
      );
      final DeleteResult denied = await repository().deleteFiles(
        <ScannedFile>[file],
      );

      // Cancellation: no failures recorded.
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[],
          'failed': <Object?>[],
          'userCancelled': true,
        },
      );
      final DeleteResult cancelled = await repository().deleteFiles(
        <ScannedFile>[file],
      );

      expect(denied.userCancelled, isFalse);
      expect(denied.failureCount, 1);
      expect(cancelled.userCancelled, isTrue);
      expect(cancelled.failureCount, 0);
      // Neither removed anything.
      expect(denied.deletedCount, 0);
      expect(cancelled.deletedCount, 0);
    });
  });
}
