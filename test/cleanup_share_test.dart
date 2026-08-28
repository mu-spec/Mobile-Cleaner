import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/cleanup_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('test/cleanup-share');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('opens the native chooser with the cleanup summary', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          received = call;
          return true;
        });

    final bool opened = await CleanupShareService(channel: channel)
        .shareCleanupSummary('Freed 3.6 GB');

    expect(opened, isTrue);
    expect(received?.method, 'shareText');
    expect(received?.arguments, <String, String>{
      'subject': 'My Mobile Cleaner result',
      'text': 'Freed 3.6 GB',
    });
  });

  test('falls back safely when Android sharing is unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'SHARE_UNAVAILABLE');
        });

    final bool opened = await CleanupShareService(channel: channel)
        .shareCleanupSummary('Freed 3.6 GB');

    expect(opened, isFalse);
  });

  test('does not open a chooser for an empty summary', () async {
    int calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls++;
          return true;
        });

    final bool opened = await CleanupShareService(channel: channel)
        .shareCleanupSummary('   ');

    expect(opened, isFalse);
    expect(calls, 0);
  });
}
