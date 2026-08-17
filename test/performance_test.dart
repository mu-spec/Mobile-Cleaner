import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_cleaner/features/files/data/file_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/perceptual_hash_repository.dart';
import 'package:mobile_cleaner/features/files/data/photo_quality_repository.dart';
import 'package:mobile_cleaner/features/files/data/thumbnail_repository.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';

ScannedFile _file(int i, {FileCategory category = FileCategory.images}) =>
    ScannedFile(
      id: '$i',
      name: 'file_$i.jpg',
      path: '/storage/emulated/0/DCIM/file_$i.jpg',
      uri: 'content://media/external/images/media/$i',
      sizeBytes: 4 * 1024 * 1024,
      category: category,
      dateModified: DateTime(2026, 3, 1),
      mimeType: 'image/jpeg',
    );

List<ScannedFile> _library(int count) =>
    <ScannedFile>[for (int i = 0; i < count; i++) _file(i)];

/// Records every batch a channel receives.
class _BatchRecorder {
  _BatchRecorder(this.channelName, this.method, this.respond) {
    channel = MethodChannel(channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method != method) {
            return null;
          }
          final List<Object?> uris =
              (call.arguments as Map<Object?, Object?>)['uris']
                  as List<Object?>;
          batches.add(uris.length);
          return respond(uris);
        });
  }

  final String channelName;
  final String method;
  final Object? Function(List<Object?>) respond;

  late final MethodChannel channel;
  final List<int> batches = <int>[];

  int get totalReceived =>
      batches.fold<int>(0, (int sum, int n) => sum + n);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Large libraries are not silently truncated', () {
    test('hashing 900 files reaches the native side in full', () async {
      final _BatchRecorder recorder = _BatchRecorder(
        'com.mobilecleaner.app/hash',
        'hashFiles',
        (List<Object?> uris) => <Object?, Object?>{
          for (final Object? uri in uris) uri: 'hash_$uri',
        },
      );

      final Map<String, String> hashes = await PlatformFileHashRepository(
        channel: recorder.channel,
      ).hashFiles(_library(900));

      // Previously one 900-URI call, of which the native side hashed 400 and
      // dropped 500 — so 500 duplicates were never found.
      expect(hashes.length, 900);
      expect(recorder.totalReceived, 900);
      expect(recorder.batches, <int>[400, 400, 100]);
    });

    test('no batch exceeds the native cap', () async {
      final _BatchRecorder recorder = _BatchRecorder(
        'com.mobilecleaner.app/hash',
        'hashFiles',
        (List<Object?> uris) => <Object?, Object?>{
          for (final Object? uri in uris) uri: 'h',
        },
      );

      await PlatformFileHashRepository(
        channel: recorder.channel,
      ).hashFiles(_library(1500));

      for (final int size in recorder.batches) {
        expect(
          size,
          lessThanOrEqualTo(PlatformFileHashRepository.maxUrisPerCall),
        );
      }
    });

    test('perceptual hashing chunks too', () async {
      final _BatchRecorder recorder = _BatchRecorder(
        'com.mobilecleaner.app/perceptual_hash',
        'hashImages',
        (List<Object?> uris) => <Object?, Object?>{
          for (final Object? uri in uris) uri: '${'a' * 16}${'b' * 16}',
        },
      );

      final Map<String, String> hashes =
          await PlatformPerceptualHashRepository(
            channel: recorder.channel,
          ).hashImages(_library(1300));

      expect(hashes.length, 1300);
      expect(recorder.batches, <int>[600, 600, 100]);
    });

    test('photo quality chunks too', () async {
      final _BatchRecorder recorder = _BatchRecorder(
        'com.mobilecleaner.app/photo_quality',
        'analyzePhotos',
        (List<Object?> uris) => <Object?, Object?>{
          for (final Object? uri in uris)
            uri: <Object?, Object?>{
              'width': 4000,
              'height': 3000,
              'pixels': 12000000,
              'sharpness': 100.0,
            },
        },
      );

      await PlatformPhotoQualityRepository(
        channel: recorder.channel,
      ).analyzePhotos(_library(700));

      expect(recorder.batches, <int>[300, 300, 100]);
    });

    test('a mid-way failure keeps what earlier batches produced', () async {
      int calls = 0;
      final MethodChannel channel = MethodChannel(
        'com.mobilecleaner.app/hash',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls++;
            if (calls > 1) {
              throw PlatformException(code: 'HASH_FAILED');
            }
            final List<Object?> uris =
                (call.arguments as Map<Object?, Object?>)['uris']
                    as List<Object?>;
            return <Object?, Object?>{
              for (final Object? uri in uris) uri: 'h',
            };
          });

      final Map<String, String> hashes = await PlatformFileHashRepository(
        channel: channel,
      ).hashFiles(_library(900));

      // The first 400 survive rather than the whole scan failing.
      expect(hashes.length, 400);
    });
  });

  group('Caching avoids repeat work', () {
    test('a second hash request does no platform work', () async {
      final _BatchRecorder recorder = _BatchRecorder(
        'com.mobilecleaner.app/hash',
        'hashFiles',
        (List<Object?> uris) => <Object?, Object?>{
          for (final Object? uri in uris) uri: 'h',
        },
      );

      final PlatformFileHashRepository repository =
          PlatformFileHashRepository(channel: recorder.channel);
      final List<ScannedFile> files = _library(50);

      await repository.hashFiles(files);
      final int afterFirst = recorder.batches.length;
      await repository.hashFiles(files);

      expect(recorder.batches.length, afterFirst);
    });

    test('only uncached files are re-requested', () async {
      final _BatchRecorder recorder = _BatchRecorder(
        'com.mobilecleaner.app/hash',
        'hashFiles',
        (List<Object?> uris) => <Object?, Object?>{
          for (final Object? uri in uris) uri: 'h',
        },
      );

      final PlatformFileHashRepository repository =
          PlatformFileHashRepository(channel: recorder.channel);

      await repository.hashFiles(_library(10));
      recorder.batches.clear();
      // Twenty files, ten already known.
      await repository.hashFiles(_library(20));

      expect(recorder.totalReceived, 10);
    });
  });

  group('Thumbnail memory is bounded', () {
    Uint8List bytesOf(int size) => Uint8List(size);

    test('the cache never exceeds its entry cap', () async {
      final MethodChannel channel = MethodChannel(
        'com.mobilecleaner.app/thumbnails',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (MethodCall call) async => bytesOf(1024),
          );

      final PlatformThumbnailRepository repository =
          PlatformThumbnailRepository(channel: channel);

      // Far more files than the cap: a real photo library.
      for (final ScannedFile file in _library(600)) {
        await repository.load(file);
      }

      expect(
        repository.cachedEntryCount,
        lessThanOrEqualTo(PlatformThumbnailRepository.maxCacheEntries),
      );
    });

    test('the cache never exceeds its byte cap', () async {
      final MethodChannel channel = MethodChannel(
        'com.mobilecleaner.app/thumbnails',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            // 512 KB each: 30 of these would pass the byte ceiling long
            // before the entry ceiling.
            channel,
            (MethodCall call) async => bytesOf(512 * 1024),
          );

      final PlatformThumbnailRepository repository =
          PlatformThumbnailRepository(channel: channel);

      for (final ScannedFile file in _library(120)) {
        await repository.load(file);
      }

      expect(
        repository.cachedByteCount,
        lessThanOrEqualTo(PlatformThumbnailRepository.maxCacheBytes),
      );
      // Evicted on bytes, well before the 240-entry cap.
      expect(
        repository.cachedEntryCount,
        lessThan(PlatformThumbnailRepository.maxCacheEntries),
      );
    });

    test('a repeat request is served from cache', () async {
      int calls = 0;
      final MethodChannel channel = MethodChannel(
        'com.mobilecleaner.app/thumbnails',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls++;
            return bytesOf(64);
          });

      final PlatformThumbnailRepository repository =
          PlatformThumbnailRepository(channel: channel);

      await repository.load(_file(1));
      await repository.load(_file(1));
      await repository.load(_file(1));

      expect(calls, 1);
    });

    test('simultaneous requests for one file share a single decode', () async {
      int calls = 0;
      final MethodChannel channel = MethodChannel(
        'com.mobilecleaner.app/thumbnails',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls++;
            return bytesOf(64);
          });

      final PlatformThumbnailRepository repository =
          PlatformThumbnailRepository(channel: channel);

      // Two tiles showing the same file during a fast scroll.
      await Future.wait<Uint8List?>(<Future<Uint8List?>>[
        repository.load(_file(7)),
        repository.load(_file(7)),
        repository.load(_file(7)),
      ]);

      expect(calls, 1);
    });

    test('a file with no thumbnail costs no platform call', () async {
      int calls = 0;
      final MethodChannel channel = MethodChannel(
        'com.mobilecleaner.app/thumbnails',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls++;
            return null;
          });

      await PlatformThumbnailRepository(channel: channel).load(
        _file(1, category: FileCategory.documents).copyWith(
          mimeType: 'application/pdf',
        ),
      );

      expect(calls, 0);
    });

    test('a failed thumbnail is remembered, not retried forever', () async {
      int calls = 0;
      final MethodChannel channel = MethodChannel(
        'com.mobilecleaner.app/thumbnails',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls++;
            throw PlatformException(code: 'NO_THUMBNAIL');
          });

      final PlatformThumbnailRepository repository =
          PlatformThumbnailRepository(channel: channel);

      expect(await repository.load(_file(3)), isNull);
      expect(await repository.load(_file(3)), isNull);

      // The null result is cached, so a broken file is not re-read on every
      // rebuild while scrolling.
      expect(calls, 1);
    });
  });
}
