import 'package:flutter/material.dart';

/// A consistent "nothing here" view.
///
/// The app grew twelve hand-rolled empty states with slightly different
/// spacing, icon sizes, and wording structure. This is the shared shape:
/// icon, what is true, and what the user can do about it.
///
/// ## Accessibility
///
/// The icon is marked decorative so a screen reader announces the message
/// rather than "image". The heading is flagged as a header, so users
/// navigating by heading can find it.
///
/// ## Layout
///
/// Always scrollable, so it works inside a `RefreshIndicator` and cannot
/// overflow on a short screen or at a large text scale — an empty state that
/// throws a layout error is worse than no empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.viewKey,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Optional call to action.
  final Widget? action;

  /// Key on the scrollable, so screens keep their existing test keys.
  final Key? viewKey;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: viewKey,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(icon, size: 56, color: colors.primary),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (action != null) ...<Widget>[
          const SizedBox(height: 20),
          Center(child: action),
        ],
      ],
    );
  }
}
