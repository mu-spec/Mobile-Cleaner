import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Cleanup opportunity categories that are already produced by Smart Scan.
///
/// Their declaration order is also the allocation order for a file matched by
/// several analyzers: the most specific and safest classification wins.
enum CleanupOpportunityKind {
  exactDuplicates,
  apkInstallers,
  oldDownloads,
  oldScreenshots,
  largeVideos,
  largeFiles,
}

extension CleanupOpportunityKindLabel on CleanupOpportunityKind {
  String get label => switch (this) {
    CleanupOpportunityKind.exactDuplicates => 'Duplicates',
    CleanupOpportunityKind.apkInstallers => 'APK installers',
    CleanupOpportunityKind.oldDownloads => 'Old downloads',
    CleanupOpportunityKind.oldScreenshots => 'Screenshots',
    CleanupOpportunityKind.largeVideos => 'Large videos',
    CleanupOpportunityKind.largeFiles => 'Large files',
  };
}

/// One analyzer's real file-level findings.
class CleanupOpportunity {
  const CleanupOpportunity({required this.kind, required this.files});

  final CleanupOpportunityKind kind;
  final List<ScannedFile> files;
}

/// A completed Smart Scan snapshot used by both scoring and recommendations.
class CleanupScanSnapshot {
  const CleanupScanSnapshot({
    required this.totalStorageBytes,
    required this.opportunities,
    required this.scannedAt,
  });

  final int totalStorageBytes;
  final List<CleanupOpportunity> opportunities;
  final DateTime scannedAt;
}

enum CleanupScoreLabel {
  excellent('Excellent'),
  good('Good'),
  needsAttention('Needs Attention'),
  cleanupRecommended('Cleanup Recommended');

  const CleanupScoreLabel(this.label);

  final String label;

  static CleanupScoreLabel fromScore(int score) {
    if (score >= CleanupScoreCalculator.excellentMinimum) {
      return CleanupScoreLabel.excellent;
    }
    if (score >= CleanupScoreCalculator.goodMinimum) {
      return CleanupScoreLabel.good;
    }
    if (score >= CleanupScoreCalculator.needsAttentionMinimum) {
      return CleanupScoreLabel.needsAttention;
    }
    return CleanupScoreLabel.cleanupRecommended;
  }
}

/// One non-overlapping line in the explanation shown to the user.
class CleanupScoreBreakdown {
  const CleanupScoreBreakdown({
    required this.kind,
    required this.files,
    required this.bytes,
  });

  final CleanupOpportunityKind kind;
  final List<ScannedFile> files;
  final int bytes;

  String get label => kind.label;
  int get itemCount => files.length;
}

/// The explainable result of evaluating one completed scan snapshot.
class CleanupScore {
  const CleanupScore({
    required this.value,
    required this.label,
    required this.opportunityBytes,
    required this.weightedOpportunityBytes,
    required this.breakdown,
  });

  final int value;
  final CleanupScoreLabel label;

  /// Distinct bytes the user can review, with each URI counted once.
  final int opportunityBytes;

  /// Confidence-weighted bytes used only by the score formula.
  final int weightedOpportunityBytes;
  final List<CleanupScoreBreakdown> breakdown;

  int get opportunityCount => breakdown.fold<int>(
    0,
    (int total, CleanupScoreBreakdown item) => total + item.itemCount,
  );
}

/// Deterministically grades cleanup opportunities from 0 to 100.
///
/// Formula:
///
/// * weighted space penalty: up to 75 points, based on confidence-weighted
///   opportunity bytes as a fraction of total storage;
/// * meaningful-category penalty: 3 points per category, capped at 15;
/// * item-volume penalty: 0, 1, 3, 6, or 10 points by finding count.
///
/// A high-confidence exact duplicate affects the score more than a personal
/// large file of the same size. This rewards clear cleanup wins without ever
/// pretending that every large personal file is safe to remove.
abstract final class CleanupScoreCalculator {
  static const int excellentMinimum = 90;
  static const int goodMinimum = 75;
  static const int needsAttentionMinimum = 50;

  static const int _mib = 1024 * 1024;
  static const int _minimumMeaningfulBytes = 10 * _mib;
  static const int _spacePenaltyScale = 800;
  static const int _maximumSpacePenalty = 75;
  static const int _maximumCategoryPenalty = 15;

  static const Map<CleanupOpportunityKind, int> confidencePermille =
      <CleanupOpportunityKind, int>{
        CleanupOpportunityKind.exactDuplicates: 1000,
        CleanupOpportunityKind.apkInstallers: 900,
        CleanupOpportunityKind.oldDownloads: 700,
        CleanupOpportunityKind.oldScreenshots: 650,
        CleanupOpportunityKind.largeVideos: 450,
        CleanupOpportunityKind.largeFiles: 350,
      };

  static CleanupScore calculate(CleanupScanSnapshot snapshot) {
    final Set<String> globallyAllocated = <String>{};
    final List<CleanupScoreBreakdown> breakdown = <CleanupScoreBreakdown>[];
    int weightedBytes = 0;

    for (final CleanupOpportunityKind kind in CleanupOpportunityKind.values) {
      final Set<String> withinCategory = <String>{};
      final List<ScannedFile> allocated = <ScannedFile>[];

      for (final CleanupOpportunity opportunity in snapshot.opportunities) {
        if (opportunity.kind != kind) {
          continue;
        }
        for (final ScannedFile file in opportunity.files) {
          final String identity = _identityOf(file);
          if (!withinCategory.add(identity) ||
              !globallyAllocated.add(identity)) {
            continue;
          }
          allocated.add(file);
        }
      }

      if (allocated.isEmpty) {
        continue;
      }
      allocated.sort(
        (ScannedFile a, ScannedFile b) => b.sizeBytes.compareTo(a.sizeBytes),
      );
      final int bytes = allocated.fold<int>(
        0,
        (int sum, ScannedFile file) => sum + file.sizeBytes,
      );
      weightedBytes += (bytes * (confidencePermille[kind] ?? 0) / 1000).round();
      breakdown.add(
        CleanupScoreBreakdown(
          kind: kind,
          files: List<ScannedFile>.unmodifiable(allocated),
          bytes: bytes,
        ),
      );
    }

    breakdown.sort((CleanupScoreBreakdown a, CleanupScoreBreakdown b) {
      final int byBytes = b.bytes.compareTo(a.bytes);
      return byBytes != 0 ? byBytes : a.kind.index.compareTo(b.kind.index);
    });

    final int opportunityBytes = breakdown.fold<int>(
      0,
      (int sum, CleanupScoreBreakdown item) => sum + item.bytes,
    );
    final int itemCount = breakdown.fold<int>(
      0,
      (int sum, CleanupScoreBreakdown item) => sum + item.itemCount,
    );
    final int meaningfulFloor = _meaningfulFloor(snapshot.totalStorageBytes);
    final int meaningfulCategories = breakdown
        .where((CleanupScoreBreakdown item) => item.bytes >= meaningfulFloor)
        .length;

    final int spacePenalty = _spacePenalty(
      weightedBytes: weightedBytes,
      totalStorageBytes: snapshot.totalStorageBytes,
    );
    final int categoryPenalty = (meaningfulCategories * 3).clamp(
      0,
      _maximumCategoryPenalty,
    );
    final int itemPenalty = _itemPenalty(itemCount);
    final int value = (100 - spacePenalty - categoryPenalty - itemPenalty)
        .clamp(0, 100);

    return CleanupScore(
      value: value,
      label: CleanupScoreLabel.fromScore(value),
      opportunityBytes: opportunityBytes,
      weightedOpportunityBytes: weightedBytes,
      breakdown: List<CleanupScoreBreakdown>.unmodifiable(breakdown),
    );
  }

  static int _spacePenalty({
    required int weightedBytes,
    required int totalStorageBytes,
  }) {
    if (weightedBytes <= 0) {
      return 0;
    }
    if (totalStorageBytes <= 0) {
      return _maximumSpacePenalty;
    }
    return (weightedBytes * _spacePenaltyScale / totalStorageBytes)
        .round()
        .clamp(0, _maximumSpacePenalty);
  }

  static int _meaningfulFloor(int totalStorageBytes) {
    final int relativeFloor = totalStorageBytes > 0
        ? totalStorageBytes ~/ 2000
        : 0;
    return relativeFloor > _minimumMeaningfulBytes
        ? relativeFloor
        : _minimumMeaningfulBytes;
  }

  static int _itemPenalty(int count) {
    if (count == 0) {
      return 0;
    }
    if (count <= 4) {
      return 1;
    }
    if (count <= 19) {
      return 3;
    }
    if (count <= 99) {
      return 6;
    }
    return 10;
  }

  static String _identityOf(ScannedFile file) {
    if (file.uri.isNotEmpty) {
      return file.uri;
    }
    if (file.path.isNotEmpty) {
      return file.path;
    }
    return '${file.id}:${file.name}:${file.sizeBytes}';
  }
}
