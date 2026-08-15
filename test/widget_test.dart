import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/app/app.dart';

void main() {
  testWidgets('splash opens the app and every bottom tab works', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MobileCleanerApp()));

    expect(find.text('Clean safely. Stay in control.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(find.text('Start safe scan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_clean')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen_Clean')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_photos')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen_Photos')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_files')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen_Files')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_apps')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screen_Apps')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pumpAndSettle();
    expect(find.text('App version'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
