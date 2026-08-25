import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// A consistent rounded-square tile for Home's Phosphor Duotone feature icons.
///
/// Uses [PhosphorIcon] (not Flutter's [Icon]) because Duotone icons render
/// two stacked font layers. The secondary layer is drawn at full opacity so
/// the two-tone design reads as intended. All Home feature icons share the
/// same size, container, corner radius, and icon-to-tile proportion.
class HomeDuotoneIcon extends StatelessWidget {
  const HomeDuotoneIcon({
    required this.icon,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    super.key,
  });

  /// A `PhosphorIconsDuotone.*` constant.
  final IconData icon;
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;

  /// Shared tile dimension for every Home feature icon.
  static const double containerSize = 50;

  /// Shared glyph dimension for every Home feature icon.
  static const double iconSize = 28;

  /// Shared corner radius.
  static const double radius = 14;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: PhosphorIcon(
          icon,
          size: iconSize,
          color: primaryColor,
          duotoneSecondaryColor: secondaryColor,
          duotoneSecondaryOpacity: 1.0,
        ),
      ),
    );
  }
}
