/// What the platform measured about one photo.
///
/// Purely descriptive. Deciding which photo is *best* is
/// [BestPhotoScorer](best_photo_scorer.dart)'s job, kept separate so the
/// ranking rules can be reasoned about and tested without a device.
class PhotoQuality {
  const PhotoQuality({
    required this.width,
    required this.height,
    required this.pixels,
    required this.sharpness,
  });

  /// Full-resolution width in pixels.
  final int width;

  /// Full-resolution height in pixels.
  final int height;

  /// Total pixels. Supplied by the platform rather than multiplied here.
  final int pixels;

  /// Variance of the Laplacian: high is sharp, low is blurred.
  ///
  /// Measured at a fixed working size, so it reflects focus rather than
  /// resolution. Comparable between photos, but the absolute value has no
  /// meaning on its own — a busy scene scores higher than a plain one at the
  /// same focus, which is why it is only ever compared *within* a group of
  /// photos of the same scene.
  final double sharpness;

  /// Megapixels, for display.
  double get megapixels => pixels / 1000000;

  /// Longest edge, used to describe resolution briefly.
  int get longestEdge => width > height ? width : height;

  /// True when nothing usable was measured.
  bool get isEmpty => pixels <= 0;

  /// Parses one platform row, returning null when unusable.
  ///
  /// A malformed row is dropped rather than defaulted, because a photo with a
  /// fabricated quality score could be recommended over a genuinely better
  /// one.
  static PhotoQuality? fromPlatformMap(Map<Object?, Object?> map) {
    final int? width = _readInt(map['width']);
    final int? height = _readInt(map['height']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }

    final int pixels = _readInt(map['pixels']) ?? (width * height);
    final double sharpness = _readDouble(map['sharpness']) ?? 0;

    return PhotoQuality(
      width: width,
      height: height,
      pixels: pixels <= 0 ? width * height : pixels,
      // A negative variance is impossible; treat it as unmeasured.
      sharpness: sharpness < 0 ? 0 : sharpness,
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static double? _readDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhotoQuality &&
          other.width == width &&
          other.height == height &&
          other.pixels == pixels &&
          other.sharpness == sharpness);

  @override
  int get hashCode => Object.hash(width, height, pixels, sharpness);
}
