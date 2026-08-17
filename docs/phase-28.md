# Phase 28 — Performance Optimization

Target: phones with thousands of files. Thumbnails, scanning, hashing, caching,
memory, scrolling.

## The two real bugs found

Auditing the hot paths turned up two problems that are **correctness** issues,
not just slowness — and both only appear on a large library, which is why no
earlier phase caught them.

### 1. Silent truncation past the native cap

`FileHashBridge` caps one call at 400 URIs and **silently drops the rest**:

```kotlin
val capped = uris.take(MAX_FILES_PER_CALL)
```

The Dart side sent every candidate in one call. So on a library with 900
size-matched candidates, 400 were hashed and **500 were never compared** —
duplicates that genuinely existed were reported as absent. The same held for
`PerceptualHashBridge` (600) and `PhotoQualityBridge` (300).

All three repositories now chunk to the native cap. A test sends 900 files and
asserts the batches are `[400, 400, 100]` and all 900 come back. Chunking also
means a mid-way failure keeps earlier results instead of losing everything —
also tested.

### 2. `thumbnailProvider` leaked one entry per file, forever

```dart
FutureProvider.family<Uint8List?, ScannedFile>   // before
```

A plain `family` keeps one provider alive per key for the life of the
`ProviderScope`. Scroll past 5,000 photos and you hold 5,000 live entries, each
retaining decoded JPEG bytes, none ever released. That was the largest memory
risk in the app.

Now `FutureProvider.autoDispose.family`, so entries drop when no tile is showing
that file. Memory tracks what is on screen, not what has ever been scrolled
past.

## Thumbnails

- **Decode at display size.** `Image.memory` had no `cacheWidth`/`cacheHeight`,
  so a 44px tile decoded the full-resolution bitmap into the image cache. Both
  `FileThumbnail` and `AppIcon` now decode to the drawn size, scaled by device
  pixel ratio and clamped.
- **Real LRU, bounded by bytes as well as count.** The old cache was FIFO and
  counted entries only — 240 entries means very different things for 44px and
  128px thumbnails. Now 240 entries **or** 12 MB, whichever comes first, with
  most-recently-used re-insertion.
- **In-flight de-duplication.** Two tiles showing the same file during a fast
  scroll previously issued two platform calls. They now share one future.
- **Negative caching.** A file with no thumbnail caches its `null`, so a broken
  or unreadable file is not re-requested on every rebuild while scrolling.

## Memory

Flutter's default image cache is 100 MB, sized for galleries showing large
images. This app shows hundreds of small thumbnails, so `main.dart` lowers it to
24 MB / 400 entries — far more headroom on a low-memory phone, still ample for
a long scroll.

The three session caches (`hash`, `perceptual_hash`, `photo_quality`) were
**unbounded maps** that grew for the life of the process. Each is now capped at
5,000 entries with oldest-first trimming. They hold short strings, so the cap is
generous while still being a ceiling.

## What was already right

Worth stating, because it means no change was needed:

- Every list is `ListView.builder` — fixed in `59999c8` after the selection
  freeze.
- Scans are capped per category and expose `truncated`, so a huge library is
  bounded and says so.
- Hashing is gated behind a size match, so most files are never read.
- Similar-photo strength re-groups in memory rather than re-decoding.
- The dashboards compose cached tool providers rather than re-scanning.

## Files

**New:** `test/performance_test.dart` (14 cases).

**Changed:** `thumbnail_provider.dart` (autoDispose), `thumbnail_repository.dart`
(LRU + byte cap + in-flight sharing), `file_hash_repository.dart`,
`perceptual_hash_repository.dart`, `photo_quality_repository.dart` (chunking +
bounded caches), `file_thumbnail.dart` and `app_icon.dart` (decode sizing),
`main.dart` (image cache tuning).

No native changes this phase.

## Tests (14 cases)

Batch arithmetic for 900/1500/1300/700 files was computed independently before
being asserted. Covers: full delivery past the cap; no batch exceeding the cap;
chunking in all three repositories; partial results surviving a mid-way failure;
cached results costing no platform work; only uncached files re-requested;
thumbnail entry cap; **byte cap evicting before the entry cap**; repeat requests
served from cache; simultaneous requests sharing one decode; non-thumbnailable
files costing no call; failures cached rather than retried forever.

## Verification status

**Static review only** here, and this is the phase where that limitation bites
hardest: I can prove the batching and cache bounds with tests, but I **cannot
measure** frame times, scroll smoothness, or real memory use without a device.

The brief said "test with large libraries" — I have tested the logic against
simulated large libraries, not the app against a real one. What I would do on
your Android 14 device:

1. Open Photos and Files on a phone with a few thousand images and watch for
   dropped frames while scrolling fast.
2. Run `flutter run --profile` and check the memory graph while scrolling a long
   list, then scrolling back — it should plateau, not climb.
3. Check that Duplicates now finds more than it used to on a large library.
   That is the user-visible symptom of the truncation bug being fixed.
