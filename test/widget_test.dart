import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/app/app.dart';

void main() {
  testWidgets('launches the Phase 0 home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MobileCleanerApp()));
    await tester.pumpAndSettle();

    expect(find.text('Mobile Cleaner'), findsOneWidget);
    expect(find.text('Start safe scan'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
