# Phase 22 — Video Analyzer

A dedicated Videos section showing thumbnail, name, duration, size, and date,
sortable by Largest, Longest, Newest, and Oldest.

## Duration had to be plumbed from scratch

Nothing in the app knew how long a video was. `MediaStore` exposes
`Video.Media.DURATION`, but the scanner never requested it, so Phase 22 starts
in Kotlin.

`FileScannerBridge.runQuery` gained an `includeDuration` flag, set only for the
video collection — `DURATION` is not guaranteed on every collection at every
API level, so it is requested per-query rather than always.

### The key naming collision

The scan payload **already** used `durationMillis`, for how long the scan took:

```kotlin
"durationMillis" to (System.currentTimeMillis() - startedAt)
```

Reusing that key for playback length would have silently collided with
`FileScanResult.durationMillis`. The per-file key is therefore
**`videoDurationMillis`**. This is the kind of thing static review usually
misses; it was caught by grepping the existing payload before adding the field.

### Unknown length is null, never zero

MediaStore leaves `DURATION` null often enough to matter. Zero is filtered out
natively (`takeIf { it > 0L }`) and again in Dart (`_readPositiveInt`), because:

- `0:00` claims a video is empty rather than admitting the length is unknown
- a zero-length video would sort as the *shortest* under Longest, burying real
  videos beneath unreadable ones

The UI shows `--:--`, unknown-length videos sort **last**, and the headline
discloses how many are missing so the total footage is not quietly understated.

## Files

### New

| File | Role |
|---|---|
| `lib/core/utils/duration_formatter.dart` | `0:42`, `4:07`, `1:12:05`; `formatLong` for totals |
| `lib/features/files/domain/video_sort.dart` | The four orderings and their comparators |
| `lib/features/files/domain/video_summary.dart` | Video filtering, totals, footage |
| `lib/features/files/presentation/providers/videos_provider.dart` | `videoScanProvider`, `videoSummaryProvider` |
| `lib/features/files/presentation/widgets/video_tile.dart` | The row |
| `lib/features/files/presentation/screens/videos_screen.dart` | `VideosScreen` |
| `test/videos_test.dart` | 26 cases |

### Changed

- `FileScannerBridge.kt` — `includeDuration`, `videoDurationMillis`
- `scanned_file.dart` — `durationMillis`, `duration`, `isVideo`, `copyWith`,
  `_readPositiveInt`
- `scanned_file_tile.dart` — the details sheet shows `Length` for videos
- `files_screen.dart` — a **Videos** shortcut card above the category grid
- `app_router.dart` — `/videos`. 17 routes, 17 builders

## A dedicated tile, not `ScannedFileTile`

A video row carries one more fact than a file row, and length belongs *on the
thumbnail* — bottom-right, dark chip — where anyone who has used a video app
expects it. Cramming it into the subtitle would have made the row read as three
interchangeable stats. Size stays bold, date ellipsises.

## Sorting

| Sort | Rule |
|---|---|
| Largest | Size descending |
| Longest | Playback descending; **unknown length last** |
| Newest | Date descending |
| Oldest | Date ascending |

Every comparator falls back to the file name, so equal sizes or identical
timestamps produce a stable order rather than one that shuffles between
rebuilds. A test sorts the same list in two input orders and asserts identical
output.

Sorting happens in `videoSummaryProvider`, a re-sort of one cached scan — a
test taps two chips and asserts the scanner was still called exactly once.
**Selection is preserved across a re-sort**, deliberately: unlike a filter
change, nothing left the list, so discarding the selection would be
destructive of the user's work.

## Video detection

MIME type is trusted over the category bucket, so a clip saved into Downloads
is still a video. A test asserts a 900 MB *photo* is excluded even though it is
the largest file in the fixture.

De-duplicated by URI, so a clip reported under two categories is counted once.

## What was deliberately not changed

The **Videos category card in the Files grid still opens the generic category
list.** Rerouting it to the new section would have changed behaviour this phase
did not ask about, and two existing tests
(`file_categories_test.dart`) tap that card and assert
`category_list_videos`. The dedicated section has its own shortcut card
instead.

Deletion is unchanged: the shared Phase 12
`Select → Review → Confirm → Delete → Result` flow, via `runDeleteFlow`.

## Layout hazards avoided

- `SelectionActionBar` in the body `Column` below the `Expanded` list, never in
  `Scaffold.bottomNavigationBar`
- `ListView.builder` — a plain `ListView` would decode every thumbnail up front
- Four sort chips in a horizontally scrollable bar
- The date is `Flexible` with `ellipsis`, so a long relative date cannot
  overflow a narrow row

## Tests (26 cases)

Fixture: a big-but-short recent drone clip, a small-but-longest old lecture, a
middling birthday video, a clip with **no length**, and a 900 MB photo that
must never appear. All four sorts produce four different orderings from it, and
`newest` is asserted to be the exact reverse of `oldest`.

Covers: duration formatting including the hour boundary and the unknown
placeholder; `formatLong` never rounding a real clip to "0 min"; zero/null/
negative durations all reading as unknown; MIME-based video detection;
each sort; tie-breaking stability; photo exclusion; URI de-duplication;
footage totals excluding unknowns and disclosing the count; largest ≠ longest;
per-row thumbnail/name/duration/size/date; `--:--` rendering; re-sort without
rescanning; selection surviving a re-sort; select-all; empty state.

Totals verified independently: 1270 MB → `1.2 GB`, 90s + 3h + 12min →
`3 hr 13 min`.

## Verification status

**Static review only.** `flutter analyze`, `flutter test`, and the Kotlin
compiler have not been run — no toolchain in this workspace. Checked by hand:
brace balance, truncation, symbol resolution, import ordering, unused imports,
80-column Dart / 100-column Kotlin, and the fixture arithmetic.

Highest-risk items on device:

1. The `FileScannerBridge.kt` change touches the **shared** query path used by
   every category. `includeDuration` defaults to false so non-video queries are
   byte-for-byte unchanged, but this is the one file where a mistake would
   break scanning app-wide — check the other categories still list correctly.
2. How often `DURATION` is actually null on your device. If it is common, the
   footage total will look low and the `videos_unknown_note` will be permanent;
   the fallback would be `MediaMetadataRetriever`, which is far more expensive.
3. Whether 500 videos is a sensible per-scan cap.
