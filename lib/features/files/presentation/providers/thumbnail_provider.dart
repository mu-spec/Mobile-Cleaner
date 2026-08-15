import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Thumbnail bytes for one file, or `null` when it has no visual preview.
///
/// Keyed by URI so two tiles showing the same file share one decode.
final thumbnailProvider = FutureProvider.family<Uint8List?, ScannedFile>((
  ref,
  ScannedFile file,
) async {
  return ref.watch(thumbnailRepositoryProvider).load(file);
});
