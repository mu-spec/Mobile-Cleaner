import 'package:flutter/services.dart';

/// Centralised haptic feedback.
///
/// Wrapped rather than called directly so that intensity is consistent across
/// the app, and so a single place decides what deserves a buzz. Over-using
/// haptics is worse than having none — a phone that vibrates on every tap is
/// annoying, so these are reserved for moments that change state.
///
/// Every call is fire-and-forget and swallows failures: a device with no
/// vibrator, or one where the user has disabled haptics, must never turn a
/// working action into an error.
abstract final class Haptics {
  /// A file was selected or deselected.
  ///
  /// The lightest tap available, because selection happens repeatedly.
  static void selection() => _run(HapticFeedback.selectionClick);

  /// A meaningful state change: a filter switched, a keeper chosen.
  static void light() => _run(HapticFeedback.lightImpact);

  /// A destructive action was confirmed.
  ///
  /// Heavier deliberately: deleting is irreversible, and the extra weight is
  /// a physical cue that this one mattered.
  static void warning() => _run(HapticFeedback.mediumImpact);

  /// An action completed successfully.
  static void success() => _run(HapticFeedback.mediumImpact);

  static void _run(Future<void> Function() action) {
    // Not awaited: haptics must never delay the frame that triggered them.
    action().catchError((Object _) {});
  }
}
