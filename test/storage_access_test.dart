import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_channel.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/storage_access_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';

class _FakeScannerChannel implements FileScannerChannel {
  _FakeScannerChannel(this.payload);

  final Map<Object?, Object?> payload;

  @override
  Future<Map<Object?, Object?>> scan({
    required List<FileCategory> categories,
    required int limitPerCategory,
    required int minSizeBytes,
    required FileSortOrder sortOrder,
  }) async => payload;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GrantedFolder parsing', () {
    test('reads uri and label from the platform payload', () {
      final List<GrantedFolder> folders =
          PlatformStorageAccessRepository.parseFolders(<Object?>[
            <Object?, Object?>{
              'uri': 'content://com.android.externalstorage.documents/tree/primary%3ADocuments',
              'label': 'Documents',
            },
          ]);

      expect(folders, hasLength(1));
      expect(folders.single.label, 'Documents');
      expect(folders.single.uri, contains('Documents'));
    });

    test('skips malformed rows and defaults a missing label', () {
      final List<GrantedFolder> folders =
          PlatformStorageAccessRepository.parseFolders(<Object?>[
            'not-a-map',
            <Object?, Object?>{'label': 'No uri'},
            <Object?, Object?>{'uri': ''},
            <Object?, Object?>{'uri': 'content://tree/1'},
          ]);

      expect(folders, hasLength(1));
      expect(folders.single.uri, 'content://tree/1');
      expect(folders.single.label, 'Folder');
    });

    test('handles a null payload', () {
      expect(PlatformStorageAccessRepository.parseFolders(null), isEmpty);
    });

    test('folders are equal by uri', () {
      const GrantedFolder a = GrantedFolder(uri: 'content://x', label: 'A');
      const GrantedFolder b = GrantedFolder(uri: 'content://x', label: 'B');
      expect(a, equals(b));
    });
  });

  group('PlatformStorageAccessRepository', () {
    const MethodChannel channel = MethodChannel('saf-test');
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

    test('requests folder access with the initial directory', () async {
      mock(
        (MethodCall call) => <Object?>[
          <Object?, Object?>{'uri': 'content://tree/docs', 'label': 'Documents'},
        ],
      );
      final PlatformStorageAccessRepository repository =
          PlatformStorageAccessRepository(channel: channel);

      final List<GrantedFolder> folders = await repository.requestFolderAccess(
        initialDir: 'Documents',
      );

      expect(calls.single.method, 'requestTreeAccess');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['initialDir'],
        'Documents',
      );
      expect(folders.single.label, 'Documents');
    });

    test('a denied grant resolves to an empty list, not an error', () async {
      mock((MethodCall call) => throw PlatformException(code: 'GRANT_FAILED'));
      final PlatformStorageAccessRepository repository =
          PlatformStorageAccessRepository(channel: channel);

      expect(await repository.requestFolderAccess(), isEmpty);
      expect(await repository.grantedFolders(), isEmpty);
    });

    test('isAccessRequired defaults to false when unavailable', () async {
      mock((MethodCall call) => throw MissingPluginException());
      final PlatformStorageAccessRepository repository =
          PlatformStorageAccessRepository(channel: channel);

      expect(await repository.isAccessRequired(), isFalse);
    });

    test('releaseFolder passes the uri through', () async {
      mock((MethodCall call) => <Object?>[]);
      final PlatformStorageAccessRepository repository =
          PlatformStorageAccessRepository(channel: channel);

      await repository.releaseFolder('content://tree/docs');

      expect(calls.single.method, 'releaseTree');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['uri'],
        'content://tree/docs',
      );
    });
  });

  group('needsFolderAccess flows through the scan', () {
    test('is true when the platform reports hidden non-media files', () async {
      final FileScanResult result = await MediaStoreFileScannerRepository(
        _FakeScannerChannel(<Object?, Object?>{
          'files': <Object?>[],
          'needsFolderAccess': true,
        }),
      ).scan();

      expect(result.needsFolderAccess, isTrue);
    });

    test('defaults to false when the platform omits it', () async {
      final FileScanResult result = await MediaStoreFileScannerRepository(
        _FakeScannerChannel(<Object?, Object?>{'files': <Object?>[]}),
      ).scan();

      expect(result.needsFolderAccess, isFalse);
    });

    test('fromFiles defaults the flag to false', () {
      expect(
        FileScanResult.fromFiles(const []).needsFolderAccess,
        isFalse,
      );
    });
  });
}
