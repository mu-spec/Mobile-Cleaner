import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_cleaner/features/apps/domain/installed_app.dart';

/// An app's launcher icon, falling back to its initial.
///
/// Icons come from the platform as PNG bytes. Any failure — a missing icon, a
/// drawable that could not be rasterised, corrupt bytes — resolves to a
/// lettered placeholder rather than an error, so one bad app cannot break the
/// list.
class AppIcon extends StatelessWidget {
  const AppIcon({required this.app, this.size = 44, super.key});

  final InstalledApp app;
  final double size;

  /// Target decode size in physical pixels, clamped to the source icon size.
  int _decodeExtent(BuildContext context) {
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final double physical = size * (ratio <= 0 ? 1 : ratio);
    return physical.clamp(32, 96).round();
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = app.icon;

    if (bytes == null || bytes.isEmpty) {
      return _IconFallback(app: app, size: size);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.memory(
          bytes,
          key: Key('app_icon_${app.packageName}'),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          // Icons arrive as 96px PNGs; decode to the drawn size so a list of
          // 100 apps does not hold 100 full-size bitmaps in the image cache.
          cacheWidth: _decodeExtent(context),
          cacheHeight: _decodeExtent(context),
          // A corrupt icon must not take down the list.
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) =>
                  _IconFallback(app: app, size: size),
        ),
      ),
    );
  }
}

class _IconFallback extends StatelessWidget {
  const _IconFallback({required this.app, required this.size});

  final InstalledApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    // substring(0, 1), not `characters`, to avoid pulling in another package
    // for a single letter. A split surrogate would render as a placeholder
    // glyph, which is an acceptable fallback for a fallback.
    final String initial = app.name.isEmpty
        ? '?'
        : app.name.substring(0, 1).toUpperCase();

    return Container(
      key: Key('app_icon_fallback_${app.packageName}'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
