import 'package:flutter/services.dart';

/// Opens Android's system share chooser for a cleanup summary.
///
/// Returning false lets the UI fall back to copying the summary on platforms
/// where the native chooser is unavailable, including widget tests.
class CleanupShareService {
  CleanupShareService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.mobilecleaner.app/share';

  final MethodChannel _channel;

  Future<bool> shareCleanupSummary(String summary) async {
    if (summary.trim().isEmpty) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('shareText', <String, String>{
            'subject': 'My Mobile Cleaner result',
            'text': summary,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
