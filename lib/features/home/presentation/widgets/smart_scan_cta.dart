import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';

/// A compact, full-width Smart Scan action.
///
/// Replaces the earlier large hero card and radar illustration with one
/// premium gradient button so the upper Home stays compact. It names the
/// feature on the left (a small orange-accented sparkle plus "Smart Scan")
/// and shows a forward arrow on the right. Tapping it routes through the
/// existing [onScan] callback — navigation and scan behaviour are
/// unchanged. No radar artwork, description, fake percentage, or fake
/// results are shown.
class SmartScanCta extends StatelessWidget {
  const SmartScanCta({required this.onScan, super.key});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
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
            onTap: onScan,
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 60),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Center(child: _CompactScanContent()),
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
class _CompactScanContent extends StatelessWidget {
  const _CompactScanContent();

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1);

    final Widget copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Smart Scan',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          'Find and clean unnecessary files',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 10.5,
            height: 1.15,
          ),
        ),
      ],
    );

    const Widget arrow = Icon(
      Icons.arrow_forward_rounded,
      size: 20,
      color: Colors.white,
    );

    // At very large text sizes the content is allowed to grow vertically
    // (centered) rather than overflow horizontally.
    if (textScale > 1.4) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: HomeUpperStyle.orange,
              ),
              const SizedBox(width: 8),
              Flexible(child: copy),
            ],
          ),
          const SizedBox(height: 6),
          arrow,
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.auto_awesome_rounded,
            size: 18,
            color: HomeUpperStyle.orange,
          ),
          const SizedBox(width: 8),
          Expanded(child: copy),
          const SizedBox(width: 8),
          arrow,
        ],
      ),
    );
  }
}
