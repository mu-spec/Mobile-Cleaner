/// A pair of 64-bit perceptual hashes describing how an image *looks*.
///
/// Distinct from the SHA-256 content hash used for exact duplicates: that
/// answers "are these the same bytes", this answers "do these look the same".
/// A re-saved, re-compressed, or slightly re-framed photo has a completely
/// different content hash but a nearly identical perceptual hash.
///
/// The platform returns 32 lowercase hex characters: dHash then aHash.
class PerceptualHash {
  const PerceptualHash({required this.difference, required this.average});

  /// Parses the 32-character platform string.
  ///
  /// Returns `null` for anything malformed rather than guessing: a bad hash
  /// would silently group unrelated photos, which is the one failure this
  /// feature must not have.
  static PerceptualHash? tryParse(String? raw) {
    if (raw == null || raw.length != hexLength) {
      return null;
    }
    final int? difference = _parseHex(raw.substring(0, 16));
    final int? average = _parseHex(raw.substring(16));
    if (difference == null || average == null) {
      return null;
    }
    return PerceptualHash(difference: difference, average: average);
  }

  /// Combined length of both hex-encoded hashes.
  static const int hexLength = 32;

  /// Bits in one hash. Both are 64-bit.
  static const int bitCount = 64;

  /// Gradient hash: each pixel against its right-hand neighbour.
  ///
  /// Robust to brightness and exposure differences, which is why it carries
  /// the most weight.
  final int difference;

  /// Average hash: each pixel against the frame mean.
  ///
  /// Cruder, used as a second opinion. Requiring both to agree suppresses the
  /// false positives dHash alone produces on flat images — sky, snow, walls.
  final int average;

  /// Bits that differ between two integers.
  ///
  /// Dart ints are 64-bit on mobile, but the arithmetic is done with unsigned
  /// shifts and masking so a sign bit can never corrupt the count.
  static int hammingDistance(int a, int b) {
    int value = a ^ b;
    int count = 0;
    while (value != 0) {
      count += value & 1;
      value = value >>> 1;
    }
    return count;
  }

  /// Bits that differ in the gradient hash. 0 means visually identical.
  int differenceDistance(PerceptualHash other) =>
      hammingDistance(difference, other.difference);

  /// Bits that differ in the average hash.
  int averageDistance(PerceptualHash other) =>
      hammingDistance(average, other.average);

  /// Parses 16 hex characters into an int, or null when malformed.
  ///
  /// Parsed in two halves because a 16-digit hex value with the top bit set
  /// exceeds the signed range `int.parse` accepts on some platforms.
  static int? _parseHex(String hex) {
    if (hex.length != 16) {
      return null;
    }
    final int? high = int.tryParse(hex.substring(0, 8), radix: 16);
    final int? low = int.tryParse(hex.substring(8), radix: 16);
    if (high == null || low == null) {
      return null;
    }
    return (high << 32) | low;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PerceptualHash &&
          other.difference == difference &&
          other.average == average);

  @override
  int get hashCode => Object.hash(difference, average);
}
