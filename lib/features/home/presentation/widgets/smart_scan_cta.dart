import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/radar_painter.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class SmartScanCta extends ConsumerStatefulWidget {
  const SmartScanCta({required this.onScan, required this.onOpen, super.key});

  final VoidCallback onScan;
  final ValueChanged<RecommendationKind> onOpen;

  @override
  ConsumerState<SmartScanCta> createState() => _SmartScanCtaState();
}

class _SmartScanCtaState extends ConsumerState<SmartScanCta>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5600),
  );
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) {
      return;
    }
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _radarController
        ..stop()
        ..value = 0.125;
    } else {
      _radarController.repeat();
    }
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final AsyncValue<List<Recommendation>> advice = ref.watch(
      recommendationsProvider,
    );
    final bool hasRec = advice.hasValue && advice.value!.isNotEmpty;

    return Semantics(
      button: true,
      label: 'Scan or open recommendation',
      child: Material(
        key: const Key('smart_scan_hero'),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          key: const Key('smart_scan_surface'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const <Color>[Color(0xFF143B91), Color(0xFF2364D9)]
                  : const <Color>[
                      HomeUpperStyle.deepBlue,
                      HomeUpperStyle.primaryBlue,
                    ],
            ),
            border: isDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                : null,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.30)
                    : HomeUpperStyle.primaryBlue.withValues(alpha: 0.28),
                blurRadius: isDark ? 18 : 14,
                offset: Offset(0, isDark ? 8 : 6),
              ),
              if (isDark)
                BoxShadow(
                  color: const Color(0xFF3478F6).withValues(alpha: 0.10),
                  blurRadius: 26,
                  offset: const Offset(0, 5),
                ),
            ],
          ),
          child: InkWell(
            key: const Key('smart_scan_button'),
            onTap: () {
              if (hasRec) {
                widget.onOpen(advice.value!.first.kind);
              } else {
                widget.onScan();
              }
            },
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 100),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // LEFT SIDE: recommendation + scan button
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox(
                            key: const Key('smart_scan_recommendation_slot'),
                            height: 40,
                            child: advice.when(
                              loading: () => const _NoRecommendationState(),
                              error: (_, _) => const _NoRecommendationState(),
                              data: (List<Recommendation> found) {
                                if (found.isEmpty) {
                                  return const _NoRecommendationState();
                                }
                                return InkWell(
                                  onTap: () => widget.onOpen(found.first.kind),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: _RecommendationState(
                                      item: found.first,
                                      onOpen: () =>
                                          widget.onOpen(found.first.kind),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: ElevatedButton.icon(
                              key: const Key('home_scan_now_button'),
                              onPressed: widget.onScan,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: HomeUpperStyle.primaryBlue,
                                elevation: 0,
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              icon: const PhosphorIcon(
                                PhosphorIconsDuotone.magnifyingGlass,
                                size: 15,
                                color: HomeUpperStyle.primaryBlue,
                                duotoneSecondaryColor:
                                    HomeUpperStyle.primaryBlue,
                                duotoneSecondaryOpacity: 0.35,
                              ),
                              label: const Text('Scan Now'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    // RIGHT SIDE: radar / scanning visual
                    SizedBox(
                      key: const Key('premium_radar_visual'),
                      width: 104,
                      height: 104,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _radarController,
                              builder: (BuildContext context, Widget? child) {
                                return CustomPaint(
                                  key: const Key('premium_radar_paint'),
                                  painter: RadarPainter(
                                    rotation: _radarController.value,
                                  ),
                                  size: const Size(104, 104),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoRecommendationState extends StatelessWidget {
  const _NoRecommendationState();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Scan your phone to find cleanup opportunities',
      child: Row(
        key: const Key('smart_scan_no_recommendation'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          PhosphorIcon(
            PhosphorIconsDuotone.lightbulb,
            size: 20,
            color: Colors.white.withValues(alpha: 0.92),
            duotoneSecondaryColor: Colors.white,
            duotoneSecondaryOpacity: 0.38,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Scan your phone to find cleanup opportunities',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.15,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationState extends StatelessWidget {
  const _RecommendationState({required this.item, required this.onOpen});

  final Recommendation item;
  final VoidCallback onOpen;

  IconData get _icon => switch (item.kind) {
    RecommendationKind.duplicateCleanup => PhosphorIconsDuotone.files,
    RecommendationKind.apkInstallerReview => PhosphorIconsDuotone.androidLogo,
    RecommendationKind.oldDownloadReview => PhosphorIconsDuotone.downloadSimple,
    RecommendationKind.screenshotReview => PhosphorIconsDuotone.image,
    RecommendationKind.largeFileReview => PhosphorIconsDuotone.fileArrowDown,
    RecommendationKind.largeVideoReview => PhosphorIconsDuotone.playCircle,
  };

  @override
  Widget build(BuildContext context) {
    final bool hasReclaim = item.reclaimableBytes > 0;
    return InkWell(
      key: Key('smart_scan_recommendation_${item.kind.name}'),
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PhosphorIcon(
            key: const Key('smart_scan_recommendation_icon'),
            _icon,
            size: 20,
            color: Colors.white,
            duotoneSecondaryColor: Colors.white.withValues(alpha: 0.55),
            duotoneSecondaryOpacity: 0.45,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                ),
                if (hasReclaim) ...<Widget>[
                  const SizedBox(height: 1),
                  Text(
                    '${ByteFormatter.format(item.reclaimableBytes)} recoverable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
