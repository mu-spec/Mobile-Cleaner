import 'package:flutter/material.dart';

/// Layout helpers for varying screen sizes and text scales.
abstract final class Responsive {
  /// Height for a horizontal chip bar, grown for the user's text scale.
  ///
  /// The bars were a fixed 52dp. At Android's larger font settings the chip
  /// labels need more room than that, and the fixed box clipped them — a
  /// common, easily missed accessibility failure, because it never shows up
  /// at the default scale a developer tests at.
  ///
  /// Capped so an extreme scale cannot eat the whole screen.
  static double chipBarHeight(BuildContext context) {
    final double scaled = MediaQuery.textScalerOf(context).scale(52);
    return scaled.clamp(52, 92);
  }

  /// Height for a small inline action, grown for text scale.
  static double compactButtonHeight(BuildContext context) {
    final double scaled = MediaQuery.textScalerOf(context).scale(30);
    return scaled.clamp(30, 56);
  }

  /// Height for a photo strip cell, grown for text scale.
  ///
  /// The cells carry several lines of caption under the thumbnail, so they
  /// are the layout most sensitive to a larger font.
  static double photoStripHeight(BuildContext context, double base) {
    final double scaled = MediaQuery.textScalerOf(context).scale(base);
    return scaled.clamp(base, base * 1.8);
  }

  /// True on a wide screen — a tablet, or a phone in landscape.
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600;

  /// Caps content width on a wide screen.
  ///
  /// A list stretched across a tablet is hard to read, and the app is
  /// phone-shaped by design, so content is centred within a comfortable
  /// measure rather than filling the width.
  static double contentMaxWidth(BuildContext context) =>
      isWide(context) ? 720 : double.infinity;
}
