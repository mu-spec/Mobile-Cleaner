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
            onTap: hasRec ? () => onOpen(advice.value!.first.kind) : onScan,
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 60),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: advice.when(
                  loading: () => const _ScanNowState(),
                  error: (Object error, StackTrace stackTrace) => const _ScanNowState(),
                  data: (List<Recommendation> found) {
                    if (found.isEmpty) {
                      return _ScanNowState(onScan: onScan);
                    }
                    return _RecommendationState(
                      item: found.first,
                      onOpen: () => onOpen(found.first.kind),
                    );
                  },
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
class _ScanNowState extends StatelessWidget {
  const _ScanNowState({this.onScan, super.key});

  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const PhosphorIcon(
          PhosphorIconsDuotone.sparkle,
          size: 22,
          color: HomeUpperStyle.orange,
          duotoneSecondaryColor: HomeUpperStyle.orange,
          duotoneSecondaryOpacity: 0.45,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Smart Scan',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onScan ?? () {},
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      ],
    );
  }
}

class _RecommendationState extends StatelessWidget {
  const _RecommendationState({
    required this.item,
    required this.onOpen,
    super.key,
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
            duotoneSecondaryColor: Colors.white.withOpacity(0.55),
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
                      color: Colors.white.withOpacity(0.85),
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

