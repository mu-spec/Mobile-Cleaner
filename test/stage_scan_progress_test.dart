import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/core/ui/circular_file_scanner.dart';
import 'package:phone_storage_cleaner/core/ui/scan_stage_presentation.dart';
import 'package:phone_storage_cleaner/features/files/data/file_hash_repository.dart';
import 'package:phone_storage_cleaner/features/files/data/perceptual_hash_repository.dart';
import 'package:phone_storage_cleaner/features/files/data/photo_quality_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_category.dart';
import 'package:phone_storage_cleaner/features/files/domain/scanned_file.dart';
import 'package:phone_storage_cleaner/features/files/presentation/widgets/photo_tool_ui.dart';

void report(
  NativeScanRequest request,
  int sequence,
  int stage,
  int done,
  int? total, {
  String name = 'Hashing files',
  String outcome = 'running',
}) {
  request.operation.acceptNative({
    'requestId': request.id, 'sequence': sequence, 'stageIndex': stage,
    'stage': name, 'processed': done, 'total': total, 'outcome': outcome,
    'unit': 'files checked',
    // Deliberately no legacy numeric flag. The denominator is stage-scoped.
  }, request.id);
}

ScanSnapshot view(
  String stage,
  int done,
  int? total, {
  String scan = 'scan',
  ScanOutcome outcome = ScanOutcome.running,
}) => ScanSnapshot(
  id: scan,
  outcome: outcome,
  displayStage: ScanStage(
    id: stage,
    name: stage,
    processed: done,
    total: total,
    unit: 'files checked',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in ['hash', 'fingerprint', 'quality']) {
    test(
      '$kind repository preserves terminal stage and never replays cache progress',
      () async {
        final channel = MethodChannel('test/stage/$kind');
        final file = ScannedFile(
          id: 'one',
          name: 'one.jpg',
          path: '',
          uri: 'content://images/one',
          sizeBytes: 32000,
          category: FileCategory.images,
          dateModified: DateTime(2026),
        );
        final hashRepo = PlatformFileHashRepository(channel: channel);
        final fingerprintRepo = PlatformPerceptualHashRepository(
          channel: channel,
        );
        final qualityRepo = PlatformPhotoQualityRepository(channel: channel);
        Future<Map<String, Object>> runRepository() async => switch (kind) {
          'hash' => await hashRepo.hashFiles([file]),
          'fingerprint' => await fingerprintRepo.hashImages([file]),
          _ => await qualityRepo.analyzePhotos([file]),
        };
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        int invocations = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          invocations++;
          final request = (call.arguments as Map)['progressId'];
          expect((call.arguments as Map)['uris'], [file.uri]);
          return {
            'scanPayload': {
              file.uri: kind == 'quality'
                  ? {
                      'width': 100,
                      'height': 100,
                      'pixels': 10000,
                      'sharpness': 2.0,
                    }
                  : kind == 'fingerprint'
                  ? '0000000000000000:0000000000000000'
                  : 'hash',
            },
            'scanOutcome': 'succeeded',
            'scanStage': {
              'requestId': request,
              'sequence': 2,
              'stageIndex': 1,
              'stage': '$kind (current batch)',
              'processed': 1,
              'total': 1,
              'outcome': 'succeeded',
              'unit': 'files checked',
            },
          };
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final first = ScanOperation();
        await first.run(() async {
          expect((await runRepository()).keys, [file.uri]);
          expect(first.snapshot.stageFraction, 1);
          expect(first.snapshot.displayStage!.name, '$kind (current batch)');
          expect(first.snapshot.successful, isFalse);
        });
        final cached = ScanOperation();
        await cached.run(() async {
          expect((await runRepository()).keys, [file.uri]);
          expect(cached.snapshot.displayStage, isNull);
          expect(cached.snapshot.successful, isFalse);
        });
        expect(invocations, 1);
      },
    );
  }

  test(
    'measured stages reach one, reset on identity, never complete parent',
    () async {
      final operation = ScanOperation();
      final gate = Completer<void>();
      final pending = operation.run(() async {
        final request = operation.request();
        report(request, 1, 0, 3, 4);
        expect(operation.snapshot.stageFraction, .75);
        report(request, 2, 0, 4, 4);
        expect(operation.snapshot.stageFraction, 1);
        expect(operation.snapshot.successful, isFalse);
        final previous = operation.snapshot.displayStage!.id;
        // Same human label, genuine new stage generation.
        report(request, 3, 1, 0, 8);
        expect(operation.snapshot.displayStage!.id, isNot(previous));
        expect(operation.snapshot.stageFraction, 0);
        report(request, 4, 1, 2, 8);
        expect(operation.snapshot.stageFraction, .25);
        await gate.future;
        request.close();
      });
      expect(operation.snapshot.successful, isFalse);
      gate.complete();
      await pending;
      expect(operation.snapshot.successful, isTrue);
    },
  );

  test('old sequence, generation, decreasing work and changed denominators rejected', () {
    final operation = ScanOperation();
    final request = operation.request();
    report(request, 1, 0, 10, 10);
    report(request, 2, 1, 3, 20);
    final stage = operation.snapshot.displayStage;
    report(request, 1, 1, 15, 20); // out of order
    report(request, 3, 0, 10, 10); // old generation with newer sequence
    report(request, 4, 1, 2, 20); // decreasing completed work
    report(request, 5, 1, 12, 40); // a contradictory denominator
    report(request, 6, 1, 6, 20, name: 'Wrong label');
    expect(identical(operation.snapshot.displayStage, stage), isTrue);
    report(request, 7, 1, 5, 20);
    expect(operation.snapshot.stageFraction, .25);
    request.close();
    report(request, 8, 2, 8, 10); // closed request cannot introduce new work
    expect(operation.snapshot.stageFraction, .25);
    operation.cancel();
  });

  test('unregistered and malformed native events cannot create a stage', () {
    final operation = ScanOperation();
    operation.acceptNative({
      'requestId': 'foreign',
      'processed': 5,
      'total': 5,
      'sequence': 1,
      'stageIndex': 1,
    }, 'foreign');
    expect(operation.snapshot.displayStage, isNull);
    final request = operation.request();
    operation.acceptNative({
      'requestId': request.id,
      'processed': 5,
      'total': 5,
    }, request.id);
    report(request, 1, 0, -1, 10);
    report(request, 2, 0, 11, 10);
    expect(operation.snapshot.displayStage, isNull);
    operation.cancel();
  });

  test('unknown stage keeps real counts, zero total never divides by zero', () {
    final operation = ScanOperation();
    final request = operation.request();
    report(request, 1, 0, 230, null, name: 'Discovering folders');
    expect(operation.snapshot.stageFraction, isNull);
    expect(operation.snapshot.stageDescription, contains('230 files checked'));
    report(request, 2, 1, 0, 0);
    expect(operation.snapshot.stageFraction, isNull);
    report(request, 3, 1, 0, 0, outcome: 'succeeded');
    expect(operation.snapshot.stageFraction, 1);
    expect(operation.snapshot.successful, isFalse);
    operation.cancel();
    expect(operation.snapshot.successful, isFalse);
  });

  test(
    'registration priority beats callback arrival order and stays sticky',
    () {
      final operation = ScanOperation(numeric: true);
      final a = operation.request(), b = operation.request();
      report(b, 1, 0, 9, 10, name: 'B');
      expect(operation.snapshot.displayStage!.id, startsWith(a.id));
      expect(operation.snapshot.stageFraction, isNull);
      report(a, 1, 0, 1, 4, name: 'A');
      expect(operation.snapshot.stageFraction, .25);
      report(b, 2, 0, 10, 10, name: 'B');
      expect(operation.snapshot.displayStage!.name, 'A');
      expect(operation.snapshot.stageFraction, .25);
      report(a, 2, 0, 4, 4, name: 'A');
      expect(operation.snapshot.stageFraction, 1);
      a.close();
      expect(operation.snapshot.displayStage!.name, 'B');
      expect(operation.snapshot.stageFraction, 1);
      expect(operation.snapshot.successful, isFalse);
      operation.cancel();
    },
  );

  test(
    'concurrent children cannot combine one label with another fraction',
    () async {
      final parent = ScanOperation();
      final a = ScanOperation(), b = ScanOperation();
      final finishA = Completer<void>(), finishB = Completer<void>();
      late NativeScanRequest ra, rb;
      final pending = parent.run(() async {
        await Future.wait([
          a.run(() async {
            ra = a.request();
            await finishA.future;
          }),
          b.run(() async {
            rb = b.request();
            await finishB.future;
          }),
        ]);
        parent.stage('Final analysis');
      });
      report(rb, 1, 0, 9, 10, name: 'B');
      report(ra, 1, 0, 2, 4, name: 'A');
      report(rb, 2, 1, 0, 20, name: 'B next');
      expect(parent.snapshot.displayStage!.name, 'A');
      expect(parent.snapshot.stageFraction, .5);
      finishA.complete();
      await Future<void>.delayed(Duration.zero);
      expect(parent.snapshot.displayStage!.name, 'B next');
      expect(parent.snapshot.stageFraction, 0);
      finishB.complete();
      await pending;
      expect(parent.snapshot.successful, isTrue);
    },
  );

  for (final outcome in ['partial', 'failed', 'cancelled']) {
    test(
      'a full stage with $outcome never authorizes parent success',
      () async {
        final operation = ScanOperation();
        await operation.run(() async {
          final request = operation.request();
          report(request, 1, 0, 10, 10, outcome: outcome);
        });
        expect(operation.snapshot.stageFraction, 1);
        expect(operation.snapshot.outcome, ScanOutcome.partial);
        expect(operation.snapshot.successful, isFalse);
      },
    );
  }

  test(
    'cached successful/partial children propagate status, not stage replay',
    () async {
      for (final partial in [false, true]) {
        final registry = ScanProgressRegistry();
        final child = registry.begin('cached');
        await child.run(() async {
          report(child.request(), 1, 0, 10, 10);
          if (partial) child.markIncomplete();
        });
        final parent = ScanOperation();
        await parent.run(() async {
          registry.attachCurrent('cached');
          expect(parent.snapshot.displayStage, isNull);
          expect(parent.snapshot.stageFraction, isNull);
          expect(parent.snapshot.successful, isFalse);
        });
        expect(parent.snapshot.successful, !partial);
        registry.dispose();
      }
    },
  );

  testWidgets('stage identity resets arc; full stage is not a checkmark', (
    tester,
  ) async {
    Widget host(String id, double fraction, {bool completed = false}) =>
        MaterialApp(
          home: CircularFileScanner(
            scanId: 'scan',
            stageId: id,
            progress: fraction,
            completed: completed,
          ),
        );
    String? semantics() => tester
        .widget<Semantics>(find.byKey(const Key('scan_progress_semantics')))
        .properties
        .value;
    await tester.pumpWidget(host('a', 1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(semantics(), '100 percent');
    expect(find.byKey(const Key('scan_radar_center')), findsOneWidget);
    await tester.pumpWidget(host('b', 0));
    expect(semantics(), '0 percent');
    await tester.pumpWidget(host('b', .5));
    await tester.pumpWidget(host('b', .1));
    expect(semantics(), '50 percent');
    await tester.pumpWidget(host('b', 1, completed: true));
    expect(find.byKey(const Key('scan_complete_icon')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fast transitions coalesce label, counts and ring atomically', (
    tester,
  ) async {
    Widget host(ScanSnapshot snapshot) => MaterialApp(
      home: ScanStagePresentation(
        snapshot: snapshot,
        builder: (context, shown) =>
            Text('${shown!.displayStage!.id}: ${shown.stageDescription}'),
      ),
    );
    await tester.pumpWidget(host(view('A', 4, 4)));
    await tester.pumpWidget(host(view('B', 0, 10)));
    expect(find.textContaining('A: Stage: A · 4 / 4'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(host(view('C', 2, 8)));
    expect(find.textContaining('B:'), findsNothing);
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.textContaining('C: Stage: C · 2 / 8'), findsOneWidget);
    await tester.pumpWidget(host(view('D', 0, 9)));
    await tester.pumpWidget(host(view('E', 0, 6, scan: 'new')));
    expect(find.textContaining('E: Stage: E · 0 / 6'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading view labels zero, unknown and stage-complete honestly', (
    tester,
  ) async {
    Widget host(ScanSnapshot snapshot) => MaterialApp(
      home: PhotoToolLoadingState(
        icon: Icons.folder,
        title: 'Scanning',
        description: 'Fallback',
        scanProgress: snapshot,
      ),
    );
    await tester.pumpWidget(host(view('Hashing', 0, 10)));
    expect(find.text('Stage: Hashing'), findsOneWidget);
    expect(find.text('0 / 10 files checked'), findsOneWidget);
    await tester.pumpWidget(host(view('Hashing', 10, 10)));
    expect(find.text('10 / 10 files checked'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('100%'), findsOneWidget);
    expect(find.byKey(const Key('scan_complete_icon')), findsNothing);
    await tester.pumpWidget(host(view('Discovery', 230, null)));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('230 files checked'), findsOneWidget);
    expect(
      tester
          .widget<CircularFileScanner>(find.byType(CircularFileScanner))
          .progress,
      isNull,
    );
    await tester.pumpWidget(
      host(view('Cached stage', 10, 10, outcome: ScanOutcome.succeeded)),
    );
    expect(
      tester
          .widget<CircularFileScanner>(find.byType(CircularFileScanner))
          .progress,
      isNull,
    );
    expect(find.byKey(const Key('scan_complete_icon')), findsNothing);
    expect(find.textContaining('Cached stage'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
