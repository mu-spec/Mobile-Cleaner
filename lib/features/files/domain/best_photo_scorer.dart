import 'package:mobile_cleaner/features/files/domain/photo_quality.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Why one photo was suggested over the others in its group.
enum BestPhotoReason {
  sharpest('Sharpest shot'),
  highestResolution('Highest resolution'),
  bestOverall('Best overall'),

  /// The group's photos scored too closely to separate honestly.
  tooClose('Too close to call');

  const BestPhotoReason(this.label);

  final String label;
}

/// One photo's standing within its group.
class PhotoScore {
  const PhotoScore({
    required this.file,
    required this.quality,
    required this.sharpnessRatio,
    required this.resolutionRatio,
    required this.score,
  });

  final ScannedFile file;
  final PhotoQuality quality;

  /// Sharpness as a fraction of the group's sharpest, 0 to 1.
  final double sharpnessRatio;

  /// Pixel count as a fraction of the group's largest, 0 to 1.
  final double resolutionRatio;

  /// Weighted overall standing, 0 to 1.
  final double score;

  /// True when this photo is markedly softer than the group's best.
  ///
  /// Relative, never absolute: there is no universal Laplacian variance that
  /// means "blurred". A landscape and a plain wall differ by an order of
  /// magnitude at identical focus, so blur is only meaningful compared with
  /// another shot of the same scene — which is exactly what a similar-photo
  /// group provides.
  bool get looksBlurred =>
      sharpnessRatio < BestPhotoScorer.blurredBelowRatio;
}

/// The outcome of ranking one group.
class BestPhotoRecommendation {
  const BestPhotoRecommendation({
    required this.scores,
    required this.reason,
    this.suggested,
  });

  /// No usable measurements, so no opinion is offered.
  static const BestPhotoRecommendation none = BestPhotoRecommendation(
    scores: <PhotoScore>[],
    reason: BestPhotoReason.tooClose,
  );

  /// Every measured photo, best first.
  final List<PhotoScore> scores;

  /// The photo suggested for keeping, or null when the group is too close.
  ///
  /// Null is a real, expected outcome. A suggestion the tool cannot justify is
  /// worse than none: it would nudge the user into deleting a shot that was
  /// just as good.
  final ScannedFile? suggested;

  /// Why [suggested] was chosen, or [BestPhotoReason.tooClose].
  final BestPhotoReason reason;

  bool get hasSuggestion => suggested != null;

  /// Score for one file, or null when it could not be measured.
  PhotoScore? scoreFor(ScannedFile file) {
    for (final PhotoScore score in scores) {
      if (score.file.uri == file.uri) {
        return score;
      }
    }
    return null;
  }

  /// True when [file] is the suggested keeper.
  bool isSuggested(ScannedFile file) => suggested?.uri == file.uri;
}

/// Ranks the photos of a similar group and suggests one to keep.
///
/// ## This never deletes and never selects
///
/// The output is a label and an ordering. It does not touch the selection, it
/// does not change which photo is protected, and it cannot start a delete. The
/// user still chooses, and the shared "one photo is always kept" rule is
/// unaffected. A recommendation is advice, not an action.
///
/// ## Scores are relative to the group, never absolute
///
/// Laplacian variance depends on scene content as much as focus, so there is
/// no threshold that means "sharp" across a whole library. Every ratio here is
/// against the best photo *in the same group* — photos of the same scene, which
/// is the only case where the comparison is fair.
abstract final class BestPhotoScorer {
  /// Weight of sharpness in the overall score.
  ///
  /// Dominant because it is the factor a person actually notices. Between two
  /// shots of the same scene, the sharp one is the keeper even if it is
  /// slightly smaller.
  static const double sharpnessWeight = 0.65;

  /// Weight of resolution.
  static const double resolutionWeight = 0.35;

  /// Below this fraction of the group's sharpest, a photo is called soft.
  static const double blurredBelowRatio = 0.55;

  /// How far ahead the leader must be before a suggestion is made.
  ///
  /// Without a margin the scorer would confidently recommend a photo that beat
  /// the runner-up by a rounding error. Below this, it says so instead.
  static const double minimumLead = 0.08;

  /// A lead this large in sharpness alone justifies the "Sharpest" label.
  static const double sharpnessLeadForLabel = 0.15;

  /// A lead this large in pixels alone justifies the "Highest resolution"
  /// label.
  static const double resolutionLeadForLabel = 0.15;

  /// Ranks [files] using [qualities], keyed by URI.
  ///
  /// Photos with no measurement are omitted from the ranking rather than
  /// scored as zero, which would falsely mark them as blurred.
  static BestPhotoRecommendation rank(
    List<ScannedFile> files,
    Map<String, PhotoQuality> qualities,
  ) {
    final List<ScannedFile> measured = <ScannedFile>[
      for (final ScannedFile file in files)
        if (qualities[file.uri] != null) file,
    ];
    if (measured.length < 2) {
      // One measured photo is not a comparison, so there is nothing to
      // recommend over anything else.
      return BestPhotoRecommendation.none;
    }

    double bestSharpness = 0;
    int bestPixels = 0;
    for (final ScannedFile file in measured) {
      final PhotoQuality quality = qualities[file.uri]!;
      if (quality.sharpness > bestSharpness) {
        bestSharpness = quality.sharpness;
      }
      if (quality.pixels > bestPixels) {
        bestPixels = quality.pixels;
      }
    }

    final List<PhotoScore> scores = <PhotoScore>[];
    for (final ScannedFile file in measured) {
      final PhotoQuality quality = qualities[file.uri]!;
      // A group where nothing could be measured falls back to 1, so the
      // factor simply drops out rather than dividing by zero.
      final double sharpnessRatio = bestSharpness > 0
          ? quality.sharpness / bestSharpness
          : 1;
      final double resolutionRatio = bestPixels > 0
          ? quality.pixels / bestPixels
          : 1;
      scores.add(
        PhotoScore(
          file: file,
          quality: quality,
          sharpnessRatio: sharpnessRatio,
          resolutionRatio: resolutionRatio,
          score:
              sharpnessRatio * sharpnessWeight +
              resolutionRatio * resolutionWeight,
        ),
      );
    }

    // Best first. Ties broken by URI so the order is stable across rebuilds
    // and a redraw can never silently change the recommendation.
    scores.sort((PhotoScore a, PhotoScore b) {
      final int byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.file.uri.compareTo(b.file.uri);
    });

    final PhotoScore leader = scores.first;
    final PhotoScore runnerUp = scores[1];
    final double lead = leader.score - runnerUp.score;

    if (lead < minimumLead) {
      // Honest silence. The photos are equally good as far as this can tell.
      return BestPhotoRecommendation(
        scores: List<PhotoScore>.unmodifiable(scores),
        reason: BestPhotoReason.tooClose,
      );
    }

    return BestPhotoRecommendation(
      scores: List<PhotoScore>.unmodifiable(scores),
      suggested: leader.file,
      reason: _reasonFor(leader, runnerUp),
    );
  }

  /// Names the factor that actually decided it, so the label is truthful.
  static BestPhotoReason _reasonFor(PhotoScore leader, PhotoScore runnerUp) {
    final double sharpnessLead =
        leader.sharpnessRatio - runnerUp.sharpnessRatio;
    final double resolutionLead =
        leader.resolutionRatio - runnerUp.resolutionRatio;

    final bool sharperOnly =
        sharpnessLead >= sharpnessLeadForLabel &&
        resolutionLead < resolutionLeadForLabel;
    final bool biggerOnly =
        resolutionLead >= resolutionLeadForLabel &&
        sharpnessLead < sharpnessLeadForLabel;

    if (sharperOnly) {
      return BestPhotoReason.sharpest;
    }
    if (biggerOnly) {
      return BestPhotoReason.highestResolution;
    }
    return BestPhotoReason.bestOverall;
  }
}
