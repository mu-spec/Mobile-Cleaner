import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/app/theme/app_theme.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/core/ui/circular_file_scanner.dart';
import 'package:phone_storage_cleaner/core/ui/reference_progress_art.dart';
import 'package:phone_storage_cleaner/core/ui/smart_scan_progress.dart';
import 'package:phone_storage_cleaner/features/cleaner/domain/scan_launch_target.dart';
import 'package:phone_storage_cleaner/features/cleaner/presentation/screens/scan_progress_screen.dart';
import 'package:phone_storage_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_scan_result.dart';
import 'package:phone_storage_cleaner/features/files/presentation/widgets/photo_tool_ui.dart';

ScanSnapshot sample(
  int done,
  int? total, {
  String stage = 'Scanning files',
  String scan = 'scan',
}) => ScanSnapshot(
  id: scan,
  fraction: total != null && total > 0
      ? (done / total >= 1.0 ? 0.99 : done / total)
      : null,
  displayStage: ScanStage(
    id: stage,
    name: stage,
    processed: done,
    total: total,
    unit: 'files checked',
  ),
);

Widget host(
  ScanSnapshot snapshot, {
  bool reduced = false,
  bool completed = false,
  bool succeeded = false,
  bool active = true,
  String? path,
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: reduced,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: SmartScanProgress(
        snapshot: snapshot,
        activity: 'Scanning your device...',
        description: 'Checking file information',
        currentPath: path,
        completed: completed,
        succeeded: succeeded,
        active: active,
      ),
    ),
  ),
);

ReferenceProgressPainter art(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(const Key('circular_file_scanner_paint')),
            )
            .painter!
        as ReferenceProgressPainter;

void consistent(WidgetTester tester, double target) {
  final fill = art(tester).fill.value;
  expect(fill, lessThanOrEqualTo(target));
  expect(find.text('${(fill * 100).floor()}%'), findsOneWidget);
  final track = tester
      .getSize(find.byKey(const Key('scan_measured_bar')))
      .width;
  final bar = tester
      .getSize(find.byKey(const Key('scan_measured_bar_fill')))
      .width;
  expect(bar / track, closeTo(fill, .00001));
}

class MeasuredRepository implements FileScannerRepository {
  final gate = Completer<FileScanResult>();
  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) {
    final operation = ScanOperation.current!;
    final native = operation.request();
    operation.acceptNative({
      'requestId': native.id,
      'sequence': 1,
      'stageIndex': 0,
      'stage': 'Scanning files',
      'processed': 110,
      'total': 500,
      'unit': 'files checked',
      'outcome': 'running',
    }, native.id);
    return gate.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'percentage is strictly below, never inside radar; counts occur once',
    (tester) async {
      await tester.pumpWidget(host(sample(110, 500), reduced: true));
      final radar = find.byKey(const Key('circular_file_scanner_artwork'));
      final number = find.byKey(const Key('scan_percentage_below'));
      expect(
        tester.getTopLeft(number).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(radar).dy),
      );
      expect(
        find.descendant(of: radar, matching: find.textContaining('%')),
        findsNothing,
      );
      expect(find.text('110 / 500 files checked'), findsOneWidget);
      expect(find.text('Stage: Scanning files'), findsOneWidget);
      expect(find.text('Private, on-device scan'), findsNothing);
      expect(
        find.text('Nothing is removed without your approval'),
        findsNothing,
      );
      consistent(tester, .22);
      expect(art(tester).fill.value, .22);
    },
  );

  testWidgets(
    'selected stage, not parent fraction, supplies all counts and fills',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ScanSnapshot(
            id: 'parent',
            processed: 999,
            total: 1000,
            fraction: .999,
            displayStage: ScanStage(
              id: 'selected',
              name: 'Hashing files',
              processed: 110,
              total: 500,
              unit: 'files fingerprinted',
            ),
          ),
          reduced: true,
        ),
      );
      expect(find.text('110 / 500 files fingerprinted'), findsOneWidget);
      expect(find.textContaining('999'), findsNothing);
      consistent(tester, .999);
      expect(find.text('99%'), findsOneWidget);
    },
  );

  testWidgets(
    'zero denominator remains unknown until an actual empty-stage completion',
    (tester) async {
      await tester.pumpWidget(host(sample(0, 0), reduced: true));
      expect(find.byKey(const Key('scan_percentage_below')), findsNothing);
      expect(find.byKey(const Key('scan_measured_bar_fill')), findsNothing);
      expect(find.text('0 / 0 files checked'), findsOneWidget);
      expect(find.byKey(const Key('scan_complete_icon')), findsNothing);
    },
  );

  testWidgets('separately approved broom capture remains byte-identical', (
    tester,
  ) async {
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
                  progress: .3,
                  cleaning: true,
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
      expect(
        bytes!.buffer.asUint8List(),
        orderedEquals(
          File('docs/reference-animation-evidence/cleaning.png')
              .readAsBytesSync(),
        ),
      );
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'count-up is bounded by confirmed work and all three fills are identical each frame',
    (tester) async {
      await tester.pumpWidget(host(sample(100, 500), reduced: true));
      await tester.pumpWidget(host(sample(110, 500)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        consistent(tester, .22);
        expect(art(tester).fill.value, greaterThanOrEqualTo(.20));
      }
      await tester.pump(const Duration(seconds: 1));
      consistent(tester, .22);
      expect(find.text('22%'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      consistent(tester, .22);
      expect(find.text('22%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unknown totals hide number and measured fill but keep actual counter',
    (tester) async {
      await tester.pumpWidget(host(sample(110, null)));
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const Key('scan_percentage_below')), findsNothing);
      expect(find.byKey(const Key('scan_measured_bar_fill')), findsNothing);
      expect(art(tester).fill.value, 0);
      expect(find.text('110 files checked'), findsOneWidget);
      expect(find.byKey(const Key('scan_stage_spinner')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'stage 100% is not parent completion and next identity resets every fill',
    (tester) async {
      await tester.pumpWidget(host(sample(500, 500), reduced: true));
      consistent(tester, 1);
      expect(find.byKey(const Key('scan_complete_icon')), findsNothing);
      await tester.pumpWidget(
        host(sample(0, 200, stage: 'Fingerprinting photos'), reduced: true),
      );
      consistent(tester, .99);
      expect(find.text('99%'), findsOneWidget);
      expect(find.text('0 / 200 files checked'), findsOneWidget);
      await tester.pumpWidget(
        host(sample(500, 500), completed: true, succeeded: true),
      );
      expect(find.byKey(const Key('scan_complete_icon')), findsOneWidget);
      expect(find.byKey(const Key('scan_stage_spinner')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('new scan resets, unknown stage hides previous measured result', (
    tester,
  ) async {
    await tester.pumpWidget(host(sample(500, 500), reduced: true));
    await tester.pumpWidget(
      host(sample(3, null, stage: 'Discovering'), reduced: true),
    );
    expect(find.byKey(const Key('scan_percentage_below')), findsNothing);
    await tester.pumpWidget(host(sample(0, 500, scan: 'new'), reduced: true));
    consistent(tester, 0);
  });

  testWidgets('actual path is optional, never a hard-coded example', (
    tester,
  ) async {
    await tester.pumpWidget(host(sample(110, 500), reduced: true));
    expect(find.byKey(const Key('scan_current_path')), findsNothing);
    await tester.pumpWidget(
      host(sample(110, 500), reduced: true, path: '/actual/test/folder/'),
    );
    expect(find.text('/actual/test/folder/'), findsOneWidget);
    await tester.pumpWidget(host(sample(110, 500), reduced: true, path: '  '));
    expect(find.byKey(const Key('scan_current_path')), findsNothing);
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(512, 768),
    const Size(800, 1280),
    const Size(640, 360),
  ]) {
    testWidgets(
      'responsive radar fits ${size.width} x ${size.height} without horizontal overflow',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(host(sample(110, 500), reduced: true));
        final rect = tester.getRect(
          find.byKey(const Key('circular_file_scanner_artwork')),
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.width, lessThanOrEqualTo(size.width * .74 + .1));
        expect(rect.width, greaterThanOrEqualTo(120));
        if (size.height > 600) expect(rect.width, greaterThan(size.width * .6));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('scan_status_card')));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'enlarged text uses vertical scroll, not a clipped radar or horizontal overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(sample(110, 500), reduced: true, textScale: 2),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('scan_status_card')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background, reduced motion, cancellation and disposal stop all decorative tickers',
    (tester) async {
      await tester.pumpWidget(host(sample(110, 500)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(host(sample(110, 500), reduced: true));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(host(sample(110, 500), active: false));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byKey(const Key('scan_complete_icon')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'photo loading integration preserves its module labels with larger radar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(512, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoToolLoadingState(
              icon: Icons.photo,
              title: 'Comparing similar photos',
              description: 'Comparing photo fingerprints',
              scanProgress: sample(110, 500, stage: 'Fingerprinting photos'),
            ),
          ),
        ),
      );
      expect(find.text('Comparing similar photos'), findsOneWidget);
      expect(find.text('Stage: Fingerprinting photos'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const Key('circular_file_scanner_artwork')))
            .width,
        greaterThan(228),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('all nine approved radar color constants remain exact', () {
    expect(
      [
        ReferenceProgressColors.royal,
        ReferenceProgressColors.blue,
        ReferenceProgressColors.deep,
        ReferenceProgressColors.cyan,
        ReferenceProgressColors.ice,
        ReferenceProgressColors.ring,
        ReferenceProgressColors.halo,
        ReferenceProgressColors.orange,
        ReferenceProgressColors.white,
      ],
      const [
        Color(0xFF3367ED),
        Color(0xFF164AD3),
        Color(0xFF032C99),
        Color(0xFF49C4F3),
        Color(0xFFB4DFFE),
        Color(0xFFCEDAF5),
        Color(0xFFEFF2FB),
        Color(0xFFF79516),
        Color(0xFFF4FBFC),
      ],
    );
  });

  for (final viewport in [const Size(320, 568), const Size(800, 1280)]) {
    testWidgets(
      'actual Smart Scan route fits $viewport including app bar and stage card',
      (tester) async {
        await tester.binding.setSurfaceSize(viewport);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = MeasuredRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              fileScannerRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const ScanProgressScreen(target: ScanLaunchTarget.files),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        final rect = tester.getRect(
          find.byKey(const Key('circular_file_scanner_artwork')),
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(viewport.width));
        expect(find.text('22%'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('scan_status_card')));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        repository.gate.complete(FileScanResult.fromFiles([]));
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'capture actual Smart Scan screen at reference viewport from measured repository progress',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(512, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final loader = FontLoader('Inter');
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
      ]) {
        final asset = 'assets/fonts/Inter-$weight.ttf';
        if (File(asset).existsSync()) loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final repository = MeasuredRepository();
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileScannerRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24),
                viewPadding: const EdgeInsets.only(top: 24),
              ),
              child: child!,
            ),
            home: RepaintBoundary(
              key: key,
              child: const ScanProgressScreen(target: ScanLaunchTarget.files),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('22%'), findsNothing);
      expect(find.text('110 / 500 files checked'), findsOneWidget);
      expect(find.text('Private, on-device scan'), findsNothing);
      expect(find.byKey(const Key('scan_current_path')), findsNothing);
      await tester.pump(const Duration(milliseconds: 5200));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('docs/approved-smart-scan-evidence')
          ..createSync(recursive: true);
        File('${dir.path}/smart-scan-1024x1536.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      repository.gate.complete(FileScanResult.fromFiles([]));
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}
