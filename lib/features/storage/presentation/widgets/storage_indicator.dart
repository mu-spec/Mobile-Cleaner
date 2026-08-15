import 'package:flutter/material.dart';

class StorageIndicator extends StatelessWidget {
  const StorageIndicator({
    required this.usedFraction,
    required this.usedPercentage,
    super.key,
  });

  final double usedFraction;
  final int usedPercentage;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      label: '$usedPercentage percent of storage used',
      child: SizedBox.square(
        dimension: 132,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: usedFraction,
                strokeWidth: 13,
                strokeCap: StrokeCap.round,
                color: colors.primary,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$usedPercentage%',
                  key: const Key('storage_percentage'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  'used',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
