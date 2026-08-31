import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/features/cleaner/presentation/screens/clean_screen.dart';
import 'package:mobile_cleaner/features/files/data/file_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/home/domain/cleanup_score.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation.dart';
import 'package:mobile_cleaner/features/home/domain/recommendation_engine.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/recommendation_destination.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/cleanup_score_card.dart';
import 'package:mobile_cleaner/features/storage/data/storage_repository.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';

const int _mib = 1024 * 1024;
const int _gib = 1024 * 1024 * 1024;

class _CountingScanner implements FileScannerRepository {
  _CountingScanner(this.files);

  List<ScannedFile> files;
  int calls = 0;

  void replaceFiles(List<ScannedFile> replacement) {
    files = replacement;
  }

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    calls++;
    final List<ScannedFile> matching = files
        .where(
          (ScannedFile file) =>
              request.categories.contains(file.category) &&
              file.sizeBytes >= request.minSizeBytes,
        )
        .toList(growable: false);
    return FileScanResult.fromFiles(matching, categories: request.categories);
  }
}

class _Hashes implements FileHashRepository {
  const _Hashes();

  @override
  Future<Map<String, String>> hashFiles(List<ScannedFile> files) async =>
      const <String, String>{};
}

class _Storage implements StorageRepository {
  const _Storage();

  @override
  Future<StorageInfo> getStorageInfo() async =>
      const StorageInfo(totalBytes: 128 * _gib, freeBytes: 40 * _gib);
}

ScannedFile _file({
  required String id,
  required String name,
  required int bytes,
  required FileCategory category,
  String mimeType = 'application/octet-stream',
  String relativePath = 'Download/',
}) => ScannedFile(
  id: id,
  name: name,
  path: '/storage/emulated/0/$relativePath$name',
  uri: 'content://media/external/file/$id',
  sizeBytes: bytes,
  category: category,
  dateModified: DateTime.now().subtract(const Duration(days: 120)),
  mimeType: mimeType,
  relativePath: relativePath,
);

ProviderContainer _container(_CountingScanner scanner) => ProviderContainer(
  overrides: [
    fileScannerRepositoryProvider.overrideWithValue(scanner),
    fileHashRepositoryProvider.overrideWithValue(const _Hashes()),
    storageRepositoryProvider.overrideWithValue(const _Storage()),
  ],
);

List<Recommendation> _recommendations(ProviderContainer container) =>
    container.read(recommendationsProvider).requireValue;

void main() {
  test('no Smart Scan means no specific recommendation or analyzer work', () {
    final _CountingScanner scanner = _CountingScanner(<ScannedFile>[
      for (int index = 0; index < 25; index++)
        _file(
          id: 'shot-$index',
          name: 'Screenshot_$index.png',
          bytes: 4 * _mib,
          category: FileCategory.images,
          mimeType: 'image/png',
          relativePath: 'Pictures/Screenshots/',
        ),
    ]);
    final ProviderContainer container = _container(scanner);
    addTearDown(container.dispose);

    expect(_recommendations(container), isEmpty);
    expect(container.read(cleanupAnalysisProvider).requireValue, isNull);
    expect(scanner.calls, 0);
  });

  test(
    'completed Smart Scan publishes recommendations from real results',
    () async {
      final _CountingScanner scanner = _CountingScanner(<ScannedFile>[
        for (int index = 0; index < 25; index++)
          _file(
            id: 'shot-$index',
            name: 'Screenshot_$index.png',
            bytes: 4 * _mib,
            category: FileCategory.images,
            mimeType: 'image/png',
            relativePath: 'Pictures/Screenshots/',
          ),
      ]);
      final ProviderContainer container = _container(scanner);
      addTearDown(container.dispose);

      await container.read(recommendationsProvider.notifier).scan();

      final Recommendation screenshot = _recommendations(container).single;
      final CompletedCleanupAnalysis analysis = container
          .read(cleanupAnalysisProvider)
          .requireValue!;
      expect(screenshot.kind, RecommendationKind.screenshotReview);
      expect(screenshot.reclaimableBytes, 100 * _mib);
      expect(analysis.recommendations, _recommendations(container));
      expect(analysis.score.opportunityBytes, 100 * _mib);
      expect(
        analysis.score.breakdown.single.kind,
        CleanupOpportunityKind.oldScreenshots,
      );
      expect(scanner.calls, greaterThan(0));
    },
  );

  test(
    'all applicable Smart Scan file analyzers contribute real findings',
    () async {
      final _CountingScanner scanner = _CountingScanner(<ScannedFile>[
        _file(
          id: 'installer',
          name: 'release.apk',
          bytes: 700 * _mib,
          category: FileCategory.downloads,
          mimeType: 'application/vnd.android.package-archive',
        ),
      ]);
      final ProviderContainer container = _container(scanner);
      addTearDown(container.dispose);

      await container.read(recommendationsProvider.notifier).scan();
      final List<Recommendation> found = _recommendations(container);

      expect(
        found.map((Recommendation item) => item.kind),
        containsAll(<RecommendationKind>[
          RecommendationKind.largeFileReview,
          RecommendationKind.oldDownloadReview,
          RecommendationKind.apkInstallerReview,
        ]),
      );
      expect(found.first.kind, RecommendationKind.apkInstallerReview);
      expect(found.first.reclaimableBytes, 700 * _mib);
    },
  );

  testWidgets(
    'results and Home share the latest score and a later scan replaces it',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _CountingScanner scanner = _CountingScanner(<ScannedFile>[]);
      final ProviderContainer container = _container(scanner);
      addTearDown(container.dispose);
      final RecommendationsController controller = container.read(
        recommendationsProvider.notifier,
      );

      await controller.scan();
      final CompletedCleanupAnalysis first = container
          .read(cleanupAnalysisProvider)
          .requireValue!;
      expect(first.score.value, 100);

      scanner.replaceFiles(<ScannedFile>[
        for (int index = 0; index < 25; index++)
          _file(
            id: 'replacement-shot-$index',
            name: 'Screenshot_replacement_$index.png',
            bytes: 40 * _mib,
            category: FileCategory.images,
            mimeType: 'image/png',
            relativePath: 'Pictures/Screenshots/',
          ),
      ]);
      await controller.scan();

      final CompletedCleanupAnalysis latest = container
          .read(cleanupAnalysisProvider)
          .requireValue!;
      expect(latest.score.value, lessThan(first.score.value));
      expect(latest.scannedAt, isNot(first.scannedAt));
      final int callsAfterScan = scanner.calls;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CleanScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('smart_scan_cleanup_score_value')),
            )
            .data,
        '${latest.score.value} / 100',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('smart_scan_cleanup_score_label')),
            )
            .data,
        latest.score.label.label,
      );
      expect(scanner.calls, callsAfterScan);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: CleanupScoreCard(onOpen: (_) {})),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('cleanup_score_value'))).data,
        '${latest.score.value}',
      );
      expect(scanner.calls, callsAfterScan);
    },
  );

  test(
    'multiple findings rank deterministically by space then safe tie-break',
    () {
      const RecommendationInputs inputs = RecommendationInputs(
        duplicateReclaimableBytes: 2 * _gib,
        duplicateGroupCount: 4,
        largeVideoCount: 2,
        largeVideoBytes: 5 * _gib,
        largestVideo: null,
        oldDownloadCount: 2,
        oldDownloadBytes: 900 * _mib,
        apkInstallerCount: 2,
        apkInstallerBytes: 900 * _mib,
      );

      final List<Recommendation> first = RecommendationEngine.evaluate(inputs);
      final List<Recommendation> second = RecommendationEngine.evaluate(inputs);

      expect(
        first.map((Recommendation item) => item.kind),
        <RecommendationKind>[
          RecommendationKind.duplicateCleanup,
          RecommendationKind.apkInstallerReview,
          RecommendationKind.oldDownloadReview,
        ],
      );
      expect(
        second.map((Recommendation item) => item.kind),
        first.map((Recommendation item) => item.kind),
      );
    },
  );

  test('completed scan with no findings fabricates nothing', () async {
    final _CountingScanner scanner = _CountingScanner(const <ScannedFile>[]);
    final ProviderContainer container = _container(scanner);
    addTearDown(container.dispose);

    await container.read(recommendationsProvider.notifier).scan();

    expect(_recommendations(container), isEmpty);
    final CompletedCleanupAnalysis analysis = container
        .read(cleanupAnalysisProvider)
        .requireValue!;
    expect(analysis.score.value, 100);
    expect(analysis.score.label, CleanupScoreLabel.excellent);
    expect(analysis.score.breakdown, isEmpty);
    expect(scanner.calls, greaterThan(0));
  });

  test('each recommendation routes to its existing review screen', () {
    expect(
      recommendationRoute(RecommendationKind.duplicateCleanup),
      AppRoutes.duplicates,
    );
    expect(
      recommendationRoute(RecommendationKind.apkInstallerReview),
      AppRoutes.apkCleaner,
    );
    expect(
      recommendationRoute(RecommendationKind.oldDownloadReview),
      AppRoutes.downloadsCleaner,
    );
    expect(
      recommendationRoute(RecommendationKind.screenshotReview),
      AppRoutes.screenshotCleaner,
    );
    expect(
      recommendationRoute(RecommendationKind.largeFileReview),
      AppRoutes.largeFiles,
    );
    expect(
      recommendationRoute(RecommendationKind.largeVideoReview),
      AppRoutes.videos,
    );
    expect(
      recommendationKindForOpportunity(CleanupOpportunityKind.exactDuplicates),
      RecommendationKind.duplicateCleanup,
    );
    expect(
      recommendationKindForOpportunity(CleanupOpportunityKind.apkInstallers),
      RecommendationKind.apkInstallerReview,
    );
    expect(
      recommendationKindForOpportunity(CleanupOpportunityKind.oldDownloads),
      RecommendationKind.oldDownloadReview,
    );
    expect(
      recommendationKindForOpportunity(CleanupOpportunityKind.oldScreenshots),
      RecommendationKind.screenshotReview,
    );
    expect(
      recommendationKindForOpportunity(CleanupOpportunityKind.largeFiles),
      RecommendationKind.largeFileReview,
    );
    expect(
      recommendationKindForOpportunity(CleanupOpportunityKind.largeVideos),
      RecommendationKind.largeVideoReview,
    );
  });

  test('successful-cleanup invalidation clears stale recommendation', () async {
    final _CountingScanner scanner = _CountingScanner(<ScannedFile>[
      _file(
        id: 'installer',
        name: 'release.apk',
        bytes: 700 * _mib,
        category: FileCategory.downloads,
      ),
    ]);
    final ProviderContainer container = _container(scanner);
    addTearDown(container.dispose);
    final RecommendationsController controller = container.read(
      recommendationsProvider.notifier,
    );
    await controller.scan();
    expect(_recommendations(container), isNotEmpty);

    controller.invalidateAfterCleanup();

    expect(_recommendations(container), isEmpty);
    expect(container.read(cleanupAnalysisProvider).requireValue, isNull);
  });

  test('new app session does not restore old scan recommendations', () async {
    final _CountingScanner scanner = _CountingScanner(<ScannedFile>[
      _file(
        id: 'installer',
        name: 'release.apk',
        bytes: 700 * _mib,
        category: FileCategory.downloads,
      ),
    ]);
    final ProviderContainer oldSession = _container(scanner);
    await oldSession.read(recommendationsProvider.notifier).scan();
    expect(_recommendations(oldSession), isNotEmpty);
    oldSession.dispose();
    final int callsAfterOldScan = scanner.calls;

    final ProviderContainer newSession = _container(scanner);
    addTearDown(newSession.dispose);

    expect(_recommendations(newSession), isEmpty);
    expect(newSession.read(cleanupAnalysisProvider).requireValue, isNull);
    expect(scanner.calls, callsAfterOldScan);
  });
}
