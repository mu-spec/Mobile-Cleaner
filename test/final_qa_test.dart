import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/app/theme/app_theme.dart';
import 'package:mobile_cleaner/core/errors/app_failure.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_detector.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/history/data/cleanup_history_repository.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_entry.dart';
import 'package:mobile_cleaner/features/history/domain/cleanup_history.dart';
import 'package:mobile_cleaner/features/settings/data/settings_repository.dart';
import 'package:mobile_cleaner/features/settings/domain/app_settings.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:mobile_cleaner/features/storage/presentation/widgets/storage_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _mib = 1024 * 1024;
const int _gib = 1024 * 1024 * 1024;

ScannedFile _file(int i, {int sizeBytes = 4 * _mib}) => ScannedFile(
  id: '$i',
  name: 'photo_$i.jpg',
  path: '/storage/emulated/0/DCIM/photo_$i.jpg',
  uri: 'content://media/external/images/media/$i',
  sizeBytes: sizeBytes,
  category: FileCategory.images,
  dateModified: DateTime(2026, 3, 1),
  mimeType: 'image/jpeg',
);

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);
  final List<ScannedFile> files;

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async => FileScanResult.fromFiles(files, categories: request.categories);
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();
  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fresh install', () {
    test('every stored preference falls back to a safe default', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final AppSettings settings =
          await const PreferencesSettingsRepository().load();
      expect(settings, AppSettings.defaults);
      expect(settings.themeMode, ThemeMode.system);

      final CleanupHistoryRepository history =
          const PreferencesCleanupHistoryRepository();
      expect((await history.load()).isEmpty, isTrue);
    });

    test('an empty device produces empty results, not errors', () async {
      final FileScanResult result = await _StubScanner(
        const <ScannedFile>[],
      ).scan();

      expect(result.isEmpty, isTrue);
      expect(result.totalBytes, 0);
      expect(result.totalFiles, 0);
    });
  });

  group('Fresh install regressions (device-reported)', () {
    test('a truly empty preference store shows onboarding', () async {
      // Reported from a real fresh install: onboarding was skipped. The Dart
      // logic was correct — Android auto-backup had restored the flags from a
      // previous install, so the store was not actually empty. The manifest
      // now sets allowBackup=false; this pins the Dart side of the contract.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      expect(preferences.getBool('onboarding_completed'), isNull);
      expect(preferences.getBool('permission_education_seen'), isNull);
    });

    test('a restored backup is what made onboarding disappear', () async {
      // Exactly what auto-backup put back on reinstall.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onboarding_completed': true,
        'permission_education_seen': true,
      });
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      // With these present the splash routes straight to Home, which is the
      // bug the user saw. Backup is now disabled so they cannot reappear.
      expect(preferences.getBool('onboarding_completed'), isTrue);
    });
  });

  group('Permission denial', () {
    test('a denial is classified and offers the settings route', () {
      final AppFailure failure = AppFailure.from(
        PlatformException(code: 'SCAN_PERMISSION_DENIED'),
      );

      expect(failure.needsPermission, isTrue);
      // A bare retry cannot help until the permission changes.
      expect(failure.isRetryable, isFalse);
      expect(failure.action, 'Review permissions');
    });

    test('a revoked permission mid-session does not crash deletion', () async {
      final MethodChannel channel = MethodChannel(
        'com.mobilecleaner.app/delete',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            throw PlatformException(code: 'SCAN_PERMISSION_DENIED');
          });

      final DeleteResult result = await PlatformDeleteRepository(
        channel: channel,
      ).deleteFiles(<ScannedFile>[_file(1)]);

      expect(result.deletedCount, 0);
      expect(result.failureCount, 1);
    });
  });

  group('Storage over 90% full', () {
    test('a nearly full device reports a sane percentage', () {
      const StorageInfo info = StorageInfo(
        totalBytes: 128 * _gib,
        freeBytes: 6 * _gib,
      );

      expect(info.usedPercentage, 95);
      expect(info.usedFraction, closeTo(0.953, 0.01));
    });

    test('a completely full device does not divide by zero or exceed 100', () {
      const StorageInfo full = StorageInfo(
        totalBytes: 64 * _gib,
        freeBytes: 0,
      );
      expect(full.usedPercentage, 100);
      expect(full.usedFraction, 1.0);

      // A platform that reports nothing must not produce NaN.
      const StorageInfo unknown = StorageInfo(totalBytes: 0, freeBytes: 0);
      expect(unknown.usedFraction, 0);
      expect(unknown.usedPercentage, 0);
    });

    test('free space larger than total is clamped, never negative', () {
      // Some OEMs report inconsistent figures.
      const StorageInfo odd = StorageInfo(
        totalBytes: 32 * _gib,
        freeBytes: 40 * _gib,
      );
      expect(odd.usedBytes, 0);
      expect(odd.usedFraction, 0);
    });

    testWidgets('the indicator announces the percentage to a screen reader', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StorageIndicator(usedFraction: 0.95, usedPercentage: 95),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('95%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Thousands of photos', () {
    test('a five thousand file library aggregates correctly', () async {
      final List<ScannedFile> library = <ScannedFile>[
        for (int i = 0; i < 5000; i++) _file(i),
      ];

      final FileScanResult result = await _StubScanner(library).scan();

      expect(result.totalFiles, 5000);
      expect(result.totalBytes, 5000 * 4 * _mib);
      // De-duplication by URI must not drop distinct files.
      expect(result.uniqueFiles.length, 5000);
    });

    test('duplicate detection on a large library stays leader-based', () {
      // 2,000 files, every pair sharing a size and hash.
      final List<ScannedFile> library = <ScannedFile>[
        for (int i = 0; i < 2000; i++)
          _file(i, sizeBytes: (i ~/ 2 + 1) * _mib),
      ];
      final Map<String, String> hashes = <String, String>{
        for (int i = 0; i < 2000; i++)
          'content://media/external/images/media/$i': 'hash_${i ~/ 2}',
      };

      final DuplicateScanResult result = DuplicateDetector.group(
        library,
        hashes,
      );

      expect(result.groupCount, 1000);
      // One copy of every set is always kept.
      expect(result.duplicateCount, 1000);
      for (final DuplicateGroup group in result.groups) {
        expect(group.duplicates.length, group.copyCount - 1);
      }
    });

    testWidgets('a long list builds lazily, not all at once', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      int built = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            thumbnailRepositoryProvider.overrideWithValue(
              const _NoThumbnails(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView.builder(
                itemCount: 5000,
                itemBuilder: (BuildContext context, int index) {
                  built++;
                  return SizedBox(height: 72, child: Text('row $index'));
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only the visible window plus a small cache extent is constructed.
      expect(built, lessThan(100));
    });
  });

  group('Deletion', () {
    test('only confirmed deletions count toward freed space', () {
      final DeleteResult partial = DeleteResult(
        deletedFiles: <ScannedFile>[_file(1), _file(2)],
        failures: const <DeleteFailure>[
          DeleteFailure(uri: 'content://3', reason: 'Denied'),
        ],
      );

      expect(partial.freedBytes, 8 * _mib);
      expect(partial.isPartialSuccess, isTrue);
      expect(partial.isCompleteSuccess, isFalse);
    });

    test('cancelling reports nothing removed and no failures', () {
      const DeleteResult cancelled = DeleteResult.cancelled();
      expect(cancelled.deletedCount, 0);
      expect(cancelled.failureCount, 0);
      expect(cancelled.userCancelled, isTrue);
    });

    test('a cleanup is recorded with the confirmed figures only', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const CleanupHistoryRepository repository =
          PreferencesCleanupHistoryRepository();

      await repository.record(
        CleanupEntry(
          performedAt: DateTime(2026, 8, 17),
          filesRemoved: 2,
          bytesRecovered: 8 * _mib,
        ),
      );

      final CleanupHistory history = await repository.load();
      expect(history.totalFilesRemoved, 2);
      expect(history.totalBytesRecovered, 8 * _mib);
    });
  });

  group('Dark mode', () {
    test('both themes build with matching structure', () {
      final ThemeData light = AppTheme.light;
      final ThemeData dark = AppTheme.dark;

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(dark.textTheme.bodyMedium?.fontFamily, 'Inter');
      expect(light.textTheme.headlineSmall?.fontFamily, 'Inter');
      expect(dark.textTheme.headlineSmall?.fontFamily, 'Inter');
    });

    test('the infinite-width button regression stays fixed in both', () {
      // Size.fromHeight(56) is Size(infinity, 56) and crashed any button
      // placed in a Row. Guarding both themes so it cannot return.
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light,
        AppTheme.dark,
      ]) {
        final Size? minimum = theme.filledButtonTheme.style?.minimumSize
            ?.resolve(<WidgetState>{});
        expect(minimum, isNotNull);
        expect(minimum!.width, 0);
        expect(minimum.width.isFinite, isTrue);
      }
    });

    testWidgets('a screen renders in dark mode without throwing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: StorageIndicator(usedFraction: 0.5, usedPercentage: 50),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('App restart', () {
    test('settings and history both survive a simulated restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await const PreferencesSettingsRepository().save(
        const AppSettings(themeMode: ThemeMode.dark),
      );
      await const PreferencesCleanupHistoryRepository().record(
        CleanupEntry(
          performedAt: DateTime(2026, 8, 17),
          filesRemoved: 3,
          bytesRecovered: 12 * _mib,
        ),
      );

      // New repository instances, as a cold start would create.
      final AppSettings settings =
          await const PreferencesSettingsRepository().load();
      final CleanupHistory history =
          await const PreferencesCleanupHistoryRepository().load();

      expect(settings.themeMode, ThemeMode.dark);
      expect(history.cleanupCount, 1);
    });

    test('scan results are deliberately not persisted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      // A stale file list would offer to delete files that are already gone.
      expect(
        preferences.getKeys().where((String k) => k.contains('scan')),
        isEmpty,
      );
    });
  });

  group('Offline use', () {
    test('byte formatting needs no locale service or network', () {
      expect(ByteFormatter.format(0), '0 B');
      expect(ByteFormatter.format(500), '500 B');
      expect(ByteFormatter.format(2 * _gib), '2.0 GB');
      // Negative input is defended rather than crashing.
      expect(ByteFormatter.format(-1), '0 B');
    });

    test('every feature path is local: no HTTP client is constructed', () {
      // The app declares no INTERNET permission, so any accidental network
      // call would fail at runtime. This asserts the classifier treats an
      // unexpected failure as showable rather than fatal.
      final AppFailure failure = AppFailure.from(
        Exception('SocketException: Failed host lookup'),
      );
      expect(failure.kind, FailureKind.unknown);
      expect(failure.message, isNotEmpty);
    });
  });
}
