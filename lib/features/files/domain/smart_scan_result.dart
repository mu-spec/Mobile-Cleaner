import 'package:mobile_cleaner/features/files/domain/apk_summary.dart';
import 'package:mobile_cleaner/features/files/domain/downloads_summary.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_summary.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// The three checks Smart Scan runs.
enum SmartScanCategory {
  largeFiles('Large Files', 'Files taking the most space'),
  oldDownloads('Old Downloads', 'Downloads you have not touched in a while'),
  apkInstallers('APK Installers', 'Setup files left after installing');

  const SmartScanCategory(this.label, this.description);

  final String label;
  final String description;
}

/// One check's findings.
class SmartScanGroup {
  const SmartScanGroup({
    required this.category,
    required this.files,
    required this.totalBytes,
  });

  factory SmartScanGroup.fromFiles(
    SmartScanCategory category,
    List<ScannedFile> files,
  ) {
    return SmartScanGroup(
      category: category,
      files: List<ScannedFile>.unmodifiable(files),
      totalBytes: files.fold<int>(
        0,
        (int sum, ScannedFile file) => sum + file.sizeBytes,
      ),
    );
  }

  final SmartScanCategory category;

  /// Files this check found, largest first.
  final List<ScannedFile> files;

  /// Combined size of [files] within this group alone.
  ///
  /// Groups can overlap, so these totals must not simply be added together.
  /// Use [SmartScanResult.totalBytes] for a headline figure.
  final int totalBytes;

  int get fileCount => files.length;

  bool get isEmpty => files.isEmpty;
}

/// Combined findings of one Smart Scan.
class SmartScanResult {
  const SmartScanResult({required this.groups, required this.scannedAt});

  /// Builds a result from the three tool summaries.
  ///
  /// The same file can legitimately satisfy more than one check — a 400 MB
  /// installer downloaded last year is a large file, an old download, and an
  /// APK. Each group lists it, because hiding it from a category the user is
  /// browsing would be confusing, but [uniqueFiles] and [totalBytes]
  /// de-duplicate by URI so the headline never double counts.
  factory SmartScanResult.from({
    required LargeFileSummary largeFiles,
    required DownloadsSummary oldDownloads,
    required ApkSummary apks,
    DateTime? scannedAt,
  }) {
    List<ScannedFile> sortedBySize(List<ScannedFile> source) {
      final List<ScannedFile> copy = List<ScannedFile>.of(source)
        ..sort(
          (ScannedFile a, ScannedFile b) => b.sizeBytes.compareTo(a.sizeBytes),
        );
      return copy;
    }

    return SmartScanResult(
      groups: <SmartScanGroup>[
        SmartScanGroup.fromFiles(
          SmartScanCategory.largeFiles,
          sortedBySize(largeFiles.files),
        ),
        SmartScanGroup.fromFiles(
          SmartScanCategory.oldDownloads,
          sortedBySize(oldDownloads.files),
        ),
        SmartScanGroup.fromFiles(
          SmartScanCategory.apkInstallers,
          sortedBySize(apks.files),
        ),
      ],
      scannedAt: scannedAt ?? DateTime.now(),
    );
  }

  final List<SmartScanGroup> groups;
  final DateTime scannedAt;

  SmartScanGroup groupFor(SmartScanCategory category) => groups.firstWhere(
    (SmartScanGroup group) => group.category == category,
    orElse: () => SmartScanGroup(
      category: category,
      files: const <ScannedFile>[],
      totalBytes: 0,
    ),
  );

  /// Groups holding at least one file, biggest contributor first.
  List<SmartScanGroup> get nonEmptyGroups {
    final List<SmartScanGroup> found = groups
        .where((SmartScanGroup group) => !group.isEmpty)
        .toList()
      ..sort(
        (SmartScanGroup a, SmartScanGroup b) =>
            b.totalBytes.compareTo(a.totalBytes),
      );
    return found;
  }

  /// Every file found, counted once even when several checks matched it.
  List<ScannedFile> get uniqueFiles {
    final Set<String> seen = <String>{};
    final List<ScannedFile> files = <ScannedFile>[];
    for (final SmartScanGroup group in groups) {
      for (final ScannedFile file in group.files) {
        if (seen.add(file.uri)) {
          files.add(file);
        }
      }
    }
    files.sort(
      (ScannedFile a, ScannedFile b) => b.sizeBytes.compareTo(a.sizeBytes),
    );
    return List<ScannedFile>.unmodifiable(files);
  }

  /// Number of distinct files found.
  int get totalFiles => uniqueFiles.length;

  /// Recoverable space, counting each file once.
  ///
  /// This is deliberately not the sum of the group totals, which would
  /// overstate the figure whenever a file matched more than one check.
  int get totalBytes => uniqueFiles.fold<int>(
    0,
    (int sum, ScannedFile file) => sum + file.sizeBytes,
  );

  bool get isEmpty => totalFiles == 0;

  /// True when at least one file was matched by more than one check.
  bool get hasOverlap {
    final int summed = groups.fold<int>(
      0,
      (int sum, SmartScanGroup group) => sum + group.fileCount,
    );
    return summed > totalFiles;
  }
}
