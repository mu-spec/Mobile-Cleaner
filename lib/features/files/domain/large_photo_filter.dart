/// Size thresholds offered by the Large Photos tool.
///
/// Deliberately smaller than the Large Files thresholds, whose 100 MB floor
/// would hide almost every photo. A modern camera shot is a few megabytes, so
/// 5 MB is already large for an image.
enum LargePhotoFilter {
  over5mb('5 MB+', '5 MB', 5 * 1024 * 1024),
  over10mb('10 MB+', '10 MB', 10 * 1024 * 1024),
  over20mb('20 MB+', '20 MB', 20 * 1024 * 1024);

  const LargePhotoFilter(this.label, this.threshold, this.minBytes);

  /// Chip label, e.g. `5 MB+`.
  final String label;

  /// Bare threshold used in sentences, e.g. `5 MB`.
  final String threshold;

  /// Inclusive lower bound a photo must meet to appear.
  final int minBytes;

  /// The smallest threshold, used for the initial scan and default view.
  static const LargePhotoFilter defaultFilter = LargePhotoFilter.over5mb;

  /// Lowest bound across every filter.
  ///
  /// The scan runs once at this threshold and the UI filters the result in
  /// memory, so switching chips never triggers another device scan.
  static int get lowestBound => LargePhotoFilter.over5mb.minBytes;

  bool matches(int sizeBytes) => sizeBytes >= minBytes;
}
