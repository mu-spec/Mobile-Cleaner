enum ScanLaunchTarget {
  smartScan('smart-scan'),
  screenshots('screenshots'),
  duplicates('duplicates'),
  largeVideos('large-videos');

  const ScanLaunchTarget(this.routeValue);

  final String routeValue;

  static ScanLaunchTarget? fromRouteValue(String? value) {
    for (final ScanLaunchTarget target in values) {
      if (target.routeValue == value) {
        return target;
      }
    }
    return null;
  }
}
