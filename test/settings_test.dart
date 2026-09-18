import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_storage_cleaner/core/constants/app_constants.dart';
import 'package:phone_storage_cleaner/features/files/domain/download_age_filter.dart';
import 'package:phone_storage_cleaner/features/files/domain/large_file_filter.dart';
import 'package:phone_storage_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:phone_storage_cleaner/features/settings/data/settings_repository.dart';
import 'package:phone_storage_cleaner/features/settings/domain/app_settings.dart';
import 'package:phone_storage_cleaner/features/settings/presentation/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubSettings implements SettingsRepository {
  _StubSettings([AppSettings? initial])
    : settings = initial ?? AppSettings.defaults;

  AppSettings settings;
  int saves = 0;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings next) async {
    settings = next;
    saves++;
  }
}

Future<_StubSettings> _pumpSettings(
  WidgetTester tester, {
  _StubSettings? repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubSettings repo = repository ?? _StubSettings();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('settings_list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AppSettings encoding', () {
    test('theme mode round-trips by name, not index', () {
      for (final ThemeMode mode in ThemeMode.values) {
        final String encoded = AppSettings.encodeThemeMode(mode);
        // A name, so reordering the enum cannot change a stored choice.
        expect(int.tryParse(encoded), isNull);
        expect(AppSettings.decodeThemeMode(encoded), mode);
      }
    });

    test('an unknown theme falls back to following the device', () {
      expect(AppSettings.decodeThemeMode(null), ThemeMode.system);
      expect(AppSettings.decodeThemeMode(''), ThemeMode.system);
      expect(AppSettings.decodeThemeMode('sepia'), ThemeMode.system);
    });

    test('enum settings decode by name and fall back safely', () {
      expect(
        AppSettings.decodeByName(
          'over1gb',
          LargeFileFilter.values,
          LargeFileFilter.defaultFilter,
        ),
        LargeFileFilter.over1gb,
      );
      // Removed or renamed values fall back rather than crashing.
      expect(
        AppSettings.decodeByName(
          'over42tb',
          LargeFileFilter.values,
          LargeFileFilter.defaultFilter,
        ),
        LargeFileFilter.defaultFilter,
      );
      expect(
        AppSettings.decodeByName(
          null,
          DownloadAgeFilter.values,
          DownloadAgeFilter.defaultFilter,
        ),
        DownloadAgeFilter.defaultFilter,
      );
    });

    test('copyWith changes one field and leaves the rest', () {
      const AppSettings base = AppSettings.defaults;
      final AppSettings next = base.copyWith(themeMode: ThemeMode.dark);

      expect(next.themeMode, ThemeMode.dark);
      expect(next.largeFileFilter, base.largeFileFilter);
      expect(next.screenshotGroup, base.screenshotGroup);
      expect(next.downloadAgeFilter, base.downloadAgeFilter);
      expect(next, isNot(base));
    });

    test('theme labels read as the UI shows them', () {
      expect(AppSettings.defaults.themeLabel, 'System');
      expect(
        AppSettings.defaults.copyWith(themeMode: ThemeMode.dark).themeLabel,
        'Dark',
      );
    });
  });

  group('Persistence', () {
    test('settings survive a real save and reload', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const PreferencesSettingsRepository repository =
          PreferencesSettingsRepository();

      await repository.save(
        const AppSettings(
          themeMode: ThemeMode.dark,
          largeFileFilter: LargeFileFilter.over1gb,
          screenshotGroup: ScreenshotGroup.days90,
          downloadAgeFilter: DownloadAgeFilter.year1,
        ),
      );

      final AppSettings loaded = await repository.load();
      expect(loaded.themeMode, ThemeMode.dark);
      expect(loaded.largeFileFilter, LargeFileFilter.over1gb);
      expect(loaded.screenshotGroup, ScreenshotGroup.days90);
      expect(loaded.downloadAgeFilter, DownloadAgeFilter.year1);
    });

    test('a fresh install gets the defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppSettings loaded = await const PreferencesSettingsRepository()
          .load();
      expect(loaded, AppSettings.defaults);
    });

    test('one corrupt value does not reset the others', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PreferencesSettingsRepository.themeKey: 'nonsense',
        PreferencesSettingsRepository.largeFileKey: 'over1gb',
      });

      final AppSettings loaded = await const PreferencesSettingsRepository()
          .load();
      expect(loaded.themeMode, ThemeMode.system);
      // Still honoured despite the bad neighbour.
      expect(loaded.largeFileFilter, LargeFileFilter.over1gb);
    });

    test('names are persisted, never enum indexes', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const PreferencesSettingsRepository repository =
          PreferencesSettingsRepository();
      await repository.save(
        const AppSettings(largeFileFilter: LargeFileFilter.over500mb),
      );

      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      expect(
        preferences.getString(PreferencesSettingsRepository.largeFileKey),
        'over500mb',
      );
    });
  });

  group('Settings screen', () {
    testWidgets('shows every required item', (WidgetTester tester) async {
      await _pumpSettings(tester);

      for (final Key key in <Key>[
        const Key('setting_theme_mode'),
        const Key('setting_large_file_threshold'),
        const Key('setting_screenshot_age'),
        const Key('setting_download_age'),
      ]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key missing');
      }

      for (final Key key in <Key>[
        const Key('manage_permissions'),
        const Key('open_privacy_policy'),
        const Key('replay_onboarding'),
        const Key('open_about'),
        const Key('setting_app_version'),
      ]) {
        await _scrollTo(tester, find.byKey(key));
        expect(find.byKey(key), findsOneWidget, reason: '$key missing');
      }
    });

    testWidgets('theme choice is saved', (WidgetTester tester) async {
      final _StubSettings repo = await _pumpSettings(tester);

      await tester.tap(find.byKey(const Key('setting_theme_mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(repo.settings.themeMode, ThemeMode.dark);
      expect(repo.saves, 1);
    });

    testWidgets('the large-file threshold can be changed', (
      WidgetTester tester,
    ) async {
      final _StubSettings repo = await _pumpSettings(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('setting_large_file_threshold_value')),
            )
            .data,
        '100 MB+',
      );

      await tester.tap(find.byKey(const Key('setting_large_file_threshold')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option_over1gb')));
      await tester.pumpAndSettle();

      expect(repo.settings.largeFileFilter, LargeFileFilter.over1gb);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('setting_large_file_threshold_value')),
            )
            .data,
        '1 GB+',
      );
    });

    testWidgets('screenshot age and download age can be changed', (
      WidgetTester tester,
    ) async {
      final _StubSettings repo = await _pumpSettings(tester);

      await tester.tap(find.byKey(const Key('setting_screenshot_age')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option_days90')));
      await tester.pumpAndSettle();
      expect(repo.settings.screenshotGroup, ScreenshotGroup.days90);

      await tester.tap(find.byKey(const Key('setting_download_age')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option_year1')));
      await tester.pumpAndSettle();
      expect(repo.settings.downloadAgeFilter, DownloadAgeFilter.year1);
    });

    testWidgets('choosing the value already set writes nothing', (
      WidgetTester tester,
    ) async {
      final _StubSettings repo = await _pumpSettings(tester);

      await tester.tap(find.byKey(const Key('setting_large_file_threshold')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('option_over100mb')));
      await tester.pumpAndSettle();

      expect(repo.saves, 0);
    });

    testWidgets('stored settings are reflected on open', (
      WidgetTester tester,
    ) async {
      await _pumpSettings(
        tester,
        repository: _StubSettings(
          const AppSettings(
            themeMode: ThemeMode.light,
            largeFileFilter: LargeFileFilter.over500mb,
            downloadAgeFilter: DownloadAgeFilter.months6,
          ),
        ),
      );

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('setting_large_file_threshold_value')),
            )
            .data,
        '500 MB+',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('setting_download_age_value')))
            .data,
        '6+ months',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('setting_theme_mode_value')))
            .data,
        'Light',
      );

      await tester.tap(find.byKey(const Key('setting_theme_mode')));
      await tester.pumpAndSettle();
      final SegmentedButton<ThemeMode> control = tester
          .widget<SegmentedButton<ThemeMode>>(
            find.byKey(const Key('setting_theme_mode_control')),
          );
      expect(control.selected, <ThemeMode>{ThemeMode.light});
    });

    testWidgets('the defaults note explains tools can still override', (
      WidgetTester tester,
    ) async {
      await _pumpSettings(tester);
      expect(find.byKey(const Key('settings_defaults_note')), findsOneWidget);
    });

    testWidgets('privacy policy row launches the published URL externally', (
      WidgetTester tester,
    ) async {
      final List<Uri> launched = <Uri>[];
      debugLaunchExternalUri = (Uri uri) async {
        launched.add(uri);
        return true;
      };
      addTearDown(() => debugLaunchExternalUri = null);

      await _pumpSettings(tester);

      await _scrollTo(tester, find.byKey(const Key('open_privacy_policy')));
      await tester.tap(find.byKey(const Key('open_privacy_policy')));

      // Controlled pumps, never pumpAndSettle: settle keeps advancing the
      // clock while frames are scheduled, which can run the SnackBar's four
      // second display and its dismissal before an assertion sees it. 300ms
      // clears the 250ms entrance and stops well short of the display time.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(launched.single, Uri.parse(AppConstants.privacyPolicyUrl));
      expect(find.byKey(const Key('privacy_policy_error')), findsNothing);
      expect(tester.takeException(), isNull);

      // The policy is no longer rendered in-app; it lives behind the link.
      expect(find.byKey(const Key('privacy_policy_sheet')), findsNothing);
    });

    testWidgets('a failed launch shows the message and does not throw', (
      WidgetTester tester,
    ) async {
      debugLaunchExternalUri = (Uri uri) async => false;
      addTearDown(() => debugLaunchExternalUri = null);

      await _pumpSettings(tester);

      await _scrollTo(tester, find.byKey(const Key('open_privacy_policy')));
      await tester.tap(find.byKey(const Key('open_privacy_policy')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('privacy_policy_error')), findsOneWidget);
      expect(find.text('Unable to open Privacy Policy.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a throwing launch is caught, not rethrown', (
      WidgetTester tester,
    ) async {
      debugLaunchExternalUri = (Uri uri) async {
        // What a device with no browser-capable handler surfaces.
        throw MissingPluginException('no browser registered');
      };
      addTearDown(() => debugLaunchExternalUri = null);

      await _pumpSettings(tester);

      await _scrollTo(tester, find.byKey(const Key('open_privacy_policy')));
      await tester.tap(find.byKey(const Key('open_privacy_policy')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('privacy_policy_error')), findsOneWidget);
      expect(find.text('Unable to open Privacy Policy.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('there is exactly one privacy policy row', (
      WidgetTester tester,
    ) async {
      await _pumpSettings(tester);

      await _scrollTo(tester, find.byKey(const Key('open_privacy_policy')));
      expect(find.byKey(const Key('open_privacy_policy')), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
    });

    testWidgets('about opens and is honest about limits', (
      WidgetTester tester,
    ) async {
      await _pumpSettings(tester);

      await _scrollTo(tester, find.byKey(const Key('open_about')));
      await tester.tap(find.byKey(const Key('open_about')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('about_sheet')), findsOneWidget);
      expect(find.text('What it will not do'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the app version is shown', (WidgetTester tester) async {
      await _pumpSettings(tester);

      await _scrollTo(tester, find.byKey(const Key('setting_app_version')));
      expect(find.byKey(const Key('setting_app_version')), findsOneWidget);
      expect(find.text('About Phone Storage Cleaner'), findsOneWidget);
    });
  });
}
