import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/history/data/cleanup_history_repository.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_entry.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_history.dart';
import 'package:mobile_cleaner/features/history/presentation/screens/cleanup_history_screen.dart';
import 'package:mobile_cleaner/features/history/presentation/widgets/cleanup_history_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _mib = 1024 * 1024;

CleanupEntry _entry({
  required DateTime at,
  int files = 5,
  int bytes = 100 * _mib,
}) => CleanupEntry(
  performedAt: at,
  filesRemoved: files,
  bytesRecovered: bytes,
);

/// Two cleanups today totalling 1.8 GB, and one on an older day at 620 MB —
/// the example from the phase spec.
CleanupHistory _fixture({DateTime? now}) {
  final DateTime today = now ?? DateTime(2026, 8, 17, 19);
  return CleanupHistory.from(<CleanupEntry>[
    _entry(at: today, files: 12, bytes: 1200 * _mib),
    _entry(
      at: today.subtract(const Duration(hours: 3)),
      files: 4,
      bytes: 643 * _mib,
    ),
    _entry(at: DateTime(2026, 8, 11, 10), files: 9, bytes: 620 * _mib),
  ]);
}

class _StubHistory implements CleanupHistoryRepository {
  _StubHistory([CleanupHistory? initial])
    : history = initial ?? CleanupHistory.empty;

  CleanupHistory history;
  int clears = 0;

  @override
  Future<CleanupHistory> load() async => history;

  @override
  Future<CleanupHistory> record(CleanupEntry entry) async {
    history = CleanupHistory.from(<CleanupEntry>[entry, ...history.entries]);
    return history;
  }

  @override
  Future<void> clear() async {
    clears++;
    history = CleanupHistory.empty;
  }
}

class _FailingHistory implements CleanupHistoryRepository {
  const _FailingHistory();

  @override
  Future<CleanupHistory> load() => Future<CleanupHistory>.error(
    StateError('History unavailable'),
  );

  @override
  Future<CleanupHistory> record(CleanupEntry entry) => load();

  @override
  Future<void> clear() => Future<void>.error(StateError('History unavailable'));
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  CleanupHistoryRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cleanupHistoryRepositoryProvider.overrideWithValue(
          repository ?? _StubHistory(_fixture()),
        ),
      ],
      child: const MaterialApp(home: CleanupHistoryScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CleanupEntry storage', () {
    test('round-trips through JSON', () {
      final CleanupEntry entry = _entry(
        at: DateTime(2026, 8, 11, 10, 30),
        files: 9,
        bytes: 620 * _mib,
      );
      final CleanupEntry? restored = CleanupEntry.fromJson(
        jsonDecode(jsonEncode(entry.toJson())) as Map<String, Object?>,
      );

      expect(restored, isNotNull);
      expect(restored!.filesRemoved, 9);
      expect(restored.bytesRecovered, 620 * _mib);
      expect(restored.performedAt, entry.performedAt);
    });

    test('no file names are ever stored', () {
      final Map<String, Object?> json = _entry(
        at: DateTime(2026, 8, 11),
      ).toJson();
      // Only a timestamp, a count, and a size.
      expect(json.keys.toSet(), <String>{'at', 'files', 'bytes'});
    });

    test('a corrupt row is dropped, never defaulted', () {
      expect(CleanupEntry.fromJson(null), isNull);
      expect(CleanupEntry.fromJson('not a map'), isNull);
      // No timestamp.
      expect(
        CleanupEntry.fromJson(<Object?, Object?>{'files': 3, 'bytes': 10}),
        isNull,
      );
      // A cleanup that removed nothing is not worth remembering.
      expect(
        CleanupEntry.fromJson(<Object?, Object?>{
          'at': 1000,
          'files': 0,
          'bytes': 0,
        }),
        isNull,
      );
    });

    test('groups by calendar day, ignoring the time', () {
      final CleanupEntry entry = _entry(at: DateTime(2026, 8, 11, 23, 59));
      expect(entry.day, DateTime(2026, 8, 11));
    });
  });

  group('CleanupHistory', () {
    test('orders newest first', () {
      final CleanupHistory history = _fixture();
      expect(history.entries.first.bytesRecovered, 1200 * _mib);
      expect(history.entries.last.bytesRecovered, 620 * _mib);
    });

    test('combines same-day cleanups into one line', () {
      final List<CleanupDay> days = _fixture().byDay;

      expect(days, hasLength(2));
      // Two cleanups today: 1200 + 643 MB.
      expect(days.first.bytesRecovered, 1843 * _mib);
      expect(days.first.filesRemoved, 16);
      expect(days.first.cleanupCount, 2);
      // The older day stays separate.
      expect(days.last.bytesRecovered, 620 * _mib);
      expect(days.last.cleanupCount, 1);
    });

    test('lifetime totals count every cleanup once', () {
      final CleanupHistory history = _fixture();
      expect(history.totalBytesRecovered, 2463 * _mib);
      expect(history.totalFilesRemoved, 25);
      expect(history.cleanupCount, 3);
    });

    test('bytes within a window exclude older days', () {
      final CleanupHistory history = _fixture();
      final DateTime now = DateTime(2026, 8, 17, 20);

      // Today only.
      expect(history.bytesRecoveredWithin(1, now: now), 1843 * _mib);
      // A week back still misses 11 August.
      expect(history.bytesRecoveredWithin(7, now: now), 1843 * _mib);
      // Thirty days reaches it.
      expect(history.bytesRecoveredWithin(30, now: now), 2463 * _mib);
    });

    test('an empty history is not an error', () {
      expect(CleanupHistory.empty.isEmpty, isTrue);
      expect(CleanupHistory.empty.totalBytesRecovered, 0);
      expect(CleanupHistory.empty.mostRecent, isNull);
      expect(CleanupHistory.empty.byDay, isEmpty);
    });
  });

  group('Persistence', () {
    test('decoding survives corrupt storage', () {
      // Not JSON at all.
      expect(
        PreferencesCleanupHistoryRepository.decode('{{{').isEmpty,
        isTrue,
      );
      // Valid JSON, wrong shape.
      expect(
        PreferencesCleanupHistoryRepository.decode('{"a":1}').isEmpty,
        isTrue,
      );
      expect(PreferencesCleanupHistoryRepository.decode(null).isEmpty, isTrue);
      expect(PreferencesCleanupHistoryRepository.decode('').isEmpty, isTrue);
    });

    test('a partly corrupt log keeps the readable rows', () {
      final String raw = jsonEncode(<Object?>[
        <String, Object?>{'at': 1000, 'files': 2, 'bytes': 50},
        <String, Object?>{'files': 9},
        'garbage',
      ]);
      expect(
        PreferencesCleanupHistoryRepository.decode(raw).cleanupCount,
        1,
      );
    });

    test('entries survive a real save and reload', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const PreferencesCleanupHistoryRepository repository =
          PreferencesCleanupHistoryRepository();

      await repository.record(
        _entry(at: DateTime(2026, 8, 11), files: 9, bytes: 620 * _mib),
      );
      await repository.record(
        _entry(at: DateTime(2026, 8, 17), files: 12, bytes: 1200 * _mib),
      );

      final CleanupHistory loaded = await repository.load();
      expect(loaded.cleanupCount, 2);
      expect(loaded.totalBytesRecovered, 1820 * _mib);
      // Newest first.
      expect(loaded.entries.first.filesRemoved, 12);
    });

    test('a cleanup that removed nothing is not recorded', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const PreferencesCleanupHistoryRepository repository =
          PreferencesCleanupHistoryRepository();

      await repository.record(
        CleanupEntry(
          performedAt: DateTime(2026, 8, 17),
          filesRemoved: 0,
          bytesRecovered: 0,
        ),
      );
      expect((await repository.load()).isEmpty, isTrue);
    });

    test('the log is capped so preferences cannot grow without bound', () {
      final List<CleanupEntry> many = <CleanupEntry>[
        for (int i = 0; i < 250; i++)
          _entry(at: DateTime(2026, 1, 1).add(Duration(days: i))),
      ];
      final String encoded = PreferencesCleanupHistoryRepository.encode(many);
      // Encoding itself is uncapped; the cap is applied on write.
      expect(
        PreferencesCleanupHistoryRepository.decode(encoded).cleanupCount,
        250,
      );
      expect(PreferencesCleanupHistoryRepository.maxEntries, 200);
    });

    test('clearing removes everything', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const PreferencesCleanupHistoryRepository repository =
          PreferencesCleanupHistoryRepository();

      await repository.record(_entry(at: DateTime(2026, 8, 17)));
      await repository.clear();
      expect((await repository.load()).isEmpty, isTrue);
    });
  });

  group('History screen', () {
    testWidgets('lists days with date and space cleaned', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('history_list')), findsOneWidget);
      // Two cleanups today, combined.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('history_bytes_2026-08-17')))
            .data,
        '1.8 GB cleaned',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('history_bytes_2026-08-11')))
            .data,
        '620.0 MB cleaned',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('history_files_2026-08-11')))
            .data,
        '9 files removed',
      );
    });

    testWidgets('same-day cleanups report how many there were', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('history_files_2026-08-17')))
            .data,
        '16 files removed · 2 cleanups',
      );
    });

    testWidgets('shows lifetime totals and the privacy note', (
      WidgetTester tester,
    ) async {
      await _pumpScreen(tester);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('history_total_bytes')))
            .data,
        '2.4 GB',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('history_total_files')))
            .data,
        '25 files across 3 cleanups',
      );
      expect(find.byKey(const Key('history_privacy_note')), findsOneWidget);
    });

    testWidgets('an empty log explains itself', (WidgetTester tester) async {
      await _pumpScreen(tester, repository: _StubHistory());

      expect(find.byKey(const Key('history_empty')), findsOneWidget);
      expect(find.text('No cleanups yet'), findsOneWidget);
      // Nothing to clear, so no clear action.
      expect(find.byKey(const Key('history_clear')), findsNothing);
    });

    testWidgets('clearing asks first, and says files are untouched', (
      WidgetTester tester,
    ) async {
      final _StubHistory repository = _StubHistory(_fixture());
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('history_clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history_clear_dialog')), findsOneWidget);
      expect(find.textContaining('Your files are not affected'), findsWidgets);

      await tester.tap(find.byKey(const Key('history_clear_confirm')));
      await tester.pumpAndSettle();

      expect(repository.clears, 1);
      expect(find.byKey(const Key('history_empty')), findsOneWidget);
    });

    testWidgets('cancelling the clear keeps the history', (
      WidgetTester tester,
    ) async {
      final _StubHistory repository = _StubHistory(_fixture());
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('history_clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.clears, 0);
      expect(find.byKey(const Key('history_list')), findsOneWidget);
    });
  });

  group('Home history card', () {
    Future<void> pumpCard(
      WidgetTester tester,
      CleanupHistoryRepository repository,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cleanupHistoryRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CleanupHistoryCard(onOpen: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('summarises the lifetime total', (WidgetTester tester) async {
      await pumpCard(tester, _StubHistory(_fixture()));

      expect(find.byKey(const Key('home_history_card')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('home_history_total')))
            .data,
        '2.4 GB',
      );
      expect(find.text('Cleaned so far'), findsOneWidget);
    });

    testWidgets('shows an honest empty state before the first cleanup', (
      WidgetTester tester,
    ) async {
      await pumpCard(tester, _StubHistory());

      // Real data only: no invented amounts, no "0 B recovered" trophy —
      // just an honest note about where the numbers will appear.
      expect(find.byKey(const Key('home_history_card')), findsNothing);
      expect(find.byKey(const Key('home_history_empty')), findsOneWidget);
      expect(find.text('No cleanups yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows an honest error state when history cannot load', (
      WidgetTester tester,
    ) async {
      await pumpCard(tester, const _FailingHistory());

      expect(find.byKey(const Key('home_history_error')), findsOneWidget);
      expect(find.text('Cleanup summary is unavailable'), findsOneWidget);
      expect(find.byKey(const Key('home_history_retry')), findsOneWidget);
      expect(find.byKey(const Key('home_history_card')), findsNothing);
    });
  });
}
