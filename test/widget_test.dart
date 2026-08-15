import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/app/app.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:mobile_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('onboarding is first-launch only and can be replayed', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    appRouter.go(AppRoutes.splash);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionGatewayProvider.overrideWithValue(
            _FakePermissionGateway(AppPermissionStatus.denied),
          ),
        ],
        child: const MobileCleanerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text('Understand Your Storage'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('Clean Smarter'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('Private by Design'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('permission_education')), findsOneWidget);

    await tester.tap(find.byKey(const Key('permission_secondary_action')));
    await tester.pumpAndSettle();
    expect(find.text('Start safe scan'), findsOneWidget);

    appRouter.go(AppRoutes.splash);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text('Start safe scan'), findsOneWidget);
    expect(find.text('Understand Your Storage'), findsNothing);

    await tester.tap(find.byKey(const Key('nav_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replay_onboarding')));
    await tester.pumpAndSettle();
    expect(find.text('Understand Your Storage'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_skip')));
    await tester.pumpAndSettle();
    expect(find.text('Start safe scan'), findsOneWidget);
  });

  testWidgets('denied permission is handled without a crash', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_completed': true,
      'permission_education_seen': false,
    });
    appRouter.go(AppRoutes.splash);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionGatewayProvider.overrideWithValue(
            _FakePermissionGateway(AppPermissionStatus.denied),
          ),
        ],
        child: const MobileCleanerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('permission_education')), findsOneWidget);
    await tester.tap(find.byKey(const Key('permission_primary_action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('permission_denied')), findsOneWidget);
    expect(find.text('Permission denied'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('permission_secondary_action')));
    await tester.pumpAndSettle();
    expect(find.text('Start safe scan'), findsOneWidget);
  });

  testWidgets('every bottom tab opens without errors', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_completed': true,
      'permission_education_seen': true,
    });
    appRouter.go(AppRoutes.splash);

    await tester.pumpWidget(const ProviderScope(child: MobileCleanerApp()));
    await tester.pump(const Duration(milliseconds: 1000));
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

class _FakePermissionGateway implements AppPermissionGateway {
  _FakePermissionGateway(this.status);

  final AppPermissionStatus status;

  @override
  Future<AppPermissionStatus> checkMediaAndStorage() async => status;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<AppPermissionStatus> requestMediaAndStorage() async => status;
}
