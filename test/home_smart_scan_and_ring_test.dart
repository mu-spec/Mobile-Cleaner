import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/app/route_observer.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/radar_painter.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/smart_scan_cta.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/storage_overview_card.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

void main() {
  group('Storage ring animation', () {
    const StorageInfo info = StorageInfo(totalBytes: 1000, freeBytes: 270);

    setUp(() => setStorageHomeVisible(true));

    test('usedFraction is normalized', () {
      expect(info.usedFraction, closeTo(0.73, 0.0001));
      expect(info.usedPercentage, 73);
    });

    testWidgets('summary icon and bar use the same real storage fraction', (
      WidgetTester tester,
    ) async {
      await _pumpStorageRing(tester, info: info);

      expect(find.byKey(const Key('storage_database_icon')), findsOneWidget);
      expect(find.byKey(const Key('storage_usage_track')), findsOneWidget);
      final FractionallySizedBox fill = tester.widget<FractionallySizedBox>(
        find.byKey(const Key('storage_usage_fill')),
      );
      expect(fill.widthFactor, closeTo(info.usedFraction, 0.0001));
      expect(find.text('Internal storage'), findsOneWidget);
    });

    testWidgets('painter starts at zero and reaches usedFraction', (
      WidgetTester tester,
    ) async {
      await _pumpStorageRing(tester, info: info);

      final dynamic initialPainter = _ringPainter(tester);
      expect(initialPainter.usedFraction as double, closeTo(0, 0.0001));
      expect(find.text('73%'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      final dynamic middlePainter = _ringPainter(tester);
      final double middleFraction = middlePainter.usedFraction as double;
      expect(middleFraction, greaterThan(0));
      expect(middleFraction, lessThan(info.usedFraction * 0.25));
      expect(find.text('73%'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1800));
      final dynamic finalPainter = _ringPainter(tester);
      expect(
        finalPainter.usedFraction as double,
        closeTo(info.usedFraction, 0.0001),
      );
      expect(find.text('73%'), findsOneWidget);
    });

    testWidgets('painter repaints when the animated fraction changes', (
      WidgetTester tester,
    ) async {
      await _pumpStorageRing(tester, info: info);
      final dynamic initialPainter = _ringPainter(tester);

      await tester.pump(const Duration(milliseconds: 600));
      final dynamic progressedPainter = _ringPainter(tester);

      expect(progressedPainter.shouldRepaint(initialPainter) as bool, isTrue);
    });

    testWidgets('reduced motion paints the final fraction immediately', (
      WidgetTester tester,
    ) async {
      await _pumpStorageRing(tester, info: info, disableAnimations: true);

      final dynamic painter = _ringPainter(tester);
      expect(
        painter.usedFraction as double,
        closeTo(info.usedFraction, 0.0001),
      );
      expect(find.text('73%'), findsOneWidget);
    });

    testWidgets('returning to Home restarts the finite animation', (
      WidgetTester tester,
    ) async {
      await _pumpStorageRing(tester, info: info);
      await tester.pump(const Duration(milliseconds: 2400));
      expect(
        (_ringPainter(tester).usedFraction as double),
        closeTo(info.usedFraction, 0.0001),
      );

      setStorageHomeVisible(false);
      setStorageHomeVisible(true);
      await tester.pump();
      expect((_ringPainter(tester).usedFraction as double), closeTo(0, 0.0001));
      expect(find.text('73%'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2400));
      expect(
        (_ringPainter(tester).usedFraction as double),
        closeTo(info.usedFraction, 0.0001),
      );
    });

    testWidgets('popping a pushed screen restarts the finite animation', (
      WidgetTester tester,
    ) async {
      await _pumpStorageRing(
        tester,
        info: info,
        navigatorObservers: <NavigatorObserver>[storageRouteObserver],
      );
      await tester.pump(const Duration(milliseconds: 2400));

      final BuildContext homeContext = tester.element(
        find.byType(StorageOverviewCard),
      );
      Navigator.of(homeContext).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              const Scaffold(body: Center(child: Text('Pushed screen'))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      Navigator.of(homeContext).pop();
      await tester.pump();
      expect((_ringPainter(tester).usedFraction as double), closeTo(0, 0.0001));
      expect(find.text('73%'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2400));
      expect(
        (_ringPainter(tester).usedFraction as double),
        closeTo(info.usedFraction, 0.0001),
      );
    });
  });

  group('Smart Scan card redesign', () {
    testWidgets('Smart Scan title and sparkle removed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SmartScanCta(onScan: () {}, onOpen: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('Smart Scan'), findsNothing);
      expect(find.byType(PhosphorIcon), findsWidgets); // radar icon allowed
    });

    testWidgets('Scan Now button always visible', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SmartScanCta(onScan: () {}, onOpen: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('Scan Now'), findsOneWidget);
    });

    testWidgets('recommendation remains visible when present', (
      WidgetTester tester,
    ) async {
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
              body: SmartScanCta(onScan: () {}, onOpen: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('Clean up duplicates'), findsOneWidget);
      expect(find.text('Scan Now'), findsOneWidget);
    });

    testWidgets('Scan Now triggers scan', (WidgetTester tester) async {
      bool scanned = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SmartScanCta(onScan: () => scanned = true, onOpen: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.tap(find.text('Scan Now'));
      await tester.pump();
      expect(scanned, isTrue);
    });

    testWidgets('radar visual present', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SmartScanCta(onScan: () {}, onOpen: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.byKey(const Key('premium_radar_visual')), findsOneWidget);
      expect(find.byKey(const Key('premium_radar_paint')), findsOneWidget);

      final CustomPaint initial = tester.widget<CustomPaint>(
        find.byKey(const Key('premium_radar_paint')),
      );
      final RadarPainter initialPainter = initial.painter! as RadarPainter;
      await tester.pump(const Duration(milliseconds: 500));
      final CustomPaint progressed = tester.widget<CustomPaint>(
        find.byKey(const Key('premium_radar_paint')),
      );
      final RadarPainter progressedPainter =
          progressed.painter! as RadarPainter;
      expect(progressedPainter.rotation, isNot(initialPainter.rotation));
      expect(progressedPainter.shouldRepaint(initialPainter), isTrue);
    });

    testWidgets('radar is static when reduced motion is requested', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: SmartScanCta(onScan: () {}, onOpen: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final RadarPainter initial =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('premium_radar_paint')),
                  )
                  .painter!
              as RadarPainter;

      await tester.pump(const Duration(seconds: 2));
      final RadarPainter afterDelay =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('premium_radar_paint')),
                  )
                  .painter!
              as RadarPainter;

      expect(afterDelay.rotation, initial.rotation);
    });
  });
}

Future<void> _pumpStorageRing(
  WidgetTester tester, {
  required StorageInfo info,
  bool disableAnimations = false,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageOverviewProvider.overrideWithValue(
          AsyncValue<StorageInfo>.data(info),
        ),
      ],
      child: MaterialApp(
        navigatorObservers: navigatorObservers,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: const StorageOverviewCard(),
          ),
        ),
      ),
    ),
  );
}

dynamic _ringPainter(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.byKey(const Key('storage_ring_paint')),
  );
  return paint.painter;
}
