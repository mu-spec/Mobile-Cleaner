import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';

/// Turns scan findings into advice, using fixed rules.
///
/// ## Deliberately not AI
///
/// Every rule is an explicit threshold comparison. That is a feature, not a
/// placeholder: the user can be told exactly why a suggestion appeared
/// ("34 screenshots older than 90 days"), the behaviour is identical on every
/// device, and it is fully testable. A model that guessed at this would be
/// slower, unpredictable, and impossible to justify to someone deciding
/// whether to delete their photos.
///
/// ## Advice only
///
/// The engine returns text and a destination. It never selects, never deletes,
/// and never changes state. Acting on a recommendation just opens the tool
/// that owns it, where the normal review-and-confirm flow applies.
abstract final class RecommendationEngine {
  /// A screenshot older than this counts as stale.
  static const int screenshotAgeDays = 90;

  /// Fire the screenshot rule above this many stale screenshots.
  static const int screenshotCountThreshold = 20;

  /// Fire the duplicate rule above this much reclaimable space.
  static const int duplicateBytesThreshold = 500 * 1024 * 1024;

  /// A video at or above this is "large".
  static const int largeVideoBytes = 1024 * 1024 * 1024;

  /// Above this much recoverable space, a recommendation is high priority.
  static const int highPriorityBytes = 1024 * 1024 * 1024;

  /// Evaluates every rule against [inputs], strongest advice first.
  ///
  /// An empty list is a valid, meaningful result: it means nothing crossed a
  /// threshold, and Home says the device looks fine rather than inventing
  /// something to suggest.
  static List<Recommendation> evaluate(RecommendationInputs inputs) {
    final List<Recommendation> found = <Recommendation>[
      ..._screenshotRule(inputs),
      ..._duplicateRule(inputs),
      ..._largeVideoRule(inputs),
    ];

    // Highest priority first, then biggest saving, then a stable tiebreak on
    // rule identity so the order never shuffles between rebuilds.
    found.sort((Recommendation a, Recommendation b) {
      final int byPriority = a.priority.index.compareTo(b.priority.index);
      if (byPriority != 0) {
        return byPriority;
      }
      final int bySize = b.reclaimableBytes.compareTo(a.reclaimableBytes);
      if (bySize != 0) {
        return bySize;
      }
      return a.kind.index.compareTo(b.kind.index);
    });

    return List<Recommendation>.unmodifiable(found);
  }

  /// `IF screenshots older than 90 days > 20` → recommend screenshot review.
  ///
  /// Strictly greater than, matching the rule as written: exactly 20 does not
  /// fire.
  static Iterable<Recommendation> _screenshotRule(
    RecommendationInputs inputs,
  ) sync* {
    if (inputs.oldScreenshotCount <= screenshotCountThreshold) {
      return;
    }

    yield Recommendation(
      kind: RecommendationKind.screenshotReview,
      priority: _priorityFor(inputs.oldScreenshotBytes),
      title: 'Review old screenshots',
      detail:
          '${inputs.oldScreenshotCount} screenshots older than '
          '$screenshotAgeDays days · '
          '${ByteFormatter.format(inputs.oldScreenshotBytes)}',
      actionLabel: 'Review screenshots',
      reclaimableBytes: inputs.oldScreenshotBytes,
      itemCount: inputs.oldScreenshotCount,
    );
  }

  /// `IF duplicate storage > 500 MB` → recommend duplicate cleanup.
  ///
  /// Measured on *reclaimable* space, not total occupied: one copy of every
  /// set is always kept, so the space every copy occupies is not what the user
  /// would get back.
  static Iterable<Recommendation> _duplicateRule(
    RecommendationInputs inputs,
  ) sync* {
    if (inputs.duplicateReclaimableBytes <= duplicateBytesThreshold) {
      return;
    }

    final int groups = inputs.duplicateGroupCount;
    yield Recommendation(
      kind: RecommendationKind.duplicateCleanup,
      priority: _priorityFor(inputs.duplicateReclaimableBytes),
      title: 'Clean up duplicates',
      detail:
          '${ByteFormatter.format(inputs.duplicateReclaimableBytes)} '
          'recoverable across $groups ${groups == 1 ? 'set' : 'sets'} · '
          'one copy of each is always kept',
      actionLabel: 'Review duplicates',
      reclaimableBytes: inputs.duplicateReclaimableBytes,
      itemCount: groups,
    );
  }

  /// `IF one video > 1 GB` → recommend large video review.
  ///
  /// Fires on a single video crossing the bar, so one enormous file is caught
  /// even on a device with no other clutter.
  static Iterable<Recommendation> _largeVideoRule(
    RecommendationInputs inputs,
  ) sync* {
    final ScannedFile? biggest = inputs.largestVideo;
    if (biggest == null || biggest.sizeBytes < largeVideoBytes) {
      return;
    }

    final int others = inputs.largeVideoCount - 1;
    final String detail = others > 0
        ? '${biggest.name} is '
              '${ByteFormatter.format(biggest.sizeBytes)} · '
              '$others other ${others == 1 ? 'video' : 'videos'} over 1 GB'
        : '${biggest.name} is ${ByteFormatter.format(biggest.sizeBytes)}';

    yield Recommendation(
      kind: RecommendationKind.largeVideoReview,
      priority: _priorityFor(inputs.largeVideoBytes),
      title: 'Review large videos',
      detail: detail,
      actionLabel: 'Review videos',
      // The whole set of large videos, not just the one that tripped the rule.
      reclaimableBytes: inputs.largeVideoBytes,
      itemCount: inputs.largeVideoCount,
    );
  }

  static RecommendationPriority _priorityFor(int bytes) =>
      bytes >= highPriorityBytes
      ? RecommendationPriority.high
      : RecommendationPriority.medium;
}
