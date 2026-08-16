import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Narrows the shared duplicate engine down to photographs.
///
/// Phase 17 proved byte-identical files of any kind. Phase 18 reuses that
/// engine unchanged and simply feeds it images only, so a duplicate document
/// or video can never appear in a photo-focused screen.
abstract final class PhotoDuplicates {
  /// True when a scanned file is an image.
  ///
  /// The MIME type is checked as well as the category because a picture found
  /// in Downloads is still a photo, and grouping it with its copy in DCIM is
  /// exactly the case this tool exists for.
  static bool isPhoto(ScannedFile file) =>
      file.category == FileCategory.images ||
      (file.mimeType?.startsWith('image/') ?? false);

  /// Keeps only the images from a scan, preserving order.
  static List<ScannedFile> only(Iterable<ScannedFile> files) =>
      <ScannedFile>[
        for (final ScannedFile file in files)
          if (isPhoto(file)) file,
      ];
}
