import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/core/ui/circular_file_scanner.dart';
import 'package:phone_storage_cleaner/core/ui/reference_progress_art.dart';
import 'package:phone_storage_cleaner/features/files/data/delete_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/delete_progress.dart';
import 'package:phone_storage_cleaner/features/files/domain/delete_result.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_category.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_selection.dart';
import 'package:phone_storage_cleaner/features/files/domain/scanned_file.dart';
import 'package:phone_storage_cleaner/features/files/presentation/widgets/delete_flow.dart';

ScannedFile item(String id, {int bytes = 100}) => ScannedFile(
  id: id,
  name: '$id.jpg',
  path: '/selected/$id.jpg',
  uri: 'content://media/images/$id',
  sizeBytes: bytes,
  category: FileCategory.images,
  dateModified: DateTime(2026),
);

void event(
  DeleteProgressOperation operation,
  int sequence,
  Map<String, String> outcomes, {
  Map<String, int> sizes = const {},
  String phase = 'deleting',
  String? current,
  bool terminal = false,
}) => operation.accept({
  'requestId': operation.id,
  'sequence': sequence,
  'outcomes': outcomes,
  'confirmedBytesByUri': sizes,
  'phase': phase,
  'currentUri': current,
  'terminal': terminal,
});

class DelayedDelete implements DeleteRepository {
  final gate = Completer<DeleteResult>();
  DeleteProgressOperation? operation;
  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) {
    operation = DeleteProgressOperation.current;
    return gate.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('progress is zero until settled evidence; waiting for consent is not cleaning', () async {
    final a = item('a'), b = item('b');
    final op = DeleteProgressOperation([a, b]);
    final gate = Completer<DeleteResult>();
    final future = op.run(() => gate.future);
    expect(op.snapshot.confirmedBytes, 0);
    event(op, 1, {}, phase: 'awaitingConfirmation');
    expect(op.snapshot.processed, 0);
    expect(op.snapshot.fraction, 0);
    event(op, 2, {a.uri: 'deleted'}, sizes: {a.uri: 83}, current: b.uri);
    expect(op.snapshot.processed, 1);
    expect(op.snapshot.fraction, .5);
    expect(op.snapshot.confirmedBytes, 83); // not a's stale scanned 100
    expect(op.snapshot.currentUri, b.uri);
    event(
      op,
      3,
      {a.uri: 'deleted', b.uri: 'deleted'},
      sizes: {a.uri: 83, b.uri: 52},
      terminal: true,
    );
    expect(op.snapshot.successful, isFalse);
    expect(op.snapshot.terminal, isFalse); // wait for actual method result
    gate.complete(
      DeleteResult(
        deletedFiles: [a, b],
        failures: [],
        confirmedBytesByUri: {a.uri: 83, b.uri: 52},
      ),
    );
    await future;
    expect(op.snapshot.successful, isTrue);
    expect(op.snapshot.confirmedBytes, 135);
    op.dispose();
  });

  test(
    'failed, skipped, cancelled and unknown-size removals never inflate bytes',
    () async {
      final a = item('a'), b = item('b'), c = item('c'), d = item('d');
      final op = DeleteProgressOperation([a, b, c, d]);
      final gate = Completer<DeleteResult>();
      final future = op.run(() => gate.future);
      event(op, 1, {a.uri: 'deleted', b.uri: 'failed', c.uri: 'skipped'});
      expect(op.snapshot.confirmedBytes, 0);
      expect(op.snapshot.processed, 3);
      gate.complete(
        DeleteResult(
          deletedFiles: [a],
          failures: [DeleteFailure(uri: b.uri, reason: 'Denied')],
          skippedUris: [c.uri],
          confirmedBytesByUri: {},
          userCancelled: true,
        ),
      );
      final result = await future;
      expect(result.unmeasuredDeletedCount, 1);
      expect(
        op.snapshot.processed,
        3,
      ); // untouched cancelled d is not processed
      expect(op.snapshot.phase, 'cancelled');
      expect(op.snapshot.successful, isFalse);
      expect(result.isPartialSuccess, isTrue);
      op.dispose();
    },
  );

  test('stale, foreign, decreasing and contradictory progress is ignored', () {
    final a = item('a'), b = item('b');
    final op = DeleteProgressOperation([a, b]);
    event(op, 2, {a.uri: 'deleted'}, sizes: {a.uri: 50});
    final before = op.snapshot;
    event(
      op,
      1,
      {a.uri: 'deleted', b.uri: 'deleted'},
      sizes: {a.uri: 50, b.uri: 100},
    );
    event(op, 3, {a.uri: 'failed'});
    event(op, 4, {a.uri: 'deleted'}, sizes: {a.uri: 10});
    event(op, 5, {'foreign': 'deleted'}, sizes: {'foreign': 1000});
    op.accept({
      'requestId': 'foreign',
      'sequence': 6,
      'outcomes': {},
      'confirmedBytesByUri': {},
    });
    expect(identical(op.snapshot, before), isTrue);
    op.dispose();
    event(
      op,
      7,
      {a.uri: 'deleted', b.uri: 'deleted'},
      sizes: {a.uri: 50, b.uri: 100},
    );
    expect(identical(op.snapshot, before), isTrue);
  });

  test('partial evidence survives a repository exception without retrying deletion', () async {
    final a = item('a'), b = item('b');
    final op = DeleteProgressOperation([a, b]);
    final result = await op.run(() async {
      event(op, 1, {a.uri: 'deleted'}, sizes: {a.uri: 42});
      throw PlatformException(code: 'CONNECTION_LOST');
    });
    expect(result.deletedFiles, [a]);
    expect(result.freedBytes, 42);
    expect(result.failures.single.uri, b.uri);
    expect(op.snapshot.successful, isFalse);
    op.dispose();
  });

  test('parser deduplicates successes and excludes skipped, failed, foreign and unknown outcomes', () {
    final a = item('a'), b = item('b'), c = item('c'), d = item('d');
    final result = PlatformDeleteRepository.parseResult(
      {
        'accountingVersion': 1,
        'deletedUris': [a.uri, a.uri, b.uri, c.uri, 'foreign'],
        'skippedUris': [b.uri],
        'failed': [
          {'uri': c.uri, 'reason': 'Denied'},
        ],
        'confirmedBytesByUri': {
          a.uri: 45,
          b.uri: 500,
          c.uri: 500,
          'foreign': 10000,
        },
      },
      [a, b, c, d],
    );
    expect(result.deletedFiles, [a]);
    expect(result.freedBytes, 45);
    expect(result.skippedUris, [b.uri]);
    expect(result.failureCount, 2);
    expect(result.isCompleteSuccess, isFalse);
  });

  test(
    'contradictory final outcomes count a URI once and never exceed total',
    () async {
      final a = item('a');
      final op = DeleteProgressOperation([a]);
      final result = await op.run(
        () async => DeleteResult(
          deletedFiles: [a, a],
          failures: [
            DeleteFailure(uri: a.uri, reason: 'Denied'),
            DeleteFailure(uri: a.uri, reason: 'Duplicate'),
          ],
          skippedUris: [a.uri],
          confirmedBytesByUri: {a.uri: 999},
        ),
      );
      expect(result.deletedCount, 0);
      expect(result.failureCount, 1);
      expect(result.skippedUris, isEmpty);
      expect(op.snapshot.processed, 1);
      expect(op.snapshot.fraction, 1);
      expect(op.snapshot.confirmedBytes, 0);
      expect(op.snapshot.successful, isFalse);
      op.dispose();
    },
  );

  test('new deletion scopes restart at zero and late old messages cannot affect them', () async {
    final a = item('a');
    final old = DeleteProgressOperation([a]);
    await old.run(() async => DeleteResult(deletedFiles: [a], failures: []));
    final fresh = DeleteProgressOperation([a]);
    event(old, 99, {a.uri: 'deleted'}, sizes: {a.uri: 900});
    expect(fresh.snapshot.processed, 0);
    expect(fresh.snapshot.confirmedBytes, 0);
    old.dispose();
    fresh.dispose();
  });

  test('modern missing/negative sizes remain unknown, never use stale planned bytes', () {
    final a = item('a', bytes: 999), b = item('b', bytes: 999);
    final result = PlatformDeleteRepository.parseResult(
      {
        'accountingVersion': 1,
        'deletedUris': [a.uri, b.uri],
        'confirmedBytesByUri': {a.uri: -1},
      },
      [a, b],
    );
    expect(result.freedBytes, 0);
    expect(result.unmeasuredDeletedCount, 2);
  });

  for (final phase in [
    'awaitingPermission',
    'awaitingConfirmation',
    'verifying',
  ]) {
    test(
      '$phase channel updates never authorize success or new bytes',
      () async {
        const transport = MethodChannel('test/confirmed-delete');
        final a = item('a');
        final op = DeleteProgressOperation([a]);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(transport, (call) async {
          expect((call.arguments as Map)['progressId'], op.id);
          await messenger.handlePlatformMessage(
            DeleteProgressOperation.channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('progress', {
                'requestId': op.id,
                'sequence': 1,
                'outcomes': {},
                'confirmedBytesByUri': {},
                'phase': phase,
              }),
            ),
            (_) {},
          );
          expect(op.snapshot.confirmedBytes, 0);
          expect(op.snapshot.successful, isFalse);
          return {
            'accountingVersion': 1,
            'deletedUris': [],
            'userCancelled': true,
            'confirmedBytesByUri': {},
          };
        });
        addTearDown(() => messenger.setMockMethodCallHandler(transport, null));
        await op.run(
          () => PlatformDeleteRepository(channel: transport).deleteFiles([a]),
        );
        expect(op.snapshot.confirmedBytes, 0);
        expect(op.snapshot.phase, 'cancelled');
        op.dispose();
      },
    );
  }

  testWidgets(
    'cleaning displays only confirmed bytes and genuine current URI during a delayed batch',
    (tester) async {
      final repo = DelayedDelete();
      final a = item('a'), b = item('b');
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deleteRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => runDeleteFlow(
                    context: context,
                    ref: ref,
                    selection: const FileSelection.empty().selectAll([a, b]),
                  ),
                  child: const Text('Start'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_confirm')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cleanup_cleaning_bytes')))
            .data,
        '0 B',
      );
      expect(
        tester
            .widget<ReferenceProgressBar>(
              find.byKey(const Key('cleanup_progress_bar')),
            )
            .value,
        0,
      );
      event(
        repo.operation!,
        1,
        {a.uri: 'deleted'},
        sizes: {a.uri: 37},
        current: b.uri,
      );
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cleanup_cleaning_bytes')))
            .data,
        '37 B',
      );
      expect(find.text('/selected/b.jpg'), findsOneWidget);
      event(
        repo.operation!,
        2,
        {a.uri: 'deleted'},
        sizes: {a.uri: 37},
        phase: 'awaitingConfirmation',
      );
      await tester.pump();
      expect(find.text('Waiting for Android confirmation…'), findsOneWidget);
      expect(
        find.text('Done'),
        findsNothing,
      ); // category not prematurely complete
      await tester.pumpWidget(
        const SizedBox.shrink(),
      ); // detach, don't cancel actual delete
      repo.gate.complete(
        DeleteResult(
          deletedFiles: [a],
          failures: [],
          userCancelled: true,
          confirmedBytesByUri: {a.uri: 37},
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cleaning shine pauses for background, reduced motion and disposal',
    (tester) async {
      Widget host({bool reduce = false, bool active = true}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: CleaningProgressAnimation(progress: .4, active: active),
        ),
      );
      await tester.pumpWidget(host());
      ReferenceProgressPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('circular_file_scanner_paint')),
                  )
                  .painter!
              as ReferenceProgressPainter;
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const Key('cleaning_broom_art')), findsOneWidget);
      final first = painter().motion.value;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 2));
      expect(painter().motion.value, first);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(painter().motion.value, isNot(first));
      await tester.pumpWidget(host(reduce: true));
      final stopped = painter().motion.value;
      await tester.pump(const Duration(seconds: 2));
      expect(painter().motion.value, stopped);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('render actual reference component previews', (tester) async {
    for (final cleaning in [false, true]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: Colors.white,
                child: MediaQuery(
                  data: const MediaQueryData(disableAnimations: true),
                  child: CircularFileScanner(
                    size: 280,
                    progress: cleaning ? .3 : .12,
                    cleaning: cleaning,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('/home/user/reference-animation-previews')
          ..createSync(recursive: true);
        File('${directory.path}/${cleaning ? 'cleaning' : 'scanning'}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
