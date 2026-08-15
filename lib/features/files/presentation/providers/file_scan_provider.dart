import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Full discovery pass across every scannable category.
final FutureProvider<FileScanResult> fileScanProvider =
    FutureProvider<FileScanResult>((ref) {
      return ref.watch(fileScannerRepositoryProvider).scan();
    });

/// Files for one category, sorted largest first.
final categoryFilesProvider =
    FutureProvider.family<List<ScannedFile>, FileCategory>((
      ref,
      FileCategory category,
    ) async {
      final FileScanResult result = await ref.watch(fileScanProvider.future);
      final List<ScannedFile> files = result.byCategory(category)
        ..sort(
          (ScannedFile a, ScannedFile b) => b.sizeBytes.compareTo(a.sizeBytes),
        );
      return files;
    });
