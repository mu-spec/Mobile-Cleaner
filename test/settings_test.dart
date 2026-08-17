import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/domain/download_age_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_file_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/settings/data/settings_repository.dart';
import 'package:mobile_cleaner/features/settings/domain/app_settings.dart';
import 'package:mobile_cleaner/features/settings/presentation/screens/settings_screen.dart';
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
      final AppSettings loaded =
          await const PreferencesSettingsRepository().load();
      expect(loaded, AppSettings.defaults);
    });

    test('one corrupt value does not reset the others', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PreferencesSettingsRepository.themeKey: 'nonsense',
        PreferencesSettingsRepository.largeFileKey: 'over1gb',
      });

      final AppSettings loaded =
          await const PreferencesSettingsRepository().load();
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
      final SegmentedButton<ThemeMode> control = tester
          .widget<SegmentedButton<ThemeMode>>(
            find.byKey(const Key('setting_theme_mode')),
          );
      expect(control.selected, <ThemeMode>{ThemeMode.light});
    });

    testWidgets('the defaults note explains tools can still override', (
      WidgetTester tester,
    ) async {
      await _pumpSettings(tester);
      expect(find.byKey(const Key('settings_defaults_note')), findsOneWidget);
    });

    testWidgets('the privacy policy opens and states the key promise', (
      WidgetTester tester,
    ) async {
      await _pumpSettings(tester);

      await _scrollTo(tester, find.byKey(const Key('open_privacy_policy')));
      await tester.tap(find.byKey(const Key('open_privacy_policy')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('privacy_policy_sheet')), findsOneWidget);
      expect(find.text('Nothing leaves your device'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      expect(find.text('App version'), findsOneWidget);
    });
  });
}
