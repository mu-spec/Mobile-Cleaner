import 'package:flutter/material.dart';

class RecommendationsCard extends StatelessWidget {
  const RecommendationsCard({required this.onScan, super.key});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      key: const Key('recommendations_section'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                Icons.lightbulb_rounded,
                color: colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Recommendations',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Run Smart Scan to get safe, personalized cleanup suggestions.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    key: const Key('recommendations_scan'),
                    onPressed: onScan,
                    child: const Text('Scan now'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
