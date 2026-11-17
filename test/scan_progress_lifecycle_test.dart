import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_storage_cleaner/app/router/app_router.dart';
import 'package:phone_storage_cleaner/core/ui/circular_file_scanner.dart';
import 'package:phone_storage_cleaner/features/cleaner/domain/scan_launch_target.dart';
import 'package:phone_storage_cleaner/features/cleaner/presentation/screens/scan_progress_screen.dart';
import 'package:phone_storage_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_scan_result.dart';

class _ControlledScanner implements FileScannerRepository {
  Completer<FileScanResult> pending = Completer<FileScanResult>();
  int calls = 0;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) {
    calls++;
    return pending.future;
  }
}

Future<GoRouter> _mount(WidgetTester tester, _ControlledScanner scanner) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final GoRouter router = GoRouter(
    initialLocation: '/scan',
    routes: <RouteBase>[
      GoRoute(
        path: '/scan',
        builder: (_, _) =>
            const ScanProgressScreen(target: ScanLaunchTarget.screenshots),
      ),
      GoRoute(
        path: AppRoutes.screenshotCleaner,
        builder: (_, _) => const Scaffold(body: Text('Results')),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('Home')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [fileScannerRepositoryProvider.overrideWithValue(scanner)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  testWidgets('fast scan retains the original 2800/650/420 ms timing gates', (
    WidgetTester tester,
  ) async {
    final _ControlledScanner scanner = _ControlledScanner();
    final GoRouter router = await _mount(tester, scanner);
    expect(scanner.calls, 1);
    scanner.pending.complete(FileScanResult.empty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2799));
    expect(find.text('Results'), findsNothing);
    expect(find.byKey(const Key('scan_complete_icon')), findsNothing);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 649));
    expect(find.byKey(const Key('scan_complete_icon')), findsNothing);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(find.byKey(const Key('scan_complete_icon')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 419));
    expect(find.text('Results'), findsNothing);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Results'), findsOneWidget);
    expect(scanner.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  testWidgets('scan error freezes animation and retry starts the same scan', (
    WidgetTester tester,
  ) async {
    final _ControlledScanner scanner = _ControlledScanner();
    final GoRouter router = await _mount(tester, scanner);
    scanner.pending.completeError(StateError('Scan unavailable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2801));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('scan_progress_error')), findsOneWidget);
    expect(
      tester
          .widget<CircularFileScanner>(find.byType(CircularFileScanner))
          .active,
      isFalse,
    );
    expect(find.text('Results'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    scanner.pending = Completer<FileScanResult>();
    await tester.tap(find.byKey(const Key('scan_progress_retry')));
    await tester.pump();
    expect(scanner.calls, 2);
    expect(
      tester
          .widget<CircularFileScanner>(find.byType(CircularFileScanner))
          .active,
      isTrue,
    );
    scanner.pending.complete(FileScanResult.empty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2801));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 651));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 421));
    await tester.pumpAndSettle();
    expect(find.text('Results'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  testWidgets(
    'leaving a pending scan disposes its animation and never redirects',
    (WidgetTester tester) async {
      final _ControlledScanner scanner = _ControlledScanner();
      final GoRouter router = await _mount(tester, scanner);
      await tester.tap(find.byKey(const Key('scan_progress_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(CircularFileScanner), findsNothing);
      scanner.pending.complete(FileScanResult.empty);
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Results'), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    },
  );
}
