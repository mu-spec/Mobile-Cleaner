class StorageInfo {
  const StorageInfo({
    required this.totalBytes,
    required this.freeBytes,
  }) : assert(totalBytes >= 0),
       assert(freeBytes >= 0);

  final int totalBytes;
  final int freeBytes;

  int get usedBytes =>
      (totalBytes - freeBytes).clamp(0, totalBytes).toInt();

  double get usedFraction {
    if (totalBytes == 0) {
      return 0;
    }
    return (usedBytes / totalBytes).clamp(0, 1).toDouble();
  }

  int get usedPercentage => (usedFraction * 100).round();
}
