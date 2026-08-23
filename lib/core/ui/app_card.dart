import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';

/// The one card surface of the design system.
///
/// White (dark surface in dark mode), [AppRadius.card] corners, and a soft
/// hairline border — all inherited from the app-level [CardThemeData] so
/// every screen that adopts it stays in lockstep automatically.
///
/// Pass [onTap] to make the whole card one tappable surface with a correctly
/// clipped ripple.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.padding = AppSpacing.card,
    this.cardKey,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Key placed on the [Card] itself, useful for layout assertions in tests.
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final Widget body = Padding(padding: padding, child: child);

    return Card(
      key: cardKey,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}
