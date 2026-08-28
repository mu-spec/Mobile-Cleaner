import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Shared visual language for every tool opened from the Photos dashboard.
///
/// The widgets deliberately reuse Home's blue/orange identity while keeping
/// file selection and cleanup behavior inside the individual feature screens.
abstract final class PhotoToolUi {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color background(BuildContext context) =>
      isDark(context) ? AppColors.darkBackground : HomeUpperStyle.background;

  static Color surface(BuildContext context) =>
      isDark(context) ? AppColors.darkSurfaceElevated : HomeUpperStyle.card;

  static Color border(BuildContext context) =>
      isDark(context) ? AppColors.darkBorder : HomeUpperStyle.border;

  static Color primary(BuildContext context) =>
      isDark(context) ? AppColors.darkPrimary : HomeUpperStyle.primaryBlue;

  static Color orange(BuildContext context) =>
      isDark(context) ? AppColors.darkOrange : HomeUpperStyle.orange;

  static BoxDecoration panelDecoration(
    BuildContext context, {
    double radius = 20,
    Color? borderColor,
  }) {
    final bool dark = isDark(context);
    return BoxDecoration(
      color: surface(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? border(context)),
      boxShadow: dark
          ? const <BoxShadow>[]
          : <BoxShadow>[
              BoxShadow(
                color: HomeUpperStyle.navy.withValues(alpha: 0.055),
                blurRadius: 24,
                offset: const Offset(0, 9),
              ),
            ],
    );
  }
}

/// Compact premium action used for an explicit rescan inside a photo tool.
class PhotoToolActionButton extends StatelessWidget {
  const PhotoToolActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool dark = PhotoToolUi.isDark(context);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(40),
          backgroundColor: dark
              ? AppColors.darkInfoSurface
              : HomeUpperStyle.softBlue,
          foregroundColor: PhotoToolUi.primary(context),
          side: BorderSide(color: PhotoToolUi.border(context)),
        ),
        icon: PhosphorIcon(icon, size: 21),
      ),
    );
  }
}

/// High-emphasis summary that establishes the hierarchy of every tool.
class PhotoToolSummaryCard extends StatelessWidget {
  const PhotoToolSummaryCard({
    required this.icon,
    required this.eyebrow,
    required this.value,
    required this.description,
    this.note,
    this.valueKey,
    this.descriptionKey,
    super.key,
  });

  final IconData icon;
  final String eyebrow;
  final String value;
  final String description;
  final Widget? note;
  final Key? valueKey;
  final Key? descriptionKey;

  @override
  Widget build(BuildContext context) {
    final bool dark = PhotoToolUi.isDark(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const <Color>[Color(0xFF102B5B), Color(0xFF0D1B32)]
              : const <Color>[
                  HomeUpperStyle.deepBlue,
                  HomeUpperStyle.primaryBlue,
                ],
        ),
        borderRadius: BorderRadius.circular(HomeUpperStyle.heroRadius),
        border: Border.all(
          color: dark
              ? AppColors.darkPrimary.withValues(alpha: 0.32)
              : Colors.white.withValues(alpha: 0.16),
        ),
        boxShadow: dark
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: HomeUpperStyle.deepBlue.withValues(alpha: 0.2),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -34,
            top: -42,
            child: Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: PhotoToolUi.orange(context).withValues(alpha: 0.52),
                  width: 18,
                ),
              ),
            ),
          ),
          Positioned(
            right: 28,
            bottom: -42,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Center(
                    child: PhosphorIcon(
                      icon,
                      size: 29,
                      color: Colors.white,
                      duotoneSecondaryColor: const Color(0xFFFFC670),
                      duotoneSecondaryOpacity: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        eyebrow.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.05,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        value,
                        key: valueKey,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: const Color(0xFFFFB04A),
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.7,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        key: descriptionKey,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (note != null) ...<Widget>[
                        const SizedBox(height: 13),
                        note!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoToolHeroNote extends StatelessWidget {
  const PhotoToolHeroNote({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: <Widget>[
          PhosphorIcon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.86),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoToolSectionHeader extends StatelessWidget {
  const PhotoToolSectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: PhotoToolUi.isDark(context)
                  ? AppColors.darkInfoSurface
                  : HomeUpperStyle.softBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: PhosphorIcon(
                icon,
                size: 21,
                color: PhotoToolUi.primary(context),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class PhotoToolChoiceChip extends StatelessWidget {
  const PhotoToolChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final bool dark = PhotoToolUi.isDark(context);
    final Color primary = PhotoToolUi.primary(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: true,
      checkmarkColor: Colors.white,
      selectedColor: primary,
      backgroundColor: PhotoToolUi.surface(context),
      side: BorderSide(color: selected ? primary : PhotoToolUi.border(context)),
      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: selected
            ? Colors.white
            : dark
            ? AppColors.darkTextPrimary
            : HomeUpperStyle.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class PhotoToolPanel extends StatelessWidget {
  const PhotoToolPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: PhotoToolUi.panelDecoration(context),
      child: child,
    );
  }
}

class PhotoToolFilePanel extends StatelessWidget {
  const PhotoToolFilePanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool dark = PhotoToolUi.isDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: PhotoToolUi.surface(context),
        elevation: dark ? 0 : 2,
        shadowColor: HomeUpperStyle.navy.withValues(alpha: 0.1),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: PhotoToolUi.border(context)),
        ),
        child: child,
      ),
    );
  }
}

class PhotoToolEmptyState extends StatelessWidget {
  const PhotoToolEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: PhotoToolPanel(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: PhotoToolUi.isDark(context)
                      ? AppColors.darkInfoSurface
                      : HomeUpperStyle.softBlue,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: PhosphorIcon(
                    icon,
                    size: 38,
                    color: PhotoToolUi.primary(context),
                    duotoneSecondaryColor: PhotoToolUi.orange(context),
                    duotoneSecondaryOpacity: 0.9,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoToolLoadingState extends StatelessWidget {
  const PhotoToolLoadingState({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox.square(
              dimension: 92,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CircularProgressIndicator(
                    strokeWidth: 6,
                    color: PhotoToolUi.primary(context),
                    backgroundColor: PhotoToolUi.isDark(context)
                        ? AppColors.darkBorder
                        : HomeUpperStyle.softBlue,
                  ),
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: PhotoToolUi.surface(context),
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: PhotoToolUi.primary(context)
                              .withValues(alpha: 0.14),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Center(
                      child: PhosphorIcon(
                        icon,
                        size: 30,
                        color: PhotoToolUi.orange(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
