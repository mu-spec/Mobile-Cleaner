/// Size thresholds offered by the Large Files tool.
enum LargeFileFilter {
  over100mb('100 MB+', '100 MB', 100 * 1024 * 1024),
  over500mb('500 MB+', '500 MB', 500 * 1024 * 1024),
  over1gb('1 GB+', '1 GB', 1024 * 1024 * 1024);

  const LargeFileFilter(this.label, this.threshold, this.minBytes);

  /// Chip label, e.g. `100 MB+`.
  final String label;

  /// Bare threshold used in sentences, e.g. `100 MB`.
  final String threshold;

  /// Inclusive lower bound a file must meet to appear.
  final int minBytes;

  /// The smallest threshold, used for the initial scan and default view.
  static const LargeFileFilter defaultFilter = LargeFileFilter.over100mb;

  /// Lowest bound across every filter.
  ///
  /// The scan runs once at this threshold and the UI filters the result in
  /// memory, so switching chips never triggers another device scan.
  static int get lowestBound => LargeFileFilter.over100mb.minBytes;

  bool matches(int sizeBytes) => sizeBytes >= minBytes;
}
