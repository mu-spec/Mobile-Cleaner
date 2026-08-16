import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_summary.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_summary.dart';
import 'package:mobile_cleaner/features/files/domain/similar_photo_group.dart';

/// The photo tools listed on the Photos tab, in display order.
enum PhotoCleanupTool {
  duplicatePhotos('Duplicate Photos', 'Identical copies of the same picture'),
  screenshots('Screenshots', 'Captures you no longer need'),
  largePhotos('Large Photos', 'The images taking the most space'),
  similarPhotos('Similar Photos', 'Near-identical shots of the same scene');

  const PhotoCleanupTool(this.label, this.description);

  final String label;
  final String description;

  /// True when the tool is built and can be opened.
  ///
  /// Every photo tool is now built. Kept as a concept so a future tool can be
  /// listed as upcoming without reworking the dashboard.
  bool get isAvailable => true;
}

/// One row of the Photo Cleanup dashboard.
class PhotoCleanupEntry {
  const PhotoCleanupEntry({
    required this.tool,
    required this.bytes,
    required this.itemCount,
    this.files = const <ScannedFile>[],
  });

  /// A tool that has not run, or cannot run yet.
  const PhotoCleanupEntry.pending(this.tool)
    : bytes = 0,
      itemCount = 0,
      files = const <ScannedFile>[];

  final PhotoCleanupTool tool;

  /// Space this tool could recover.
  ///
  /// For duplicates this is the *reclaimable* figure — one copy of each set is
  /// always kept — not the space every copy occupies.
  final int bytes;

  /// How many photos the figure covers.
  final int itemCount;

  /// The photos counted, used only to de-duplicate the headline total.
  final List<ScannedFile> files;

  /// True when the tool ran and found nothing worth showing.
  bool get isEmpty => itemCount == 0;

  /// True when there is a real figure to show rather than an action label.
  bool get hasFigure => tool.isAvailable;

  /// True when the figure is an upper bound rather than a firm total.
  ///
  /// Similar shots differ, so what is actually freed depends on which the user
  /// keeps. The UI prefixes this with "up to".
  bool get isEstimate => tool == PhotoCleanupTool.similarPhotos;
}

/// Everything the Photos tab needs to draw itself.
///
/// Composed from the existing tool providers, so the dashboard and the tools
/// can never disagree.
class PhotoCleanupSummary {
  const PhotoCleanupSummary({required this.entries});

  /// Builds the dashboard from each tool's own result.
  factory PhotoCleanupSummary.from({
    required DuplicateScanResult duplicates,
    required ScreenshotSummary screenshots,
    required LargePhotoSummary largePhotos,
    SimilarPhotoScanResult similarPhotos = SimilarPhotoScanResult.empty,
  }) {
    return PhotoCleanupSummary(
      entries: <PhotoCleanupEntry>[
        PhotoCleanupEntry(
          tool: PhotoCleanupTool.duplicatePhotos,
          // Keeping one copy of every set is the rule the tool enforces, so
          // the dashboard must promise the same number the tool can deliver.
          bytes: duplicates.reclaimableBytes,
          itemCount: duplicates.duplicateCount,
          files: duplicates.allDuplicates,
        ),
        PhotoCleanupEntry(
          tool: PhotoCleanupTool.screenshots,
          bytes: screenshots.totalBytes,
          itemCount: screenshots.fileCount,
          files: screenshots.files,
        ),
        PhotoCleanupEntry(
          tool: PhotoCleanupTool.largePhotos,
          bytes: largePhotos.totalBytes,
          itemCount: largePhotos.fileCount,
          files: largePhotos.files,
        ),
        PhotoCleanupEntry(
          tool: PhotoCleanupTool.similarPhotos,
          // An upper bound: keeping the best shot of each set. Phrased as
          // "up to" in the UI, because which shot the user keeps changes it.
          bytes: similarPhotos.reclaimableBytes,
          itemCount: similarPhotos.extraPhotoCount,
          // Deliberately not contributed to the headline. Similar photos are
          // not interchangeable, so counting them as recoverable would promise
          // space the user may well decide not to free.
          files: const <ScannedFile>[],
        ),
      ],
    );
  }

  /// One entry per tool, in [PhotoCleanupTool] order.
  final List<PhotoCleanupEntry> entries;

  PhotoCleanupEntry entryFor(PhotoCleanupTool tool) => entries.firstWhere(
    (PhotoCleanupEntry entry) => entry.tool == tool,
    orElse: () => PhotoCleanupEntry.pending(tool),
  );

  /// Every photo the dashboard counted, listed once.
  ///
  /// The tools overlap by design: a 12 MB screenshot duplicated twice is a
  /// screenshot, a large photo, and a duplicate. Each row reports its own
  /// figure, but the headline must not count that photo three times.
  List<ScannedFile> get uniqueFiles {
    final Set<String> seen = <String>{};
    final List<ScannedFile> files = <ScannedFile>[];
    for (final PhotoCleanupEntry entry in entries) {
      for (final ScannedFile file in entry.files) {
        if (seen.add(file.uri)) {
          files.add(file);
        }
      }
    }
    return List<ScannedFile>.unmodifiable(files);
  }

  /// Recoverable space, counting each photo once.
  ///
  /// Deliberately not the sum of the rows, which would overstate the figure
  /// wherever the tools overlap.
  int get totalBytes => uniqueFiles.fold<int>(
    0,
    (int sum, ScannedFile file) => sum + file.sizeBytes,
  );

  int get totalPhotos => uniqueFiles.length;

  bool get isEmpty => totalPhotos == 0;

  /// True when at least one photo was counted by more than one tool.
  bool get hasOverlap {
    final int summed = entries.fold<int>(
      0,
      (int sum, PhotoCleanupEntry entry) => sum + entry.files.length,
    );
    return summed > totalPhotos;
  }

  /// Available tools that found something, biggest first.
  List<PhotoCleanupEntry> get rankedFindings {
    final List<PhotoCleanupEntry> found = entries
        .where(
          (PhotoCleanupEntry entry) => entry.hasFigure && !entry.isEmpty,
        )
        .toList()
      ..sort(
        (PhotoCleanupEntry a, PhotoCleanupEntry b) =>
            b.bytes.compareTo(a.bytes),
      );
    return found;
  }
}
