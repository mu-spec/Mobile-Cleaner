import 'package:flutter/widgets.dart';

/// Spacing scale for the whole app.
///
/// Every gap and padding should be one of these steps, so screens share one
/// rhythm instead of per-widget guesses.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// Main horizontal page padding.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: md);

  /// Default internal padding of a card.
  static const EdgeInsets card = EdgeInsets.all(lg);
}

/// Corner radii for the whole app.
abstract final class AppRadius {
  /// Cards and other large surfaces.
  static const double card = 18;

  /// Buttons and inputs.
  static const double button = 14;

  /// Small tinted icon tiles.
  static const double tile = 12;
}
