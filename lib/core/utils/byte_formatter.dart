/// Shared human-readable byte formatting used across the app.
abstract final class ByteFormatter {
  static const double _kib = 1024;
  static const double _mib = _kib * 1024;
  static const double _gib = _mib * 1024;
  static const double _tib = _gib * 1024;

  /// Formats [bytes] as `1.4 GB`, `820.0 MB`, `12.0 KB`, or `640 B`.
  static String format(int bytes) {
    if (bytes < 0) {
      return '0 B';
    }
    if (bytes >= _tib) {
      return '${(bytes / _tib).toStringAsFixed(1)} TB';
    }
    if (bytes >= _gib) {
      return '${(bytes / _gib).toStringAsFixed(1)} GB';
    }
    if (bytes >= _mib) {
      return '${(bytes / _mib).toStringAsFixed(1)} MB';
    }
    if (bytes >= _kib) {
      return '${(bytes / _kib).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
