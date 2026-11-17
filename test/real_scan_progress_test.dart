import 'dart:async';
import 'dart:io';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/core/ui/circular_file_scanner.dart';

void sample(
  ScanOperation operation,
  int processed,
  int? total, {
  String request = 'request',
  String stage = 'Reading images',
  bool numeric = true,
  String outcome = 'running',
}) {
  operation.acceptNative({
    'requestId': request,
    'processed': processed,
    'total': total,
    'numeric': numeric,
    'stage': stage,
    'outcome': outcome,
  }, request);
}

Widget host({
  double? progress,
  String id = 'one',
  bool succeeded = false,
  bool active = true,
}) => MaterialApp(
  home: Center(
    child: CircularFileScanner(
      progress: progress,
      scanId: id,
      succeeded: succeeded,
      active: active,
    ),
  ),
);
CustomPainter painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byKey(const Key('circular_file_scanner_paint')))
    .painter!;
void Function(Canvas) drawing(WidgetTester tester) =>
    (canvas) => painter(tester).paint(canvas, const Size.square(228));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Measured operation accounting', () {
    test('a fresh scan has no fabricated denominator', () {
      final operation = ScanOperation(numeric: true);
      expect(operation.snapshot.processed, 0);
      expect(operation.snapshot.total, isNull);
      expect(operation.snapshot.fraction, isNull);
      operation.cancel();
    });
    test('processed-work counts drive fractions, never time', () async {
      final operation = ScanOperation(numeric: true);
      await operation.run(() async {
        for (final count in [100, 250, 500, 750]) {
          sample(operation, count, 1000);
          expect(operation.snapshot.fraction, count / 1000);
        }
        await Future<void>.delayed(Duration.zero);
        expect(operation.snapshot.fraction, .75);
      });
      expect(operation.snapshot.fraction, 1);
      expect(operation.snapshot.successful, isTrue);
    });
    test(
      'out of order and invalid counters cannot rewind or overshoot',
      () async {
        final operation = ScanOperation(numeric: true);
        await operation.run(() async {
          sample(operation, 500, 1000);
          sample(operation, 250, 1000);
          expect(operation.snapshot.fraction, .5);
          sample(operation, 1100, 1000);
          sample(operation, -1, 1000);
          expect(operation.snapshot.fraction, .5);
        });
      },
    );
    test(
      '1000/1000 native rows cannot finish required Flutter analysis',
      () async {
        final gate = Completer<void>();
        final operation = ScanOperation(numeric: true);
        final pending = operation.run(() async {
          sample(operation, 750, 1000);
          sample(operation, 1000, 1000, outcome: 'succeeded');
          operation.stage('Aggregating results');
          await gate.future;
        });
        expect(operation.snapshot.fraction, .75);
        expect(operation.snapshot.successful, isFalse);
        gate.complete();
        await pending;
        expect(operation.snapshot.fraction, 1);
      },
    );
    test(
      'unknown totals and composite stage counts stay indeterminate',
      () async {
        final operation = ScanOperation();
        await operation.run(() async {
          sample(operation, 230, null, stage: 'Discovering folders');
          expect(operation.snapshot.fraction, isNull);
          sample(operation, 900, 1000, stage: 'Hashing');
          expect(operation.snapshot.fraction, isNull);
          sample(operation, 1000, 1000, stage: 'Hashing');
          operation.stage('Comparing');
          expect(operation.snapshot.fraction, isNull);
        });
        expect(operation.snapshot.fraction, 1);
      },
    );
    test(
      'a parent waits for all concurrent branches and final analysis',
      () async {
        final parent = ScanOperation();
        final first = Completer<void>(), second = Completer<void>();
        final a = ScanOperation(numeric: true),
            b = ScanOperation(numeric: true);
        final pending = parent.run(() async {
          await Future.wait([
            a.run(() async {
              sample(a, 100, 100);
              await first.future;
            }),
            b.run(() async {
              sample(b, 1, 10);
              await second.future;
            }),
          ]);
          parent.stage('Evaluating recommendations');
          expect(parent.snapshot.successful, isFalse);
        });
        first.complete();
        await Future<void>.delayed(Duration.zero);
        expect(parent.snapshot.fraction, isNull);
        expect(parent.snapshot.successful, isFalse);
        second.complete();
        await pending;
        expect(parent.snapshot.successful, isTrue);
      },
    );
    test(
      'successfully empty scans complete without dividing by zero',
      () async {
        final operation = ScanOperation(numeric: true);
        await operation.run(() async {
          sample(operation, 0, 0);
          expect(operation.snapshot.fraction, isNull);
        });
        expect(operation.snapshot.fraction, 1);
      },
    );
    test('failure after discovery never produces success', () async {
      final operation = ScanOperation(numeric: true);
      await expectLater(
        operation.run<void>(() async {
          sample(operation, 9, 10);
          throw PlatformException(code: 'SCAN_PERMISSION_DENIED');
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(operation.snapshot.outcome, ScanOutcome.failed);
      expect(operation.snapshot.fraction, .9);
    });
    test(
      'partial/unreadable results retain their payload, not a success ring',
      () async {
        final operation = ScanOperation();
        final result = await operation.run(() async {
          sample(operation, 10, 10, outcome: 'partial');
          return {'preserved': 42};
        });
        expect(result, {'preserved': 42});
        expect(operation.snapshot.outcome, ScanOutcome.partial);
        expect(operation.snapshot.fraction, isNull);
      },
    );
    test('cancellation ignores late completion and stale callbacks', () async {
      final operation = ScanOperation(numeric: true);
      final gate = Completer<void>();
      final pending = operation.run(() async {
        sample(operation, 3, 10);
        await gate.future;
      });
      operation.cancel();
      sample(operation, 10, 10);
      gate.complete();
      await pending;
      expect(operation.snapshot.outcome, ScanOutcome.cancelled);
      expect(operation.snapshot.fraction, .3);
    });
    test(
      'detaching a screen does not cancel provider-owned shared work',
      () async {
        final parent = ScanOperation(), child = ScanOperation();
        final gate = Completer<void>();
        final pending = parent.run(() => child.run(() => gate.future));
        parent.cancel();
        expect(child.snapshot.outcome, ScanOutcome.running);
        gate.complete();
        await pending;
        expect(child.snapshot.successful, isTrue);
        expect(parent.snapshot.outcome, ScanOutcome.cancelled);
      },
    );
    test('cached partial work cannot become a new consumer success', () async {
      final registry = ScanProgressRegistry();
      final child = registry.begin('cached');
      final preserved = await child.run(() async {
        child.markIncomplete();
        return 42;
      });
      final parent = ScanOperation();
      expect(
        await parent.run(() async {
          registry.attachCurrent('cached');
          return preserved;
        }),
        42,
      );
      expect(parent.snapshot.outcome, ScanOutcome.partial);
      expect(parent.snapshot.fraction, isNull);
      registry.dispose();
    });
    test(
      'registry generations cannot be overwritten by old progress',
      () async {
        final registry = ScanProgressRegistry();
        final old = registry.begin('files');
        final fresh = registry.begin('files');
        sample(old, 9, 10);
        expect((await registry.watch('files').first).id, fresh.id);
        expect(fresh.snapshot.processed, 0);
        old.cancel();
        registry.dispose();
      },
    );
  });

  group('Native channel contract', () {
    const transport = MethodChannel('test/real-progress');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      messenger.setMockMethodCallHandler(transport, null);
      messenger.setMockMethodCallHandler(NativeScanRequest.channel, null);
    });
    test(
      'terminal envelope preserves original data and partial status',
      () async {
        messenger.setMockMethodCallHandler(transport, (call) async {
          expect((call.arguments as Map)['progressId'], isA<String>());
          return {
            'scanPayload': {
              'files': [1, 2],
            },
            'scanOutcome': 'partial',
          };
        });
        final operation = ScanOperation();
        final result = await operation.run(
          () => NativeScanRequest.invokeMap(transport, 'scan', {}),
        );
        expect(result, {
          'files': [1, 2],
        });
        expect(operation.snapshot.outcome, ScanOutcome.partial);
      },
    );
    test(
      'missing plugin cannot be converted into a success by a caller fallback',
      () async {
        final operation = ScanOperation();
        await operation.run(() async {
          try {
            await NativeScanRequest.invokeMap(transport, 'scan', {});
          } on MissingPluginException {
            /* Existing repositories retain fallback data. */
          }
        });
        expect(operation.snapshot.outcome, ScanOutcome.partial);
      },
    );
    test('only its owner can cancel a native request', () async {
      final cancellations = <String>[];
      messenger.setMockMethodCallHandler(NativeScanRequest.channel, (
        call,
      ) async {
        cancellations.add((call.arguments as Map)['requestId'] as String);
        return null;
      });
      final a = ScanOperation(), b = ScanOperation();
      final ra = a.request(), rb = b.request();
      a.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(cancellations, [ra.id]);
      expect(b.snapshot.outcome, ScanOutcome.running);
      rb.close();
      b.cancel();
    });
    test(
      'provider invalidation cooperatively cancels its native work',
      () async {
        final gate = Completer<Map<Object?, Object?>?>();
        final cancelled = <String>[];
        messenger.setMockMethodCallHandler(transport, (call) => gate.future);
        messenger.setMockMethodCallHandler(NativeScanRequest.channel, (
          call,
        ) async {
          cancelled.add((call.arguments as Map)['requestId'] as String);
          return null;
        });
        final provider = FutureProvider(
          (ref) => observeScan(
            ref,
            'owned',
            () => NativeScanRequest.invokeMap(transport, 'scan', {}),
          ),
        );
        final container = ProviderContainer();
        final future = container.read(provider.future);
        await Future<void>.delayed(Duration.zero);
        container.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(cancelled.length, 1);
        gate.complete({'files': []});
        // Riverpod's disposed future is intentionally not awaited by consumers.
        unawaited(future.then<void>((_) {}, onError: (Object _) {}));
      },
    );
  });

  group('Real clockwise geometry', () {
    testWidgets('zero and unknown totals never draw a rotating blue arc', (
      tester,
    ) async {
      await tester.pumpWidget(host(progress: 0));
      expect(drawing(tester), paintsExactlyCountTimes(#drawArc, 0));
      await tester.pumpWidget(host());
      await tester.pump(const Duration(seconds: 30));
      expect(drawing(tester), paintsExactlyCountTimes(#drawArc, 0));
      expect(
        CircularFileScanner.motionDuration,
        const Duration(milliseconds: 5800),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
      '12 oclock clockwise sweep and leading marker stay fixed between updates',
      (tester) async {
        await tester.pumpWidget(host(progress: .25));
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          drawing(tester),
          paints
            ..arc(
              startAngle: -math.pi / 2,
              sweepAngle: math.pi / 2,
              strokeCap: StrokeCap.butt,
              useCenter: false,
            )
            ..circle(x: 228 / 2 + 228 * .43, y: 228 / 2, radius: 228 * .023),
        );
        await tester.pump(const Duration(seconds: 12));
        expect(
          drawing(tester),
          paints..arc(startAngle: -math.pi / 2, sweepAngle: math.pi / 2),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'smooth interpolation never exceeds the last confirmed fraction',
      (tester) async {
        await tester.pumpWidget(host(progress: 0));
        await tester.pumpWidget(host(progress: .5));
        for (int i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          expect(
            drawing(tester),
            paints..something(
              (method, args) =>
                  method == #drawArc &&
                  (args[2] as double) >= 0 &&
                  (args[2] as double) <= math.pi,
            ),
          );
        }
        await tester.pumpWidget(host(progress: .1));
        await tester.pump(const Duration(milliseconds: 300));
        expect(drawing(tester), paints..arc(sweepAngle: math.pi));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets('only whole-operation success authorizes 360 degrees', (
      tester,
    ) async {
      await tester.pumpWidget(host(progress: .75));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpWidget(host(progress: 1));
      await tester.pump(const Duration(milliseconds: 250));
      expect(drawing(tester), paints..arc(sweepAngle: math.pi * 1.5));
      await tester.pumpWidget(host(progress: 1, succeeded: true));
      await tester.pump(const Duration(milliseconds: 250));
      expect(drawing(tester), paints..arc(sweepAngle: math.pi * 2));
      await tester.pumpWidget(host(progress: 0, id: 'fresh'));
      expect(drawing(tester), paintsExactlyCountTimes(#drawArc, 0));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  test('release version and Android Flutter wiring remain correct', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.1+2'));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('versionName = flutter.versionName'));
    expect(gradle, contains('versionCode = flutter.versionCode'));
    expect(
      gradle,
      contains('applicationId = "com.KoreAppsTek.PhoneStorageCleaner"'),
    );
  });
}
