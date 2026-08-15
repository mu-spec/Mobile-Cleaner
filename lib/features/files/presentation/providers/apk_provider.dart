import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/apk_summary.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';

/// One scan covering everywhere an installer can turn up.
///
/// The APKs category is the obvious source, but a downloaded package is also
/// reported under Downloads, and a stray `.apk` can be classified as a
/// document. Scanning all three and filtering on the file itself is more
/// reliable than trusting a single category.
final FutureProvider<FileScanResult> apkScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return ref
          .watch(fileScannerRepositoryProvider)
          .scan(
            const FileScanRequest(
              categories: <FileCategory>[
                FileCategory.apks,
                FileCategory.downloads,
                FileCategory.documents,
              ],
              limitPerCategory: 500,
            ),
          );
    });

/// Installers and their combined size, in the requested order.
///
/// Sorting filters the existing scan in memory, so changing order never
/// triggers another device scan.
final apkSummaryProvider = FutureProvider.family<ApkSummary, FileListSort>((
  ref,
  FileListSort sort,
) async {
  final FileScanResult result = await ref.watch(apkScanProvider.future);
  return ApkSummary.from(result.files, sort: sort);
});
