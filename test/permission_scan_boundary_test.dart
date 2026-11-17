import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_category.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_scan_result.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';

class _RecordingScanner implements FileScannerRepository {
  final List<FileScanRequest> requests = [];
  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    requests.add(request);
    return FileScanResult.empty;
  }
}

void main() {
  test(
    'mixed scan excludes denied video/audio, preserving every scan option',
    () async {
      final delegate = _RecordingScanner();
      final scanner = PermissionAwareFileScannerRepository(
        delegate,
        () async => PermissionSnapshot(
          sdkInt: 34,
          statuses: const {PermissionKind.photos: AppPermissionStatus.limited},
        ),
      );
      final result = await scanner.scan(
        const FileScanRequest(
          limitPerCategory: 73,
          minSizeBytes: 456,
          sortOrder: FileSortOrder.dateDesc,
        ),
      );
      expect(identical(result, FileScanResult.empty), isTrue);
      final request = delegate.requests.single;
      expect(request.categories, [
        FileCategory.images,
        FileCategory.documents,
        FileCategory.downloads,
        FileCategory.apks,
      ]);
      expect(request.limitPerCategory, 73);
      expect(request.minSizeBytes, 456);
      expect(request.sortOrder, FileSortOrder.dateDesc);
    },
  );
  test(
    'full access leaves discovery categories and returned calculations intact',
    () async {
      final delegate = _RecordingScanner();
      final scanner = PermissionAwareFileScannerRepository(
        delegate,
        () async => PermissionSnapshot(
          sdkInt: 34,
          statuses: {
            for (final kind in PermissionKind.values)
              kind: AppPermissionStatus.granted,
          },
        ),
      );
      expect(identical(await scanner.scan(), FileScanResult.empty), isTrue);
      expect(delegate.requests.single.categories, FileCategory.scannable);
    },
  );
  test(
    'scoped folder-only mode still discovers its available non-media',
    () async {
      final delegate = _RecordingScanner();
      final scanner = PermissionAwareFileScannerRepository(
        delegate,
        () async => PermissionSnapshot(
          sdkInt: 30,
          statuses: const {},
          folderUris: const {'content://tree/documents'},
        ),
      );
      await scanner.scan();
      expect(delegate.requests.single.categories, [
        FileCategory.documents,
        FileCategory.downloads,
        FileCategory.apks,
      ]);
    },
  );
  test(
    'revocation is reread before scanning, not inferred from last result',
    () async {
      final delegate = _RecordingScanner();
      bool granted = true;
      final scanner = PermissionAwareFileScannerRepository(
        delegate,
        () async => PermissionSnapshot(
          sdkInt: 34,
          statuses: {
            PermissionKind.photos: granted
                ? AppPermissionStatus.granted
                : AppPermissionStatus.denied,
          },
        ),
      );
      const request = FileScanRequest(categories: [FileCategory.images]);
      await scanner.scan(request);
      granted = false;
      await expectLater(
        scanner.scan(request),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'SCAN_PERMISSION_DENIED',
          ),
        ),
      );
      expect(delegate.requests.length, 1);
    },
  );
  test(
    'legacy denied read cannot scan or launch any permission prompt',
    () async {
      final delegate = _RecordingScanner();
      final scanner = PermissionAwareFileScannerRepository(
        delegate,
        () async => PermissionSnapshot(sdkInt: 28, statuses: const {}),
      );
      await expectLater(scanner.scan(), throwsA(isA<PlatformException>()));
      expect(delegate.requests, isEmpty);
    },
  );
}
