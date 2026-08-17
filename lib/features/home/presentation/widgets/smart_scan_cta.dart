import 'package:flutter/material.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';

/// The primary action on Home.
///
/// One full-width button, visually heavier than anything else on the screen,
/// so there is never a question about what to do first.
///
/// The privacy line sits directly under it rather than in Settings or a
/// policy page. A storage cleaner asks for broad file access, and the moment
/// the user is deciding whether to let it scan is exactly when the reassurance
/// is worth something. It is also true of this build: the app has no INTERNET
/// permission at all.
class SmartScanCta extends StatelessWidget {
  const SmartScanCta({required this.onScan, super.key});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('smart_scan_button'),
            onPressed: onScan,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
            // 'Scan now' is the action; the section heading above already
            // says what the feature is called.
            label: const Text('Scan now'),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Files stay on your device.',
                key: const Key('smart_scan_privacy_note'),
                maxLines: 2,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A compact, tappable row used by the Quick tools list.
///
/// A row rather than a large card: four oversized tiles pushed everything
/// else below the fold and gave secondary tools the same visual weight as the
/// primary action. Rows keep the hierarchy honest and fit far more in.
class HomeToolRow extends StatelessWidget {
  const HomeToolRow({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
    super.key,
  });

  final Key rowKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      children: <Widget>[
        InkWell(
          key: rowKey,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HomeMetrics.rowMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                children: <Widget>[
                  HomeIconTile(icon: icon),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: HomeMetrics.rowIconSize,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 70, color: colors.outlineVariant),
      ],
    );
  }
}
