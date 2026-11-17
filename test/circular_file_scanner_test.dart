import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/core/ui/circular_file_scanner.dart';
import 'package:phone_storage_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:phone_storage_cleaner/features/files/presentation/widgets/photo_tool_ui.dart';

Widget _host({
  double? progress,
  bool active = true,
  bool completed = false,
  bool enabled = true,
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
  double size = 228,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: TickerMode(
        enabled: enabled,
        child: Center(
          child: CircularFileScanner(
            progress: progress,
            active: active,
            completed: completed,
            size: size,
          ),
        ),
      ),
    ),
  );
}

CustomPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byKey(const Key('circular_file_scanner_paint')))
    .painter!;

String? _semanticsValue(WidgetTester tester) => tester
    .widget<Semantics>(find.byKey(const Key('scan_progress_semantics')))
    .properties
    .value;

void main() {
  testWidgets(
    'unknown progress is activity, never an elapsed-time percentage',
    (WidgetTester tester) async {
      await tester.pumpWidget(_host());
      expect(_semanticsValue(tester), 'Scanning');
      expect(find.byKey(const Key('scan_folder_icon')), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      int repaints = 0;
      final CustomPainter painter = _painter(tester);
      void repaint() => repaints++;
      painter.addListener(repaint);

      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 8));
      }
      expect(repaints, greaterThanOrEqualTo(5));
      expect(_semanticsValue(tester), 'Scanning');
      expect(find.byKey(const Key('scan_complete_icon')), findsNothing);
      painter.removeListener(repaint);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('determinate progress changes only when supplied by the caller', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(progress: 0.37));
    expect(_semanticsValue(tester), '37 percent');
    await tester.pump(const Duration(seconds: 20));
    expect(_semanticsValue(tester), '37 percent');
    await tester.pumpWidget(_host(progress: 0.72));
    expect(_semanticsValue(tester), '72 percent');
    await tester.pumpWidget(_host(progress: 0));
    expect(_semanticsValue(tester), '0 percent');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completion stops motion and shows a static completion mark', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(_host(completed: true));
    expect(_semanticsValue(tester), 'Scan complete');
    expect(find.byKey(const Key('scan_complete_icon')), findsOneWidget);
    expect(find.byKey(const Key('scan_folder_icon')), findsNothing);
    int repaints = 0;
    final CustomPainter painter = _painter(tester);
    void repaint() => repaints++;
    painter.addListener(repaint);
    await tester.pump(const Duration(seconds: 20));
    expect(repaints, 0);
    painter.removeListener(repaint);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive on failure or cancellation stops, retry restarts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_host(active: false));
    expect(_semanticsValue(tester), 'Scan paused');
    int repaints = 0;
    final CustomPainter painter = _painter(tester);
    void repaint() => repaints++;
    painter.addListener(repaint);
    await tester.pump(const Duration(seconds: 12));
    expect(repaints, 0);
    painter.removeListener(repaint);

    await tester.pumpWidget(_host());
    final CustomPainter restarted = _painter(tester);
    restarted.addListener(repaint);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(repaints, greaterThan(0));
    restarted.removeListener(repaint);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('offstage TickerMode and reduced motion do not keep ticking', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pumpWidget(_host(enabled: false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_host(reduceMotion: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan_folder_icon')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(_semanticsValue(tester), 'Scanning');
  });

  testWidgets('backgrounding pauses motion, foregrounding resumes it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposal during an active scan leaves no animation ticker', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 20));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both themes and compact loading area paint without overflow', (
    WidgetTester tester,
  ) async {
    for (final Brightness brightness in Brightness.values) {
      await tester.pumpWidget(_host(brightness: brightness, size: 92));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.getSize(find.byType(CircularFileScanner)),
        const Size.square(92),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('all shared file and photo loading states use the scanner', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FilesScanningView())),
    );
    expect(find.byType(CircularFileScanner), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PhotoToolLoadingState(
            icon: Icons.photo,
            title: 'Comparing photos',
            description: 'Analyzing files on device.',
          ),
        ),
      ),
    );
    expect(find.byType(CircularFileScanner), findsOneWidget);
    expect(find.text('Comparing photos'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
