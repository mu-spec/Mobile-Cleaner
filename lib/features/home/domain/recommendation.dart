import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// The kinds of advice Home can give.
///
/// One value per rule, so a rule can be found, tested, and routed by identity
/// rather than by matching on its wording.
enum RecommendationKind {
  duplicateCleanup,
  apkInstallerReview,
  oldDownloadReview,
  screenshotReview,
  largeFileReview,
  largeVideoReview,
}

/// How strongly a recommendation is worth acting on.
///
/// Used only for ordering, never to auto-act. Nothing on Home deletes.
enum RecommendationPriority {
  /// A large, clear-cut win.
  high,

  /// Worth a look.
  medium,
}

/// One piece of advice, ready to render.
class Recommendation {
  const Recommendation({
    required this.kind,
    required this.priority,
    required this.title,
    required this.detail,
    required this.actionLabel,
    this.reclaimableBytes = 0,
    this.itemCount = 0,
  });

  final RecommendationKind kind;
  final RecommendationPriority priority;

  /// Short headline, e.g. `Review old screenshots`.
  final String title;

  /// The evidence, e.g. `34 screenshots older than 90 days · 210 MB`.
  ///
  /// Always states the numbers the rule fired on, so the advice is checkable
  /// rather than something the user has to take on trust.
  final String detail;

  final String actionLabel;

  /// Space this recommendation could recover. Zero when not size-driven.
  ///
  /// Used for ordering within a priority band, so the biggest win leads.
  final int reclaimableBytes;

  /// How many items the rule matched.
  final int itemCount;
}

/// The inputs a rule can read.
///
/// A plain data holder rather than a set of providers, so
/// [RecommendationEngine] stays pure and every rule is testable without a
/// device, a scan, or a widget.
class RecommendationInputs {
  const RecommendationInputs({
    this.oldScreenshotCount = 0,
    this.oldScreenshotBytes = 0,
    this.duplicateReclaimableBytes = 0,
    this.duplicateGroupCount = 0,
    this.largestVideo,
    this.largeVideoCount = 0,
    this.largeVideoBytes = 0,
    this.largeFileCount = 0,
    this.largeFileBytes = 0,
    this.oldDownloadCount = 0,
    this.oldDownloadBytes = 0,
    this.apkInstallerCount = 0,
    this.apkInstallerBytes = 0,
  });

  /// Screenshots older than [RecommendationEngine.screenshotAgeDays].
  final int oldScreenshotCount;
  final int oldScreenshotBytes;

  /// Space recoverable by removing duplicate copies, keeping one of each.
  final int duplicateReclaimableBytes;
  final int duplicateGroupCount;

  /// The single biggest video, when there is one.
  final ScannedFile? largestVideo;

  /// Videos at or above [RecommendationEngine.largeVideoBytes].
  final int largeVideoCount;

  /// Combined size of those videos.
  final int largeVideoBytes;

  /// Files matched by Smart Scan's existing 100 MB+ large-file analyzer.
  final int largeFileCount;
  final int largeFileBytes;

  /// Downloads untouched for the configured default age (currently 30 days).
  final int oldDownloadCount;
  final int oldDownloadBytes;

  /// Installer packages found by Smart Scan's existing APK analyzer.
  final int apkInstallerCount;
  final int apkInstallerBytes;
}
