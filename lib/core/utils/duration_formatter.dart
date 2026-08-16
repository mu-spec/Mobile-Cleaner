/// Shared human-readable playback-length formatting.
abstract final class DurationFormatter {
  /// Shown when a video's length is unknown.
  ///
  /// Deliberately not `0:00`, which would claim the video is empty rather than
  /// admitting the length was never resolved.
  static const String unknown = '--:--';

  /// Formats a clip length as `0:42`, `4:07`, or `1:12:05`.
  ///
  /// The hours field appears only when there is one, so a short clip is not
  /// padded out to `0:04:07`.
  static String format(Duration? duration) {
    if (duration == null || duration <= Duration.zero) {
      return unknown;
    }

    final int totalSeconds = duration.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    final String paddedSeconds = seconds.toString().padLeft(2, '0');
    if (hours == 0) {
      return '$minutes:$paddedSeconds';
    }
    return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
  }

  /// Formats a combined length in words, e.g. `3 hr 12 min` or `45 min`.
  ///
  /// Used for totals, where `12:07:33` reads as a timestamp rather than as an
  /// amount of footage.
  static String formatLong(Duration? duration) {
    if (duration == null || duration <= Duration.zero) {
      return '0 min';
    }

    final int hours = duration.inHours;
    final int minutes = duration.inMinutes % 60;

    if (hours == 0) {
      // Round a sub-minute total up, so a real clip is never "0 min".
      final int shown = minutes == 0 ? 1 : minutes;
      return '$shown min';
    }
    if (minutes == 0) {
      return '$hours hr';
    }
    return '$hours hr $minutes min';
  }
}
