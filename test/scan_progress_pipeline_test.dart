import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/features/files/data/file_scanner_channel.dart';
import 'package:phone_storage_cleaner/features/files/data/storage_access_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/screenshot_provider.dart';
import 'package:phone_storage_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:phone_storage_cleaner/features/permissions/domain/permission_snapshot.dart';

import 'support/permission_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const transport = MethodChannel('test/measured-scanner');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> emit(String request, int done, int? total) async {
    await messenger.handlePlatformMessage(
      NativeScanRequest.channel.name,
      codec.encodeMethodCall(
        MethodCall('progress', {
          'requestId': request,
          'stageIndex': 0,
          'sequence': done,
          'stage': 'Reading images',
          'processed': done,
          'total': total,
          'unit': 'rows checked',
          'numeric': true,
          'outcome': 'running',
        }),
      ),
      (_) {},
    );
  }

  for (final partial in [false, true]) {
    test(
      'native → permission-aware repository → summary → parent, partial=$partial',
      () async {
        final response = Completer<Map<String, Object>>();
        final invoked = Completer<String>();
        messenger.setMockMethodCallHandler(transport, (call) {
          final arguments = call.arguments as Map;
          expect(arguments['categories'], ['images']);
          invoked.complete(arguments['progressId'] as String);
          return response.future;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(transport, null));
        final permissions = FakePermissionGateway();
        permissions.statuses[PermissionKind.photos] =
            AppPermissionStatus.limited;
        final container = ProviderContainer(
          overrides: [
            permissionGatewayProvider.overrideWithValue(permissions),
            storageAccessRepositoryProvider.overrideWithValue(
              FakeFolderAccess(),
            ),
            fileScannerChannelProvider.overrideWithValue(
              MethodChannelFileScanner(channel: transport),
            ),
          ],
        );
        addTearDown(container.dispose);
        final parent = ScanOperation(numeric: true);
        final result = parent.run(
          () => container.read(
            screenshotSummaryProvider(ScreenshotGroup.defaultGroup).future,
          ),
        );
        final id = await invoked.future;
        await emit(id, 1, 4);
        expect(parent.snapshot.fraction, .25);
        await emit(id, 2, 4);
        expect(parent.snapshot.fraction, .5);
        await emit(id, 4, 4);
        expect(parent.snapshot.successful, isFalse);
        expect(parent.snapshot.fraction, .99);
        response.complete({
          'scanOutcome': partial ? 'partial' : 'succeeded',
          'scanPayload': {'files': <Object>[], 'durationMillis': 25},
        });
        final summary = await result;
        expect(summary.fileCount, 0);
        expect(parent.snapshot.successful, !partial);
        expect(parent.snapshot.fraction, partial ? .99 : 1);
        expect(permissions.requests, isEmpty);
        expect(
          permissions.statuses[PermissionKind.videos],
          AppPermissionStatus.denied,
        );
        // A queued message for the now-closed native request cannot mutate it.
        await emit(id, 0, 4);
        expect(parent.snapshot.fraction, 1);
      },
    );
  }
}
