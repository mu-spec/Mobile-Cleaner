import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// A compact, full-width Smart Scan action.
///
/// Replaces the earlier large hero card and radar illustration with one
/// premium gradient button so the upper Home stays compact. It names the
/// feature on the left (a small orange-accented sparkle plus "Smart Scan")
/// and shows a forward arrow on the right. Tapping it routes through the
/// existing [onScan] callback — navigation and scan behaviour are
/// unchanged. No radar artwork, description, fake percentage, or fake
/// results are shown.
class SmartScanCta extends ConsumerWidget {
  const SmartScanCta({
    required this.onScan,
    required this.onOpen,
    super.key,
  });

  final VoidCallback onScan;
  final ValueChanged<RecommendationKind> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Recommendation>> advice = ref.watch(recommendationsProvider);
    final bool hasRec = advice.hasValue && advice.value!.isNotEmpty;
    return Semantics(
      button: true,
      label: 'Smart Scan',
      child: Material(
        key: const Key('smart_scan_hero'),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                HomeUpperStyle.deepBlue,
                HomeUpperStyle.primaryBlue,
              ],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: HomeUpperStyle.primaryBlue.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: InkWell(
            key: const Key('smart_scan_button'),
            onTap: () {
              if (hasRec) {
                onOpen(advice.value!.first.kind);
              } else {
                onScan();
              }
            },
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 76),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const PhosphorIcon(
                          PhosphorIconsDuotone.sparkle,
                          size: 20,
                          color: HomeUpperStyle.orange,
                          duotoneSecondaryColor: HomeUpperStyle.orange,
                          duotoneSecondaryOpacity: 0.45,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Smart Scan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              height: 1.1,
                            ),
                          ),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                          ),
                          child: const Center(
                            child: PhosphorIcon(
                              PhosphorIconsDuotone.sparkle,
                              size: 14,
                              color: Colors.white70,
                              duotoneSecondaryOpacity: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    advice.when(
                      loading: () => const SizedBox.shrink(),
                      error: (Object error, StackTrace stackTrace) => const SizedBox.shrink(),
                      data: (List<Recommendation> found) {
                        if (found.isNotEmpty) {
                          return InkWell(
                            onTap: () => onOpen(found.first.kind),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: _RecommendationState(
                                item: found.first,
                                onOpen: () => onOpen(found.first.kind),
                              ),
                            ),
                          );
                        }
                        return const Text(
                          'No recommendations yet',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: TextButton(
                        onPressed: onScan,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Scan Now',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
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

/// Left sparkle + label, right forward arrow. Height stays in the 58–64dp
/// band while still reflowing vertically at large accessibility text
/// scales instead of overflowing.
class _RecommendationState extends StatelessWidget {
  const _RecommendationState({
    required this.item,
    required this.onOpen,
  });

  final Recommendation item;
  final VoidCallback onOpen;

  IconData get _icon => switch (item.kind) {
        RecommendationKind.screenshotReview => PhosphorIconsDuotone.image,
        RecommendationKind.duplicateCleanup => PhosphorIconsDuotone.files,
        RecommendationKind.largeVideoReview => PhosphorIconsDuotone.playCircle,
      };

  @override
  Widget build(BuildContext context) {
    final bool hasReclaim = item.reclaimableBytes > 0;
    return InkWell(
      key: Key('smart_scan_recommendation_${item.kind.name}'),
      onTap: onOpen,
      borderRadius: BorderRadius.circular(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          PhosphorIcon(
            _icon,
            size: 22,
            color: Colors.white,
            duotoneSecondaryColor: Colors.white.withValues(alpha: 0.55),
            duotoneSecondaryOpacity: 0.45,
          ),
          const SizedBox(width: 10),
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
                  const SizedBox(height: 2),
                  Text(
                    '${ByteFormatter.format(item.reclaimableBytes)} recoverable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}

