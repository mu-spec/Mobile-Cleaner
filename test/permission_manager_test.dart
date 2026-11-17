import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/app/router/permission_policy.dart';
import 'package:phone_storage_cleaner/features/files/data/storage_access_repository.dart';
import 'package:phone_storage_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';
import 'package:phone_storage_cleaner/features/permissions/presentation/providers/permission_manager.dart';

import 'support/permission_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerFor(
    FakePermissionGateway gateway,
    FakeFolderAccess folders,
  ) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        permissionGatewayProvider.overrideWithValue(gateway),
        storageAccessRepositoryProvider.overrideWithValue(folders),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('Android capability policy', () {
    for (final int sdk in <int>[24, 25, 26, 27, 28, 29, 30, 31, 32]) {
      test(
        'API $sdk reuses legacy read but respects scoped non-media access',
        () {
          final PermissionSnapshot denied = PermissionSnapshot(
            sdkInt: sdk,
            statuses: const {},
          );
          expect(denied.requiredFor(PermissionFeature.photos), {
            PermissionKind.storage,
          });
          expect(denied.requiredFor(PermissionFeature.videos), {
            PermissionKind.storage,
          });
          expect(denied.allowsFeature(PermissionFeature.nonMedia), sdk >= 29);
          final PermissionSnapshot granted = PermissionSnapshot(
            sdkInt: sdk,
            statuses: const {
              PermissionKind.storage: AppPermissionStatus.granted,
            },
          );
          expect(granted.allowsFeature(PermissionFeature.media), isTrue);
          expect(granted.allowsFeature(PermissionFeature.nonMedia), isTrue);
        },
      );
    }
    for (final int sdk in <int>[33, 34, 35, 36]) {
      test('API $sdk keeps each media grant separate', () {
        final PermissionSnapshot photos = PermissionSnapshot(
          sdkInt: sdk,
          statuses: const {PermissionKind.photos: AppPermissionStatus.granted},
        );
        expect(photos.allowsFeature(PermissionFeature.photos), isTrue);
        expect(photos.allowsFeature(PermissionFeature.videos), isFalse);
        expect(photos.allowsFeature(PermissionFeature.audio), isFalse);
        expect(
          photos.statusOf(PermissionKind.storage),
          AppPermissionStatus.denied,
        );
        expect(
          photos.statusFor(PermissionFeature.media),
          AppPermissionStatus.limited,
        );
        expect(photos.missingFor(PermissionFeature.media), {
          PermissionKind.videos,
          PermissionKind.audio,
        });
        expect(photos.folderUris, isEmpty);
      });
    }
    test(
      'selected visual media is sufficient for its tools, not full storage',
      () {
        final PermissionSnapshot selected = PermissionSnapshot(
          sdkInt: 34,
          statuses: const {
            PermissionKind.photos: AppPermissionStatus.limited,
            PermissionKind.audio: AppPermissionStatus.limited,
          },
        );
        expect(selected.allowsFeature(PermissionFeature.photos), isTrue);
        expect(
          selected.statusFor(PermissionFeature.photos),
          AppPermissionStatus.limited,
        );
        expect(selected.allowsFeature(PermissionFeature.audio), isFalse);
        expect(selected.allowsFeature(PermissionFeature.videos), isFalse);
        expect(selected.allows(PermissionKind.storage), isFalse);
      },
    );
    test('a folder grant is never a photo or unrestricted media grant', () {
      final PermissionSnapshot folder = PermissionSnapshot(
        sdkInt: 34,
        statuses: const {},
        folderUris: const {'content://tree/one'},
      );
      expect(folder.allowsFeature(PermissionFeature.photos), isFalse);
      expect(folder.allowsFeature(PermissionFeature.media), isTrue);
      expect(
        folder.statusFor(PermissionFeature.media),
        AppPermissionStatus.limited,
      );
      expect(folder.allowsFeature(PermissionFeature.nonMedia), isTrue);
    });
    test(
      'all feature routes share a central policy, including direct links',
      () {
        for (final String path in <String>[
          '/photos',
          '/screenshot-cleaner',
          '/large-photos',
          '/photo-duplicates',
          '/similar-photos',
        ]) {
          expect(
            permissionFeatureFor(Uri.parse(path)),
            PermissionFeature.photos,
          );
        }
        for (final String path in <String>[
          '/large-files',
          '/duplicates',
          '/clean',
        ]) {
          expect(
            permissionFeatureFor(Uri.parse(path)),
            PermissionFeature.media,
          );
        }
        expect(
          permissionFeatureFor(Uri.parse('/files')),
          PermissionFeature.nonMedia,
        );
        expect(
          permissionFeatureFor(Uri.parse('/file-category?category=images')),
          PermissionFeature.photos,
        );
        expect(
          permissionFeatureFor(Uri.parse('/file-category?category=audio')),
          PermissionFeature.audio,
        );
        expect(
          permissionFeatureFor(Uri.parse('/apk-cleaner')),
          PermissionFeature.nonMedia,
        );
        expect(
          permissionFeatureFor(Uri.parse('/downloads-cleaner')),
          PermissionFeature.nonMedia,
        );
        expect(
          permissionFeatureFor(Uri.parse('/videos')),
          PermissionFeature.videos,
        );
        expect(
          permissionFeatureFor(Uri.parse('/apps')),
          PermissionFeature.none,
        );
        expect(
          permissionFeatureFor(Uri.parse('/scan-progress?scan=apps')),
          PermissionFeature.none,
        );
        expect(
          permissionFeatureFor(Uri.parse('/scan-progress?scan=photo-cleanup')),
          PermissionFeature.photos,
        );
        expect(
          permissionFeatureFor(Uri.parse('/scan-progress?scan=large-videos')),
          PermissionFeature.videos,
        );
      },
    );
    test(
      'permission continuation rejects external and looping destinations',
      () {
        expect(permissionDestination('https://example.com/files'), isNull);
        expect(permissionDestination('//example.com/files'), isNull);
        expect(permissionDestination('/permissions?next=/files'), isNull);
        expect(permissionDestination('/unknown'), isNull);
        expect(permissionDestination('/videos')?.path, '/videos');
      },
    );
  });

  group('Central manager', () {
    late FakePermissionGateway gateway;
    late FakeFolderAccess folders;
    late ProviderContainer container;
    late PermissionManager manager;

    setUp(() {
      gateway = FakePermissionGateway();
      folders = FakeFolderAccess();
      container = containerFor(gateway, folders);
      manager = container.read(permissionManagerProvider.notifier);
    });

    test(
      'a photo grant is reused by every other photo tool without a request',
      () async {
        await manager.request(PermissionFeature.photos);
        expect(gateway.requests, [
          {PermissionKind.photos},
        ]);
        await manager.request(PermissionFeature.photos);
        expect(
          (await manager.refresh()).allowsFeature(PermissionFeature.photos),
          isTrue,
        );
        expect(gateway.requests.length, 1);
      },
    );
    test(
      'a sufficient partial result does not request optional media types',
      () async {
        gateway.statuses[PermissionKind.photos] = AppPermissionStatus.limited;
        final PermissionSnapshot snapshot = await manager.request(
          PermissionFeature.media,
        );
        expect(
          snapshot.statusFor(PermissionFeature.media),
          AppPermissionStatus.limited,
        );
        expect(gateway.requests, isEmpty);
      },
    );
    test('a video feature never borrows a photo grant', () async {
      await manager.request(PermissionFeature.photos);
      await manager.request(PermissionFeature.videos);
      expect(gateway.requests, [
        {PermissionKind.photos},
        {PermissionKind.videos},
      ]);
    });
    test(
      'denial is stable; reads/navigation never launch another prompt',
      () async {
        gateway.response = AppPermissionStatus.denied;
        await manager.request(PermissionFeature.photos);
        await manager.refresh();
        await manager.refresh();
        expect(gateway.requests.length, 1);
        expect(
          container
              .read(permissionManagerProvider)
              .value!
              .allowsFeature(PermissionFeature.photos),
          isFalse,
        );
      },
    );
    test(
      'blocked and restricted grants cannot trigger a runtime dialog',
      () async {
        for (final AppPermissionStatus status in [
          AppPermissionStatus.permanentlyDenied,
          AppPermissionStatus.restricted,
        ]) {
          gateway.statuses[PermissionKind.photos] = status;
          expect(
            (await manager.request(PermissionFeature.photos))
                .statusFor(PermissionFeature.photos),
            status,
          );
        }
        expect(gateway.requests, isEmpty);
        await manager.openSettings();
        expect(gateway.settingsOpened, 1);
      },
    );
    test(
      'concurrent reads and requests are coalesced, not duplicated',
      () async {
        gateway.requestGate = Completer<void>();
        final Future<PermissionSnapshot> first = manager.request(
          PermissionFeature.photos,
        );
        final Future<PermissionSnapshot> second = manager.request(
          PermissionFeature.photos,
        );
        expect(identical(first, second), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(gateway.requests.length, 1);
        final Future<PermissionSnapshot> resume = manager.refresh();
        gateway.requestGate!.complete();
        await Future.wait([first, second, resume]);
        expect(gateway.requests.length, 1);
        final int before = gateway.reads;
        await Future.wait([
          manager.refresh(),
          manager.refresh(),
          manager.refresh(),
        ]);
        expect(gateway.reads - before, 1);
      },
    );
    test(
      'Settings/foreground rechecks actual grants, including revocation',
      () async {
        await manager.request(PermissionFeature.photos);
        gateway.statuses[PermissionKind.photos] = AppPermissionStatus.denied;
        manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await manager.refresh();
        expect(
          container
              .read(permissionManagerProvider)
              .value!
              .allowsFeature(PermissionFeature.photos),
          isFalse,
        );
        gateway.statuses[PermissionKind.photos] = AppPermissionStatus.limited;
        manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await manager.refresh();
        expect(
          container
              .read(permissionManagerProvider)
              .value!
              .statusFor(PermissionFeature.photos),
          AppPermissionStatus.limited,
        );
        expect(gateway.requests.length, 1);
      },
    );
    test(
      'a restarted manager rechecks Android, never a persistent granted flag',
      () async {
        await manager.request(PermissionFeature.photos);
        final ProviderContainer restarted = containerFor(gateway, folders);
        expect(
          (await restarted.read(permissionManagerProvider.notifier).refresh())
              .allowsFeature(PermissionFeature.photos),
          isTrue,
        );
        expect(gateway.requests.length, 1);
        gateway.statuses[PermissionKind.photos] = AppPermissionStatus.denied;
        expect(
          (await restarted.read(permissionManagerProvider.notifier).refresh())
              .allowsFeature(PermissionFeature.photos),
          isFalse,
        );
      },
    );
    test(
      'SAF grants are shared and can be revoked independently of media',
      () async {
        await manager.requestFolderAccess();
        expect((await manager.refresh()).folderUris.length, 1);
        expect(
          (await manager.refresh()).allowsFeature(PermissionFeature.photos),
          isFalse,
        );
        folders.folders.clear();
        expect((await manager.refresh()).folderUris, isEmpty);
        expect(folders.pickerRequests, 1);
        expect(gateway.requests, isEmpty);
      },
    );
    test(
      'an OS read failure is not accepted as an earlier cached grant',
      () async {
        await manager.request(PermissionFeature.photos);
        gateway.failReads = true;
        await expectLater(manager.refresh(), throwsStateError);
        expect(container.read(permissionManagerProvider).hasError, isTrue);
      },
    );
  });
}
