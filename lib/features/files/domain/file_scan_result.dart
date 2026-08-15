import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Aggregated totals for a single [FileCategory].
class FileCategorySummary {
  const FileCategorySummary({
    required this.category,
    required this.fileCount,
    required this.totalBytes,
    this.newestFileDate,
  });

  factory FileCategorySummary.fromFiles(
    FileCategory category,
    List<ScannedFile> files,
  ) {
    int totalBytes = 0;
    DateTime? newest;
    for (final ScannedFile file in files) {
      totalBytes += file.sizeBytes;
      if (newest == null || file.dateModified.isAfter(newest)) {
        newest = file.dateModified;
      }
    }
    return FileCategorySummary(
      category: category,
      fileCount: files.length,
      totalBytes: totalBytes,
      newestFileDate: newest,
    );
  }

  final FileCategory category;
  final int fileCount;
  final int totalBytes;
  final DateTime? newestFileDate;

  bool get isEmpty => fileCount == 0;
}

/// Complete output of one discovery pass over accessible storage.
class FileScanResult {
  const FileScanResult({
    required this.files,
    required this.summaries,
    required this.scannedAt,
    this.durationMillis = 0,
    this.truncated = false,
  });

  /// Builds a result (and its per-category summaries) from a flat file list.
  factory FileScanResult.fromFiles(
    List<ScannedFile> files, {
    DateTime? scannedAt,
    int durationMillis = 0,
    bool truncated = false,
    List<FileCategory> categories = FileCategory.scannable,
  }) {
    final Map<FileCategory, List<ScannedFile>> grouped =
        <FileCategory, List<ScannedFile>>{
          for (final FileCategory category in categories)
            category: <ScannedFile>[],
        };
    for (final ScannedFile file in files) {
      grouped.putIfAbsent(file.category, () => <ScannedFile>[]).add(file);
    }

    return FileScanResult(
      files: List<ScannedFile>.unmodifiable(files),
      summaries: Map<FileCategory, FileCategorySummary>.unmodifiable(
        grouped.map(
          (FileCategory category, List<ScannedFile> items) =>
              MapEntry<FileCategory, FileCategorySummary>(
                category,
                FileCategorySummary.fromFiles(category, items),
              ),
        ),
      ),
      scannedAt: scannedAt ?? DateTime.now(),
      durationMillis: durationMillis,
      truncated: truncated,
    );
  }

  static final FileScanResult empty = FileScanResult(
    files: const <ScannedFile>[],
    summaries: const <FileCategory, FileCategorySummary>{},
    scannedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final List<ScannedFile> files;
  final Map<FileCategory, FileCategorySummary> summaries;
  final DateTime scannedAt;

  /// How long the native scan took, for diagnostics.
  final int durationMillis;

  /// True when the scan hit its per-category row limit.
  final bool truncated;

  int get totalFiles => files.length;

  int get totalBytes =>
      files.fold<int>(0, (int sum, ScannedFile file) => sum + file.sizeBytes);

  bool get isEmpty => files.isEmpty;

  List<ScannedFile> byCategory(FileCategory category) => files
      .where((ScannedFile file) => file.category == category)
      .toList(growable: false);

  FileCategorySummary summaryFor(FileCategory category) =>
      summaries[category] ??
      FileCategorySummary(category: category, fileCount: 0, totalBytes: 0);

  /// Categories ordered by how much space they occupy.
  List<FileCategorySummary> get summariesBySize {
    final List<FileCategorySummary> values = summaries.values.toList()
      ..sort(
        (FileCategorySummary a, FileCategorySummary b) =>
            b.totalBytes.compareTo(a.totalBytes),
      );
    return values;
  }

  /// The heaviest files across every category.
  List<ScannedFile> largestFiles({int limit = 20}) {
    final List<ScannedFile> sorted = List<ScannedFile>.of(files)
      ..sort(
        (ScannedFile a, ScannedFile b) => b.sizeBytes.compareTo(a.sizeBytes),
      );
    return sorted.take(limit).toList(growable: false);
  }
}
