import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/core/utils/duration_formatter.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/data/file_scanner_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/video_sort.dart';
import 'package:mobile_cleaner/features/files/domain/video_summary.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/videos_screen.dart';

const int _mib = 1024 * 1024;

ScannedFile _video({
  required String id,
  required String name,
  required int sizeBytes,
  int? durationMillis,
  int daysOld = 10,
  FileCategory category = FileCategory.videos,
  String? mimeType = 'video/mp4',
}) {
  return ScannedFile(
    id: id,
    name: name,
    path: '/storage/emulated/0/DCIM/Camera/$name',
    uri: 'content://media/external/video/media/$id',
    sizeBytes: sizeBytes,
    category: category,
    dateModified: DateTime(2026, 3, 1, 12).subtract(Duration(days: daysOld)),
    mimeType: mimeType,
    relativePath: 'DCIM/Camera/',
    durationMillis: durationMillis,
  );
}

/// Four videos with distinct size/length/date orderings, a photo that must be
/// excluded, and a clip whose length MediaStore never resolved.
List<ScannedFile> _fixture() => <ScannedFile>[
  // Big but short and recent.
  _video(
    id: '1',
    name: 'drone.mp4',
    sizeBytes: 800 * _mib,
    durationMillis: 90 * 1000,
    daysOld: 2,
  ),
  // Small but the longest, and the oldest.
  _video(
    id: '2',
    name: 'lecture.mp4',
    sizeBytes: 120 * _mib,
    durationMillis: 3 * 3600 * 1000,
    daysOld: 400,
  ),
  // Middling everything.
  _video(
    id: '3',
    name: 'birthday.mp4',
    sizeBytes: 300 * _mib,
    durationMillis: 12 * 60 * 1000,
    daysOld: 60,
  ),
  // Length unknown.
  _video(id: '4', name: 'mystery.mkv', sizeBytes: 50 * _mib, daysOld: 30),
  // A photo: never in this section.
  _video(
    id: '5',
    name: 'photo.jpg',
    sizeBytes: 900 * _mib,
    category: FileCategory.images,
    mimeType: 'image/jpeg',
  ),
];

class _StubScanner implements FileScannerRepository {
  _StubScanner(this.files);

  final List<ScannedFile> files;
  final List<FileScanRequest> requests = <FileScanRequest>[];

  @override
  Future<FileScanResult> scan([
    FileScanRequest request = const FileScanRequest(),
  ]) async {
    requests.add(request);
    return FileScanResult.fromFiles(files, categories: request.categories);
  }
}

class _NoThumbnails implements ThumbnailRepository {
  const _NoThumbnails();

  @override
  Future<Uint8List?> load(ScannedFile file, {int size = 128}) async => null;
}

class _NoopDelete implements DeleteRepository {
  @override
  Future<DeleteResult> deleteFiles(List<ScannedFile> files) async =>
      DeleteResult(deletedFiles: files, failures: const <DeleteFailure>[]);
}

Future<_StubScanner> _pumpVideos(
  WidgetTester tester, {
  List<ScannedFile>? files,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _StubScanner scanner = _StubScanner(files ?? _fixture());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileScannerRepositoryProvider.overrideWithValue(scanner),
        thumbnailRepositoryProvider.overrideWithValue(const _NoThumbnails()),
        deleteRepositoryProvider.overrideWithValue(_NoopDelete()),
      ],
      child: const MaterialApp(home: VideosScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return scanner;
}

List<String> _names(VideoSort sort) => VideoSummary.from(_fixture(), sort)
    .videos
    .map((ScannedFile f) => f.name)
    .toList();

void main() {
  group('DurationFormatter', () {
    test('formats clip lengths without padding the hour away', () {
      expect(DurationFormatter.format(const Duration(seconds: 42)), '0:42');
      expect(
        DurationFormatter.format(const Duration(minutes: 4, seconds: 7)),
        '4:07',
      );
      expect(
        DurationFormatter.format(
          const Duration(hours: 1, minutes: 12, seconds: 5),
        ),
        '1:12:05',
      );
    });

    test('an unknown length is admitted, never shown as zero', () {
      expect(DurationFormatter.format(null), '--:--');
      expect(DurationFormatter.format(Duration.zero), '--:--');
      expect(
        DurationFormatter.format(const Duration(seconds: -5)),
        '--:--',
      );
    });

    test('totals read as an amount of footage, not a timestamp', () {
      expect(
        DurationFormatter.formatLong(const Duration(hours: 3, minutes: 12)),
        '3 hr 12 min',
      );
      expect(DurationFormatter.formatLong(const Duration(hours: 2)), '2 hr');
      expect(
        DurationFormatter.formatLong(const Duration(minutes: 45)),
        '45 min',
      );
      // A real clip is never rounded down to nothing.
      expect(
        DurationFormatter.formatLong(const Duration(seconds: 20)),
        '1 min',
      );
      expect(DurationFormatter.formatLong(null), '0 min');
    });
  });

  group('ScannedFile video metadata', () {
    test('a duration is parsed from the platform row', () {
      final ScannedFile? file = ScannedFile.fromPlatformMap(
        <Object?, Object?>{
          'id': '1',
          'name': 'clip.mp4',
          'path': '/storage/clip.mp4',
          'uri': 'content://media/external/video/media/1',
          'sizeBytes': 1000,
          'mimeType': 'video/mp4',
          'videoDurationMillis': 90000,
        },
      );

      expect(file?.durationMillis, 90000);
      expect(file?.duration, const Duration(seconds: 90));
      expect(file?.isVideo, isTrue);
    });

    test('zero and missing lengths both read as unknown, not 0:00', () {
      ScannedFile? build(Object? duration) => ScannedFile.fromPlatformMap(
        <Object?, Object?>{
          'id': '1',
          'name': 'clip.mp4',
          'uri': 'content://media/external/video/media/1',
          'sizeBytes': 1000,
          'mimeType': 'video/mp4',
          'videoDurationMillis': duration,
        },
      );

      expect(build(0)?.durationMillis, isNull);
      expect(build(null)?.durationMillis, isNull);
      expect(build(-1)?.durationMillis, isNull);
      expect(build(0)?.duration, isNull);
    });

    test('a video is recognised by MIME type even outside its category', () {
      final ScannedFile downloaded = _video(
        id: '9',
        name: 'saved.mp4',
        sizeBytes: 10 * _mib,
        category: FileCategory.downloads,
      );
      expect(downloaded.isVideo, isTrue);
      expect(VideoSummary.isVideo(downloaded), isTrue);
    });
  });

  group('VideoSort', () {
    test('largest orders by size', () {
      expect(_names(VideoSort.largest), <String>[
        'drone.mp4',
        'birthday.mp4',
        'lecture.mp4',
        'mystery.mkv',
      ]);
    });

    test('longest orders by playback length, not by size', () {
      expect(_names(VideoSort.longest), <String>[
        'lecture.mp4',
        'birthday.mp4',
        'drone.mp4',
        // Unknown length sorts last, never first.
        'mystery.mkv',
      ]);
    });

    test('newest and oldest are exact reverses on distinct dates', () {
      expect(_names(VideoSort.newest), <String>[
        'drone.mp4',
        'mystery.mkv',
        'birthday.mp4',
        'lecture.mp4',
      ]);
      expect(
        _names(VideoSort.oldest),
        _names(VideoSort.newest).reversed.toList(),
      );
    });

    test('ties break on name, so the order never shuffles', () {
      final List<ScannedFile> tied = <ScannedFile>[
        _video(id: '1', name: 'zebra.mp4', sizeBytes: 10 * _mib, daysOld: 5),
        _video(id: '2', name: 'apple.mp4', sizeBytes: 10 * _mib, daysOld: 5),
      ];
      final VideoSummary first = VideoSummary.from(tied, VideoSort.largest);
      final VideoSummary second = VideoSummary.from(
        tied.reversed,
        VideoSort.largest,
      );

      expect(first.videos.first.name, 'apple.mp4');
      expect(
        first.videos.map((ScannedFile f) => f.name),
        second.videos.map((ScannedFile f) => f.name),
      );
    });

    test('all four orderings are offered, largest by default', () {
      expect(VideoSort.values, hasLength(4));
      expect(VideoSort.values.map((VideoSort s) => s.label), <String>[
        'Largest',
        'Longest',
        'Newest',
        'Oldest',
      ]);
      expect(VideoSort.defaultSort, VideoSort.largest);
    });
  });

  group('VideoSummary', () {
    test('photos are excluded even when they are the biggest file', () {
      final VideoSummary summary = VideoSummary.from(
        _fixture(),
        VideoSort.largest,
      );

      expect(
        summary.videos.map((ScannedFile f) => f.name),
        isNot(contains('photo.jpg')),
      );
      expect(summary.videoCount, 4);
      // 800 + 120 + 300 + 50, without the 900 MB photo.
      expect(summary.totalBytes, 1270 * _mib);
    });

    test('a video reported twice is counted once', () {
      final ScannedFile clip = _video(
        id: '1',
        name: 'clip.mp4',
        sizeBytes: 10 * _mib,
        durationMillis: 1000,
      );
      final VideoSummary summary = VideoSummary.from(
        <ScannedFile>[clip, clip],
        VideoSort.largest,
      );

      expect(summary.videoCount, 1);
      expect(summary.totalBytes, 10 * _mib);
    });

    test('total footage counts only known lengths, and says so', () {
      final VideoSummary summary = VideoSummary.from(
        _fixture(),
        VideoSort.largest,
      );

      // 90s + 3h + 12min.
      expect(
        summary.totalDuration,
        const Duration(hours: 3, minutes: 13, seconds: 30),
      );
      expect(summary.unknownDurationCount, 1);
      expect(summary.hasUnknownDurations, isTrue);
    });

    test('largest and longest can be different videos', () {
      final VideoSummary summary = VideoSummary.from(
        _fixture(),
        VideoSort.largest,
      );

      expect(summary.largestVideo?.name, 'drone.mp4');
      expect(summary.longestVideo?.name, 'lecture.mp4');
    });

    test('longest is null when no length is known at all', () {
      final VideoSummary summary = VideoSummary.from(
        <ScannedFile>[_video(id: '1', name: 'a.mp4', sizeBytes: 10 * _mib)],
        VideoSort.longest,
      );
      expect(summary.longestVideo, isNull);
      expect(summary.hasUnknownDurations, isTrue);
    });

    test('an empty library is empty, not an error', () {
      final VideoSummary summary = VideoSummary.from(
        const <ScannedFile>[],
        VideoSort.largest,
      );
      expect(summary.isEmpty, isTrue);
      expect(summary.averageBytes, 0);
      expect(summary.largestVideo, isNull);
      expect(VideoSummary.empty.isEmpty, isTrue);
    });
  });

  group('Videos screen', () {
    testWidgets('scans videos only', (WidgetTester tester) async {
      final _StubScanner scanner = await _pumpVideos(tester);

      expect(scanner.requests, hasLength(1));
      expect(scanner.requests.single.categories, <FileCategory>[
        FileCategory.videos,
      ]);
    });

    testWidgets('shows thumbnail, name, duration, size, and date per row', (
      WidgetTester tester,
    ) async {
      await _pumpVideos(tester);

      expect(find.byKey(const Key('video_tile_1')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('video_name_1'))).data,
        'drone.mp4',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('video_duration_1'))).data,
        '1:30',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('video_size_1'))).data,
        '800.0 MB',
      );
      expect(find.byKey(const Key('video_date_1')), findsOneWidget);
    });

    testWidgets('a video of unknown length shows the placeholder', (
      WidgetTester tester,
    ) async {
      await _pumpVideos(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('video_duration_4'))).data,
        '--:--',
      );
    });

    testWidgets('the headline reports space and footage', (
      WidgetTester tester,
    ) async {
      await _pumpVideos(tester);

      expect(
        tester
            .widget<Text>(find.byKey(const Key('videos_total_bytes')))
            .data,
        '1.2 GB',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('videos_count'))).data,
        '4 videos · 3 hr 13 min',
      );
      // The missing length is disclosed, not glossed over.
      expect(find.byKey(const Key('videos_unknown_note')), findsOneWidget);
    });

    testWidgets('all four sorts are offered and reorder the list', (
      WidgetTester tester,
    ) async {
      await _pumpVideos(tester);

      for (final VideoSort sort in VideoSort.values) {
        expect(find.byKey(Key('video_sort_${sort.name}')), findsOneWidget);
      }

      // Largest leads by default.
      expect(
        tester.widget<Text>(find.byKey(const Key('videos_sort_note'))).data,
        'Biggest files first',
      );

      await tester.tap(find.byKey(const Key('video_sort_longest')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('videos_sort_note'))).data,
        'Longest playback first',
      );
    });

    testWidgets('re-sorting does not rescan the device', (
      WidgetTester tester,
    ) async {
      final _StubScanner scanner = await _pumpVideos(tester);
      expect(scanner.requests, hasLength(1));

      await tester.tap(find.byKey(const Key('video_sort_oldest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('video_sort_newest')));
      await tester.pumpAndSettle();

      // Every ordering is a re-sort of the same scan.
      expect(scanner.requests, hasLength(1));
    });

    testWidgets('re-sorting keeps the selection, since nothing left the list', (
      WidgetTester tester,
    ) async {
      await _pumpVideos(tester);

      await tester.tap(find.byKey(const Key('video_checkbox_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('videos_selection_bar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('video_sort_oldest')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('videos_selection_count')))
            .data,
        '1 selected',
      );
    });

    testWidgets('selecting reveals a working Delete action', (
      WidgetTester tester,
    ) async {
      await _pumpVideos(tester);
      expect(find.byKey(const Key('videos_selection_bar')), findsNothing);

      await tester.tap(find.byKey(const Key('video_checkbox_1')));
      await tester.pumpAndSettle();

      final FilledButton delete = tester.widget<FilledButton>(
        find.byKey(const Key('videos_selection_delete')),
      );
      expect(delete.onPressed, isNotNull);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('videos_selection_bytes')))
            .data,
        '800.0 MB',
      );
    });

    testWidgets('select all covers every video and nothing else', (
      WidgetTester tester,
    ) async {
      await _pumpVideos(tester);

      await tester.tap(find.byKey(const Key('videos_select_all')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('videos_selection_count')))
            .data,
        '4 selected',
      );
    });

    testWidgets('an empty library says so', (WidgetTester tester) async {
      await _pumpVideos(tester, files: const <ScannedFile>[]);

      expect(find.byKey(const Key('videos_empty')), findsOneWidget);
      expect(find.byKey(const Key('videos_selection_bar')), findsNothing);
    });
  });
}
