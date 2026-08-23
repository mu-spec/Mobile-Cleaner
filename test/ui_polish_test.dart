import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/core/ui/empty_state.dart';
import 'package:mobile_cleaner/core/ui/haptics.dart';
import 'package:mobile_cleaner/core/ui/responsive.dart';
import 'package:mobile_cleaner/core/ui/success_check.dart';

/// Records haptic calls made through the platform channel.
List<String> _captureHaptics() {
  final List<String> calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall call,
      ) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String? ?? 'vibrate');
        }
        return null;
      });
  return calls;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
  Size size = const Size(420, 900),
  bool disableAnimations = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // Platform-channel mocks are process-global. Never let a haptics stub
    // leak into later MaterialApp tests, where Flutter legitimately sends
    // SystemChrome.setApplicationSwitcherDescription on the same channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('Haptics', () {
    testWidgets('each level reaches the platform', (
      WidgetTester tester,
    ) async {
      final List<String> calls = _captureHaptics();

      Haptics.selection();
      Haptics.light();
      Haptics.warning();
      Haptics.success();
      await tester.pump();

      expect(calls, hasLength(4));
    });

    testWidgets('a device with no vibrator does not break the action', (
      WidgetTester tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'HapticFeedback.vibrate') {
              throw PlatformException(code: 'UNAVAILABLE');
            }
            // SystemChrome and other real framework traffic shares this
            // channel and is unrelated to the no-vibrator scenario.
            return null;
          });

      // Fire-and-forget: a failure here must never surface to the user.
      expect(Haptics.selection, returnsNormally);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('SuccessCheck', () {
    testWidgets('settles, so pumpAndSettle cannot hang', (
      WidgetTester tester,
    ) async {
      // A looping animation would make this time out — the risk that would
      // have broken every widget test reaching the cleanup screen.
      await _pump(tester, const SuccessCheck());

      expect(find.byKey(const Key('success_check')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('honours the reduce-animations accessibility setting', (
      WidgetTester tester,
    ) async {
      await _pump(tester, const SuccessCheck(), disableAnimations: true);

      // Jumps to the final frame rather than animating.
      final FadeTransition fade = tester.widget<FadeTransition>(
        find.byType(FadeTransition).first,
      );
      expect(fade.opacity.value, 1.0);
    });

    testWidgets('animates to completion when animations are enabled', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: false),
            child: Scaffold(body: SuccessCheck()),
          ),
        ),
      );
      await tester.pump();

      // Mid-flight it is not yet fully shown.
      await tester.pump(const Duration(milliseconds: 100));
      final FadeTransition midway = tester.widget<FadeTransition>(
        find.byType(FadeTransition).first,
      );
      expect(midway.opacity.value, lessThan(1.0));

      await tester.pumpAndSettle();
      final FadeTransition done = tester.widget<FadeTransition>(
        find.byType(FadeTransition).first,
      );
      expect(done.opacity.value, 1.0);
    });
  });

  group('EmptyState', () {
    testWidgets('shows the message and marks the icon decorative', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const EmptyState(
          viewKey: Key('demo_empty'),
          icon: Icons.check_circle_outline_rounded,
          title: 'All clear',
          message: 'Nothing needs attention.',
        ),
      );

      expect(find.byKey(const Key('demo_empty')), findsOneWidget);
      expect(find.text('All clear'), findsOneWidget);
      // Target this EmptyState's icon rather than framework-level semantics
      // wrappers that MaterialApp may legitimately add.
      final Finder semantics = find.byKey(
        const Key('empty_state_icon_semantics'),
      );
      expect(semantics, findsOneWidget);
      expect(tester.widget<ExcludeSemantics>(semantics).excluding, isTrue);
      expect(
        find.descendant(
          of: semantics,
          matching: find.byIcon(Icons.check_circle_outline_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('survives a large text scale on a short screen', (
      WidgetTester tester,
    ) async {
      // The combination that overflows a fixed-height empty state.
      await _pump(
        tester,
        const EmptyState(
          icon: Icons.folder_off_rounded,
          title: 'No files found',
          message:
              'Nothing in your library is visible to this app right now, so '
              'there is nothing to review or remove at the moment.',
        ),
        textScale: 2,
        size: const Size(320, 480),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders an action when given one', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        EmptyState(
          icon: Icons.refresh_rounded,
          title: 'Nothing yet',
          message: 'Try scanning again.',
          action: FilledButton(
            key: const Key('demo_action'),
            onPressed: () {},
            child: const Text('Scan'),
          ),
        ),
      );

      expect(find.byKey(const Key('demo_action')), findsOneWidget);
    });
  });

  group('Responsive', () {
    testWidgets('chip bars grow with text scale but stay bounded', (
      WidgetTester tester,
    ) async {
      late double normal;
      late double large;
      late double extreme;

      await _pump(
        tester,
        Builder(
          builder: (BuildContext context) {
            normal = Responsive.chipBarHeight(context);
            return const SizedBox();
          },
        ),
      );
      await _pump(
        tester,
        Builder(
          builder: (BuildContext context) {
            large = Responsive.chipBarHeight(context);
            return const SizedBox();
          },
        ),
        textScale: 1.5,
      );
      await _pump(
        tester,
        Builder(
          builder: (BuildContext context) {
            extreme = Responsive.chipBarHeight(context);
            return const SizedBox();
          },
        ),
        textScale: 4,
      );

      expect(normal, 52);
      // Grows, so chip labels are not clipped.
      expect(large, greaterThan(normal));
      // But capped, so an extreme scale cannot eat the screen.
      expect(extreme, 92);
    });

    testWidgets('a narrow screen is not treated as wide', (
      WidgetTester tester,
    ) async {
      late bool phone;
      late bool tablet;

      await _pump(
        tester,
        Builder(
          builder: (BuildContext context) {
            phone = Responsive.isWide(context);
            return const SizedBox();
          },
        ),
        size: const Size(400, 800),
      );
      await _pump(
        tester,
        Builder(
          builder: (BuildContext context) {
            tablet = Responsive.isWide(context);
            return const SizedBox();
          },
        ),
        size: const Size(900, 1200),
      );

      expect(phone, isFalse);
      expect(tablet, isTrue);
    });

    testWidgets('photo strips grow but never run away', (
      WidgetTester tester,
    ) async {
      late double base;
      late double huge;

      await _pump(
        tester,
        Builder(
          builder: (BuildContext context) {
            base = Responsive.photoStripHeight(context, 232);
            return const SizedBox();
          },
        ),
      );
      await _pump(
        tester,
        Builder(
          builder: (BuildContext context) {
            huge = Responsive.photoStripHeight(context, 232);
            return const SizedBox();
          },
        ),
        textScale: 5,
      );

      expect(base, 232);
      expect(huge, closeTo(232 * 1.8, 0.01));
    });
  });
}
