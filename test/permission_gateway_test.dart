import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_storage_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );
  final List<MethodCall> calls = <MethodCall>[];
  final Map<int, int> actual = <int, int>{};

  setUp(() {
    calls.clear();
    actual.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'checkPermissionStatus' => actual[call.arguments as int] ?? 0,
            'requestPermissions' => <int, int>{
              for (final int id in (call.arguments as List).cast<int>())
                id: actual[id] ?? 0,
            },
            'openAppSettings' => true,
            _ => null,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  for (final int sdk in <int>[24, 28, 29, 30, 32]) {
    test('API $sdk reads and requests legacy READ permission only', () async {
      final PermissionGateway gateway = PermissionGateway(
        isAndroid: true,
        androidSdk: () async => sdk,
      );
      actual[Permission.storage.value] = 1;
      final snapshot = await gateway.readPermissions();
      expect(
        snapshot.statusOf(PermissionKind.storage),
        AppPermissionStatus.granted,
      );
      expect(
        calls
            .where((call) => call.method == 'checkPermissionStatus')
            .map((call) => call.arguments),
        [Permission.storage.value],
      );
      await gateway.requestPermissions({
        PermissionKind.storage,
        PermissionKind.photos,
      });
      expect(calls.last.arguments, [Permission.storage.value]);
    });
  }
  for (final int sdk in <int>[33, 34, 35, 36]) {
    test(
      'API $sdk reads each media status; never requests legacy/all-files',
      () async {
        final PermissionGateway gateway = PermissionGateway(
          isAndroid: true,
          androidSdk: () async => sdk,
        );
        actual[Permission.photos.value] = sdk >= 34 ? 3 : 1;
        actual[Permission.videos.value] = 4;
        actual[Permission.audio.value] = 2;
        final snapshot = await gateway.readPermissions();
        expect(
          snapshot.statusOf(PermissionKind.photos),
          sdk >= 34 ? AppPermissionStatus.limited : AppPermissionStatus.granted,
        );
        expect(
          snapshot.statusOf(PermissionKind.videos),
          AppPermissionStatus.permanentlyDenied,
        );
        expect(
          snapshot.statusOf(PermissionKind.audio),
          AppPermissionStatus.restricted,
        );
        expect(
          snapshot.statusOf(PermissionKind.storage),
          AppPermissionStatus.denied,
        );
        await gateway.requestPermissions({
          PermissionKind.storage,
          PermissionKind.photos,
        });
        expect(calls.last.arguments, [Permission.photos.value]);
        expect(
          calls
              .where((call) => call.method == 'checkPermissionStatus')
              .map((call) => call.arguments),
          [
            Permission.photos.value,
            Permission.videos.value,
            Permission.audio.value,
          ],
        );
      },
    );
  }
  test(
    'every read reaches Android instead of trusting the preceding result',
    () async {
      final PermissionGateway gateway = PermissionGateway(
        isAndroid: true,
        androidSdk: () async => 34,
      );
      actual[Permission.photos.value] = 1;
      expect(
        (await gateway.readPermissions()).allowsFeature(
          PermissionFeature.photos,
        ),
        isTrue,
      );
      actual[Permission.photos.value] = 0;
      expect(
        (await gateway.readPermissions()).allowsFeature(
          PermissionFeature.photos,
        ),
        isFalse,
      );
      expect(
        calls.where((call) => call.method == 'requestPermissions'),
        isEmpty,
      );
    },
  );
  test('empty requests launch no native permission dialog', () async {
    final PermissionGateway gateway = PermissionGateway(
      isAndroid: true,
      androidSdk: () async => 34,
    );
    await gateway.requestPermissions({});
    expect(calls, isEmpty);
  });
}
