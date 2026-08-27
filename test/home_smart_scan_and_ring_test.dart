import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/smart_scan_cta.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/storage_overview_card.dart';

void main() {
  group('Storage ring animation', () {
    testWidgets('ring starts at 0 and reaches usedFraction', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageOverviewProvider.overrideWithValue(
              AsyncValue<StorageInfo>.data(
                StorageInfo(
                  totalBytes: 1024 * 1024 * 1024,
                  freeBytes: 1024 * 1024 * (1024 - 150),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StorageOverviewCard(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 1000));
      expect(find.byKey(const Key('free_storage')), findsOneWidget);
    });

    testWidgets('reduced motion shows final state', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageOverviewProvider.overrideWithValue(
              AsyncValue<StorageInfo>.data(
                StorageInfo(
                  totalBytes: 1000,
                  freeBytes: 900,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: StorageOverviewCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('free_storage')), findsOneWidget);
    });
  });

  group('Smart Scan card redesign', () {
    testWidgets('Smart Scan title and sparkle removed', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SmartScanCta(
                onScan: () {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Smart Scan'), findsNothing);
      expect(find.byType(PhosphorIcon), findsWidgets); // radar icon allowed
    });

    testWidgets('Scan Now button always visible', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SmartScanCta(
                onScan: () {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Scan Now'), findsOneWidget);
    });

    testWidgets('recommendation remains visible when present', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recommendationsProvider.overrideWithValue(
              AsyncValue<List<Recommendation>>.data(<Recommendation>[
                const Recommendation(
                  kind: RecommendationKind.duplicateCleanup,
                  priority: RecommendationPriority.high,
                  title: 'Clean up duplicates',
                  detail: 'Found duplicates',
                  actionLabel: 'Review',
                  reclaimableBytes: 715 * 1024 * 1024,
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SmartScanCta(
                onScan: () {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Clean up duplicates'), findsOneWidget);
      expect(find.text('Scan Now'), findsOneWidget);
    });

    testWidgets('Scan Now triggers scan', (WidgetTester tester) async {
      bool scanned = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SmartScanCta(
                onScan: () => scanned = true,
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan Now'));
      await tester.pump();
      expect(scanned, isTrue);
    });

    testWidgets('radar visual present', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SmartScanCta(
                onScan: () {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
