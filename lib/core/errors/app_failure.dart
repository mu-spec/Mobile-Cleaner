import 'package:flutter/services.dart';

/// The problems this app can actually hit, classified.
///
/// Everything the user might see is mapped onto one of these, so each failure
/// gets wording and an action that fit the real cause — rather than one
/// generic "something went wrong" that leaves them with nothing to do.
enum FailureKind {
  /// Storage or media permission was refused or revoked.
  permissionDenied,

  /// The file is no longer where the scan found it.
  missingFile,

  /// Android refused to remove a file.
  deleteFailed,

  /// Storage info could not be read.
  storageUnavailable,

  /// The work was abandoned — the user left, or backed out of a dialog.
  cancelled,

  /// A capability this build's native side does not provide.
  unsupported,

  /// Anything genuinely unexpected.
  unknown,
}

/// A classified problem, ready to show.
class AppFailure {
  const AppFailure({
    required this.kind,
    required this.message,
    this.action,
    this.technicalDetail,
  });

  final FailureKind kind;

  /// One plain sentence describing what happened, in the user's terms.
  final String message;

  /// What the user can do about it, when there is something.
  final String? action;

  /// The raw platform code or exception text, for a bug report.
  ///
  /// Shown in small print rather than hidden: the Android 11 scan bug went
  /// undiagnosed for phases because the error screen showed a headline and
  /// nothing else.
  final String? technicalDetail;

  /// True when retrying could plausibly work.
  ///
  /// A permission problem is not retryable until the permission changes, and
  /// an unsupported capability never becomes available, so neither offers a
  /// bare "Try again" that would just fail identically.
  bool get isRetryable =>
      kind != FailureKind.permissionDenied && kind != FailureKind.unsupported;

  /// True when the fix is in system settings rather than in this app.
  bool get needsPermission => kind == FailureKind.permissionDenied;

  /// Classifies any thrown object.
  ///
  /// Never throws itself, and always returns something showable — an
  /// unrecognised error becomes [FailureKind.unknown] with its own text
  /// attached rather than being swallowed.
  static AppFailure from(Object error) {
    if (error is AppFailure) {
      return error;
    }
    if (error is MissingPluginException) {
      return AppFailure(
        kind: FailureKind.unsupported,
        message: 'This feature is not available on this device.',
        technicalDetail: error.message,
      );
    }
    if (error is PlatformException) {
      return _fromPlatform(error);
    }
    return AppFailure(
      kind: FailureKind.unknown,
      message: 'Something went wrong.',
      action: 'Try again',
      technicalDetail: '${error.runtimeType}: $error',
    );
  }

  static AppFailure _fromPlatform(PlatformException error) {
    final String code = error.code.toUpperCase();
    final String detail = <String>[
      error.code,
      error.message ?? '',
      error.details is String ? error.details as String : '',
    ].where((String part) => part.isNotEmpty).join(' — ');

    // Matched on the code rather than by searching the message, so a change
    // of wording cannot silently reclassify a failure.
    if (code.contains('PERMISSION') || code.contains('DENIED')) {
      return AppFailure(
        kind: FailureKind.permissionDenied,
        message: 'Mobile Cleaner needs access to your files to continue.',
        action: 'Review permissions',
        technicalDetail: detail,
      );
    }
    if (code.contains('NOT_FOUND') || code.contains('MISSING')) {
      return AppFailure(
        kind: FailureKind.missingFile,
        message: 'That file is no longer on this device.',
        action: 'Rescan',
        technicalDetail: detail,
      );
    }
    if (code.contains('CANCEL')) {
      return AppFailure(
        kind: FailureKind.cancelled,
        message: 'That was cancelled. Nothing was changed.',
        technicalDetail: detail,
      );
    }
    if (code.contains('STORAGE_UNAVAILABLE') ||
        code.contains('INVALID_STORAGE')) {
      return AppFailure(
        kind: FailureKind.storageUnavailable,
        message: 'Android did not report this device\u2019s storage.',
        action: 'Try again',
        technicalDetail: detail,
      );
    }
    if (code.contains('DELETE')) {
      return AppFailure(
        kind: FailureKind.deleteFailed,
        message: 'Those files could not be removed.',
        action: 'Try again',
        technicalDetail: detail,
      );
    }
    if (code.contains('UNAVAILABLE') || code.contains('NO_ACTIVITY')) {
      return AppFailure(
        kind: FailureKind.unsupported,
        message: 'This feature is not available on this device.',
        technicalDetail: detail,
      );
    }

    return AppFailure(
      kind: FailureKind.unknown,
      // The platform message is usually the most useful thing available.
      message: error.message?.isNotEmpty == true
          ? error.message!
          : 'Something went wrong.',
      action: 'Try again',
      technicalDetail: detail,
    );
  }
}
