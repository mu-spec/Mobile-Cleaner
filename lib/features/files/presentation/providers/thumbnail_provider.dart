import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

/// Thumbnail bytes for one file, or `null` when it has no visual preview.
///
/// Keyed by URI so two tiles showing the same file share one decode.
///
/// ## Why `autoDispose` matters here
///
/// A plain `family` keeps **one provider entry alive per key, forever**. On a
/// phone with 5,000 photos, scrolling the whole list would leave 5,000 live
/// entries, each holding decoded JPEG bytes, and none of them would ever be
/// released. That is the single largest memory risk in the app.
///
/// With `autoDispose`, an entry is dropped once no tile is showing that file,
/// so memory tracks what is on screen rather than what has ever been scrolled
/// past. Re-scrolling costs a cheap re-read, and
/// [PlatformThumbnailRepository]'s own bounded cache absorbs most of that.
final thumbnailProvider = FutureProvider.autoDispose
    .family<Uint8List?, ScannedFile>((ref, ScannedFile file) async {
      return ref.watch(thumbnailRepositoryProvider).load(file);
    });
