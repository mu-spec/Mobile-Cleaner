import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/navigation/root_back_button.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/photo_cleanup_summary.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/photo_cleanup_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Photos tab: a compact overview of the four photo-cleanup tools.
///
/// Every value comes from the tool's existing provider. This dashboard only
/// reports the results and opens the relevant review screen; it never deletes
/// anything itself.
class PhotosScreen extends ConsumerWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PhotoCleanupSummary> cleanup = ref.watch(
      photoCleanupProvider,
    );
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      key: const Key('photos_screen'),
      appBar: AppBar(
        toolbarHeight: 60,
        leading: const RootBackButton(buttonKey: Key('photos_back_button')),
        titleSpacing: 4,
        title: Text(
          'Photos',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('photo_cleanup_rescan'),
            tooltip: 'Scan again',
            onPressed: () => refreshPhotoCleanup(ref),
            icon: const Icon(Icons.refresh_rounded, size: 27),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            refreshPhotoCleanup(ref);
            await ref.read(photoCleanupProvider.future);
          },
          child: cleanup.when(
            loading: () => const FilesScanningView(),
            error: (Object error, StackTrace stackTrace) => FilesErrorView(
              error: error,
              onRetry: () => refreshPhotoCleanup(ref),
              onPermissions: () => context.push(AppRoutes.permissions),
            ),
            data: (PhotoCleanupSummary summary) =>
                _PhotoCleanupView(summary: summary),
          ),
        ),
      ),
    );
  }
}

class _PhotoCleanupView extends StatelessWidget {
  const _PhotoCleanupView({required this.summary});

  final PhotoCleanupSummary summary;

  static String _routeFor(PhotoCleanupTool tool) => switch (tool) {
    PhotoCleanupTool.duplicatePhotos => AppRoutes.photoDuplicates,
    PhotoCleanupTool.screenshots => AppRoutes.screenshotCleaner,
    PhotoCleanupTool.largePhotos => AppRoutes.largePhotos,
    PhotoCleanupTool.similarPhotos => AppRoutes.similarPhotos,
  };

  void _open(BuildContext context, PhotoCleanupTool tool) {
    context.push(_routeFor(tool));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('photo_cleanup_dashboard'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        const _PhotoHeroCard(),
        const SizedBox(height: 14),
        _PhotoToolsCard(
          summary: summary,
          onOpen: (PhotoCleanupTool tool) => _open(context, tool),
        ),
        if (summary.isEmpty) ...<Widget>[
          const SizedBox(height: 20),
          const _NothingToClean(),
        ],
      ],
    );
  }
}

/// The warm photo-review banner from the supplied reference.
class _PhotoHeroCard extends StatelessWidget {
  const _PhotoHeroCard();

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: const Key('photo_hero_card'),
      height: 146,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const <Color>[Color(0xFFE96100), Color(0xFFFF8A00)]
              : const <Color>[Color(0xFFFF7108), Color(0xFFFF9700)],
        ),
        borderRadius: BorderRadius.circular(17),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: HomeUpperStyle.orange.withValues(
              alpha: isDark ? 0.18 : 0.24,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: -24,
            top: -46,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          const Positioned(left: 20, top: 20, bottom: 18, child: _HeroCopy()),
          const Positioned(
            right: 2,
            top: 4,
            bottom: 1,
            width: 168,
            child: _StackedPhotoIllustration(),
          ),
        ],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    final TextScaler heroTextScaler = MediaQuery.textScalerOf(context)
        .clamp(maxScaleFactor: 1.15);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 185,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Review and clean\nyour photos',
              key: const Key('photo_hero_title'),
              textScaler: heroTextScaler,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.25,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Free up space by removing\nduplicates and clutter.',
              key: const Key('photo_hero_subtitle'),
              textScaler: heroTextScaler,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three offset photo prints create the same visual idea as the reference
/// while remaining a crisp, resolution-independent Flutter illustration.
class _StackedPhotoIllustration extends StatelessWidget {
  const _StackedPhotoIllustration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const Key('photo_hero_illustration'),
      alignment: Alignment.center,
      children: <Widget>[
        Positioned(
          right: 8,
          top: 15,
          child: Transform.rotate(
            angle: 0.15,
            child: const _PhotoPrint(
              width: 79,
              height: 107,
              sky: Color(0xFF67B8F4),
              mountain: Color(0xFF164A8A),
            ),
          ),
        ),
        Positioned(
          right: 54,
          top: 29,
          child: Transform.rotate(
            angle: -0.12,
            child: const _PhotoPrint(
              width: 77,
              height: 103,
              sky: Color(0xFF58C7E8),
              mountain: Color(0xFF18375D),
            ),
          ),
        ),
        Positioned(
          right: 29,
          top: 24,
          child: Transform.rotate(
            angle: 0.035,
            child: const _PhotoPrint(
              width: 84,
              height: 111,
              sky: Color(0xFF74D4F2),
              mountain: Color(0xFF102C52),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoPrint extends StatelessWidget {
  const _PhotoPrint({
    required this.width,
    required this.height,
    required this.sky,
    required this.mountain,
  });

  final double width;
  final double height;
  final Color sky;
  final Color mountain;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(5, 5, 5, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFEFF),
        borderRadius: BorderRadius.circular(5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF723200).withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: _LandscapePainter(sky: sky, mountain: mountain),
        ),
      ),
    );
  }
}

class _LandscapePainter extends CustomPainter {
  const _LandscapePainter({required this.sky, required this.mountain});

  final Color sky;
  final Color mountain;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[sky, const Color(0xFFE9F8FF)],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.22),
      size.width * 0.1,
      Paint()..color = const Color(0xFFFFE48C),
    );

    final Path distant = Path()
      ..moveTo(0, size.height * 0.72)
      ..lineTo(size.width * 0.29, size.height * 0.39)
      ..lineTo(size.width * 0.52, size.height * 0.67)
      ..lineTo(size.width * 0.7, size.height * 0.43)
      ..lineTo(size.width, size.height * 0.73)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(distant, Paint()..color = mountain.withValues(alpha: 0.72));

    final Path foreground = Path()
      ..moveTo(0, size.height * 0.82)
      ..quadraticBezierTo(
        size.width * 0.33,
        size.height * 0.62,
        size.width * 0.58,
        size.height * 0.82,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.66,
        size.width,
        size.height * 0.79,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(foreground, Paint()..color = mountain);
  }

  @override
  bool shouldRepaint(covariant _LandscapePainter oldDelegate) {
    return oldDelegate.sky != sky || oldDelegate.mountain != mountain;
  }
}

class _PhotoToolsCard extends StatelessWidget {
  const _PhotoToolsCard({required this.summary, required this.onOpen});

  final PhotoCleanupSummary summary;
  final ValueChanged<PhotoCleanupTool> onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color border = isDark ? AppColors.darkBorder : AppColors.border;

    return Container(
      key: const Key('photo_cleanup_card'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
        boxShadow: <BoxShadow>[
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF172033).withValues(alpha: 0.055),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        children: <Widget>[
          for (int index = 0; index < summary.entries.length; index++) ...[
            _CleanupRow(
              entry: summary.entries[index],
              onOpen: () => onOpen(summary.entries[index].tool),
            ),
            if (index != summary.entries.length - 1)
              Divider(height: 1, indent: 70, endIndent: 14, color: border),
          ],
          if (summary.hasOverlap)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
              decoration: BoxDecoration(
                color: (isDark ? AppColors.darkInfoSurface : AppColors.softBlue)
                    .withValues(alpha: isDark ? 0.48 : 0.7),
                border: Border(top: BorderSide(color: border)),
              ),
              child: Text(
                'Some photos appear in more than one category.',
                key: const Key('photo_cleanup_overlap_note'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CleanupRow extends StatelessWidget {
  const _CleanupRow({required this.entry, required this.onOpen});

  final PhotoCleanupEntry entry;
  final VoidCallback onOpen;

  IconData get _icon => switch (entry.tool) {
    PhotoCleanupTool.duplicatePhotos => PhosphorIconsDuotone.copy,
    PhotoCleanupTool.screenshots => PhosphorIconsDuotone.deviceMobileCamera,
    PhotoCleanupTool.largePhotos => PhosphorIconsDuotone.imageSquare,
    PhotoCleanupTool.similarPhotos => PhosphorIconsDuotone.imagesSquare,
  };

  _ToolColors get _toolColors => switch (entry.tool) {
    PhotoCleanupTool.duplicatePhotos => const _ToolColors(
      foreground: Color(0xFFE43D55),
      secondary: Color(0xFFFFA7B5),
      background: Color(0xFFFFEAF0),
    ),
    PhotoCleanupTool.screenshots => const _ToolColors(
      foreground: Color(0xFF245FCE),
      secondary: Color(0xFF8CB8FF),
      background: Color(0xFFEAF2FF),
    ),
    PhotoCleanupTool.largePhotos => const _ToolColors(
      foreground: Color(0xFF1263BE),
      secondary: Color(0xFF79C6F3),
      background: Color(0xFFE9F5FF),
    ),
    PhotoCleanupTool.similarPhotos => const _ToolColors(
      foreground: Color(0xFFF27D08),
      secondary: Color(0xFFFFC26C),
      background: Color(0xFFFFF0DB),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final bool pending = !entry.hasFigure;
    final String value = pending
        ? 'Analyze'
        : entry.isEmpty
        ? 'None'
        : entry.isEstimate
        ? 'Up to ${ByteFormatter.format(entry.bytes)}'
        : ByteFormatter.format(entry.bytes);
    final _ToolColors visual = _toolColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('photo_tool_${entry.tool.name}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: <Widget>[
              Container(
                key: Key('photo_tool_icon_${entry.tool.name}'),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? visual.foreground.withValues(alpha: 0.16)
                      : visual.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: visual.foreground.withValues(
                      alpha: isDark ? 0.25 : 0.08,
                    ),
                  ),
                ),
                child: Center(
                  child: PhosphorIcon(
                    _icon,
                    size: 26,
                    color: visual.foreground,
                    duotoneSecondaryColor: visual.secondary,
                    duotoneSecondaryOpacity: 1,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      entry.tool.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      key: Key('photo_tool_value_${entry.tool.name}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Review',
                key: Key('photo_tool_review_${entry.tool.name}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkPrimary : AppColors.actionBlue,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolColors {
  const _ToolColors({
    required this.foreground,
    required this.secondary,
    required this.background,
  });

  final Color foreground;
  final Color secondary;
  final Color background;
}

class _NothingToClean extends StatelessWidget {
  const _NothingToClean();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      key: const Key('photo_cleanup_clean'),
      children: <Widget>[
        Icon(
          Icons.check_circle_outline_rounded,
          size: 42,
          color: colors.primary,
        ),
        const SizedBox(height: 10),
        Text(
          'Your photos look tidy',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'No duplicates, screenshots, or oversized images were found.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
