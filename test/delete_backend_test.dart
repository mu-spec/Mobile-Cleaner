import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

const int _mib = 1024 * 1024;

/// A MediaStore row — images, video, audio, and most documents.
ScannedFile _mediaStoreFile({
  String id = '1',
  FileCategory category = FileCategory.images,
  int sizeBytes = 10 * _mib,
}) {
  return ScannedFile(
    id: id,
    name: 'IMG_$id.jpg',
    path: '/storage/emulated/0/DCIM/Camera/IMG_$id.jpg',
    uri: 'content://media/external/images/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: DateTime(2026, 5, 1),
    mimeType: 'image/jpeg',
  );
}

/// A SAF document, as returned by the granted-tree scanner.
ScannedFile _safFile({String id = 'doc-1', int sizeBytes = 5 * _mib}) {
  return ScannedFile(
    id: id,
    name: 'report.pdf',
    path: 'Documents/report.pdf',
    uri: 'content://com.android.externalstorage.documents/tree/'
        'primary%3ADocuments/document/primary%3ADocuments%2Freport.pdf',
    sizeBytes: sizeBytes,
    category: FileCategory.documents,
    dateModified: DateTime(2026, 4, 1),
    mimeType: 'application/pdf',
  );
}

/// A legacy direct path, from the pre-scoped-storage scan.
ScannedFile _directFile({String id = 'f1', int sizeBytes = 2 * _mib}) {
  return ScannedFile(
    id: id,
    name: 'old.zip',
    path: '/storage/emulated/0/Download/old.zip',
    uri: 'file:///storage/emulated/0/Download/old.zip',
    sizeBytes: sizeBytes,
    category: FileCategory.downloads,
    dateModified: DateTime(2025, 1, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deletable routing', () {
    test('MediaStore, SAF and direct paths are all deletable', () {
      expect(_mediaStoreFile().isDeletable, isTrue);
      expect(_safFile().isDeletable, isTrue);
      // The bridge deletes file:// directly, so it must not be greyed out.
      expect(_directFile().isDeletable, isTrue);
    });

    test('an unknown scheme is not offered for deletion', () {
      final ScannedFile odd = _mediaStoreFile().copyWith(
        uri: 'http://example.com/a.jpg',
      );
      expect(odd.isDeletable, isFalse);
    });
  });

  group('PlatformDeleteRepository', () {
    const MethodChannel channel = MethodChannel('delete-backend-test');
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

    test('a MediaStore URI deletes and reports the freed size', () async {
      final ScannedFile file = _mediaStoreFile();
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
      expect(result.freedBytes, 10 * _mib);
      expect(result.isCompleteSuccess, isTrue);
    });

    test('a SAF document URI deletes through the same call', () async {
      final ScannedFile file = _safFile();
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[file.uri],
          'failed': <Object?>[],
        },
      );

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[file],
      );

      // One shared backend: no separate SAF entry point.
      expect(calls.single.method, 'deleteFiles');
      expect(result.deletedCount, 1);
      expect(result.freedBytes, 5 * _mib);
    });

    test('a direct file path deletes', () async {
      final ScannedFile file = _directFile();
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[file.uri],
          'failed': <Object?>[],
        },
      );

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[file],
      );

      expect(result.deletedCount, 1);
      expect(result.freedBytes, 2 * _mib);
    });

    test('every supported type can be sent in one batch', () async {
      final List<ScannedFile> files = <ScannedFile>[
        _mediaStoreFile(id: '1', category: FileCategory.images),
        _mediaStoreFile(id: '2', category: FileCategory.videos),
        _mediaStoreFile(id: '3', category: FileCategory.audio),
        _safFile(),
        _directFile(),
      ];
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[for (final ScannedFile f in files) f.uri],
          'failed': <Object?>[],
        },
      );

      final DeleteResult result = await repository().deleteFiles(files);

      final Map<Object?, Object?> args =
          calls.single.arguments as Map<Object?, Object?>;
      expect((args['uris']! as List<Object?>), hasLength(5));
      expect(result.deletedCount, 5);
    });

    test('denied access keeps the file and reports the reason', () async {
      final ScannedFile file = _mediaStoreFile();
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

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[file],
      );

      expect(result.deletedCount, 0);
      expect(result.freedBytes, 0);
      expect(result.failureCount, 1);
      expect(result.failures.single.reason, 'Access to this file was denied.');
      expect(result.isFailure, isTrue);
    });

    test('a cancelled system confirmation deletes nothing', () async {
      final ScannedFile file = _mediaStoreFile();
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[],
          'failed': <Object?>[],
          'userCancelled': true,
        },
      );

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[file],
      );

      expect(result.userCancelled, isTrue);
      expect(result.deletedCount, 0);
      expect(result.freedBytes, 0);
      expect(result.isCompleteSuccess, isFalse);
    });

    test('cancelling still reports what went before the prompt', () async {
      // SAF and direct-path files are removed before the MediaStore dialog is
      // raised, so cancelling must not hide them.
      final ScannedFile saf = _safFile();
      final ScannedFile media = _mediaStoreFile();
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[saf.uri],
          'failed': <Object?>[],
          'userCancelled': true,
        },
      );

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[saf, media],
      );

      expect(result.userCancelled, isTrue);
      expect(result.deletedCount, 1);
      expect(result.freedBytes, 5 * _mib);
    });

    test('a partly denied batch reports both halves', () async {
      final ScannedFile ok = _mediaStoreFile(id: '1');
      final ScannedFile denied = _mediaStoreFile(id: '2', sizeBytes: 7 * _mib);
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[ok.uri],
          'failed': <Object?>[
            <Object?, Object?>{
              'uri': denied.uri,
              'reason': 'Access to this file was denied.',
            },
          ],
        },
      );

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[ok, denied],
      );

      expect(result.isPartialSuccess, isTrue);
      expect(result.deletedCount, 1);
      // Only the confirmed deletion counts toward freed space.
      expect(result.freedBytes, 10 * _mib);
      expect(result.failureCount, 1);
    });

    test('a URI reported both deleted and failed counts as failed', () async {
      final ScannedFile file = _mediaStoreFile();
      mock(
        (MethodCall call) => <Object?, Object?>{
          'deletedUris': <Object?>[file.uri],
          'failed': <Object?>[
            <Object?, Object?>{'uri': file.uri, 'reason': 'Locked'},
          ],
        },
      );

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[file],
      );

      // Never claim a file is gone when the platform is ambiguous.
      expect(result.deletedCount, 0);
      expect(result.freedBytes, 0);
      expect(result.failureCount, 1);
    });

    test('a platform error fails every file rather than claiming success',
        () async {
      mock((MethodCall call) => throw PlatformException(code: 'DELETE_FAILED'));

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[_mediaStoreFile(), _safFile()],
      );

      expect(result.deletedCount, 0);
      expect(result.failureCount, 2);
    });

    test('an empty selection never reaches the platform', () async {
      mock((MethodCall call) => <Object?, Object?>{});

      final DeleteResult result = await repository().deleteFiles(
        <ScannedFile>[],
      );

      expect(calls, isEmpty);
      expect(result.deletedCount, 0);
    });
  });
}
