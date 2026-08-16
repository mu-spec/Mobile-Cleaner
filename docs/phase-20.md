# Phase 20 — Similar Photo Detection

On-device photo similarity. Group visually similar photos, such as several
nearly identical shots.

Built only now that exact duplicates are stable — Phases 17 and 18 shipped, and
this reuses their group/keep machinery rather than replacing it.

```
images only  ->  perceptual hash  ->  compare hashes  ->  similar group
```

## Everything runs on the device

Two 64-bit hashes are computed from a downsampled decode of each image, and
compared with integer bit arithmetic. No image, thumbnail, hash, or metadata
leaves the phone; no network permission is used and no model is downloaded.
The loading view says so explicitly.

## The two hashes, and why both

| Hash | What it encodes | Weakness |
|---|---|---|
| **dHash** (gradient) | Each pixel vs. its right-hand neighbour on a 9x8 grid | Groups any two flat images — sky, snow, a white wall — because they share a near-empty gradient signature |
| **aHash** (average) | Each pixel of an 8x8 grid vs. the frame mean | Fooled by exposure and brightness changes between shots |

**Both must agree** before two photos are grouped. That is the single most
important decision in this phase: each hash alone produces false positives that
the other rejects, and a false positive here means offering to delete a photo
the user wanted. Rec. 601 luma weighting is used so two shots differing only in
colour temperature still hash alike.

Returned as 32 lowercase hex characters, dHash then aHash.

## Leader comparison, not transitive chaining

The obvious approach — union any two photos within the threshold — chains: A is
near B, B is near C, C is near D, and the group ends up holding two photos that
look nothing alike. Every photo here is instead compared against its group's
**leader**, so every member is provably within the threshold of one common
reference, and the closest leader wins when two are eligible.

A regression test locks this: A–C is 8 bits, C–CHAIN is 8 bits, A–CHAIN is 16.
Transitive grouping would merge all three; the detector correctly keeps CHAIN
out.

## Similarity strength

| | dHash bound | aHash bound |
|---|---|---|
| Strict | 4 | 6 |
| **Balanced** (default) | 8 | 10 |
| Relaxed | 12 | 14 |

aHash bounds are looser because it is the weaker signal — it is there to veto
obvious mismatches, not to make the primary decision.

Strength is applied at **grouping** time, not hashing time
(`photoFingerprintProvider` is separate from `similarPhotosProvider`), so
switching chips re-groups in memory. A test asserts the hash repository is
called exactly once across a strength change: decoding is the expensive step
and must never repeat.

## Deliberately more cautious than the duplicate tool

Exact duplicates are interchangeable, so selecting every extra copy is safe.
Similar photos are **not** — one may be the sharp one, or the one where nobody
blinked. So on this screen:

- **nothing is ever pre-selected**
- **there is no global select-all.** Only per-set selection. "Delete all
  similar photos" is precisely the operation a user regrets, so the affordance
  does not exist. A test asserts `similar_photos_select_all` is absent.
- the total reads **"up to 7.0 MB"**, and the card states the match was by
  appearance, not byte for byte
- each cell shows its **file size**, unlike the duplicate tool, because similar
  shots genuinely differ in size and that is a real reason to prefer one
- `reclaimableBytes` assumes the **largest** shot is kept — the conservative
  estimate, since the largest is usually the best quality

One photo of every set is always kept, exactly as in Phase 18.

## Shared keep-selection

`DuplicateKeepSelection` now operates on a new `PhotoCopyGroup` interface
(`groupKey`, `files`, `original`) implemented by both `DuplicateGroup` and
`SimilarPhotoGroup`. The "one copy is always kept" rule therefore has **one**
implementation, not one per feature.

`reclaimableBytes` was changed from `fileBytes x count` to a per-file sum —
correct for duplicates (all the same size) and necessary for similar photos
(all different sizes).

## Files

### New

| File | Role |
|---|---|
| `android/.../PerceptualHashBridge.kt` | dHash + aHash over a downsampled decode; 7th method channel |
| `lib/features/files/domain/perceptual_hash.dart` | Parse, Hamming distance |
| `lib/features/files/domain/photo_copy_group.dart` | `PhotoCopyGroup` interface |
| `lib/features/files/domain/similar_photo_group.dart` | Group, scan result, `SimilarityStrength` |
| `lib/features/files/domain/similar_photo_detector.dart` | Candidates + leader grouping |
| `lib/features/files/data/perceptual_hash_repository.dart` | Channel wrapper, session cache |
| `lib/features/files/presentation/providers/similar_photos_provider.dart` | Scan, fingerprints, grouping |
| `lib/features/files/presentation/screens/similar_photos_screen.dart` | `SimilarPhotosScreen` |
| `test/similar_photos_test.dart` | 24 cases |

### Changed

- `MainActivity.kt` — registers and disposes the 7th channel
- `duplicate_group.dart` — now `implements PhotoCopyGroup`
- `duplicate_keep_selection.dart` — generalised to `PhotoCopyGroup`
- `photo_cleanup_summary.dart` — Similar Photos carries a real figure;
  `isAvailable` is now always true; new `isEstimate`
- `photo_cleanup_provider.dart` — fourth scan composed in
- `photos_screen.dart` — the row routes to the screen; the "coming next"
  SnackBar is gone; estimates render as `up to X`
- `app_router.dart` — `/similar-photos`. 16 routes, 16 builders
- `test/photo_cleanup_dashboard_test.dart`, `test/widget_test.dart` — new
  provider override; the `Analyze` and "coming next" assertions were replaced

### Method channels — now 7

`storage`, `file_scanner`, `thumbnails`, `saf`, `delete`, `hash`,
**`perceptual_hash`**.

## Similar photos do not inflate the dashboard headline

The dashboard row shows `up to X`, but the entry contributes **no files** to
`PhotoCleanupSummary.uniqueFiles`. Counting them as recoverable would promise
space the user may well decide not to free, after looking at the shots. A test
asserts the headline is identical with and without similar photos present.

## Native safety

- Bounds-only decode pass, then `inSampleSize` — a 50 MP photo is never fully
  decoded; only enough pixels to fill a 32-pixel grid
- 600-image cap per call
- Every failure, including `OutOfMemoryError`, omits that image rather than
  failing the batch
- Two-thread pool, `RejectedExecutionException` answered rather than crashing
- Bitmaps recycled

## Tests (24 cases)

Fixture: a three-shot burst at known Hamming distances (4 and 8 from the
leader), an unrelated scene at 40 bits, a **flat wall** whose gradient is 2 bits
away but whose average hash is 20 bits away, a video, and a sub-floor icon. All
distances were verified with independent arithmetic before being asserted.

Highlights: hex parsing including a top-bit-set hash; malformed input rejected;
**both hashes must agree** (the flat wall is vetoed at every strength); videos
and tiny files never analysed; a photo reported twice is not its own twin;
**no transitive chaining**; strength changes grouping; unreadable photos dropped;
a lone photo is never a group of one; reclaimable assumes the largest is kept;
burst detection by timespan; the shared keep-selection always retains one shot
for every possible choice; nothing pre-selected; no global select-all;
strength change does not re-decode.

## Verification status

**Static review only.** `flutter analyze`, `flutter test`, and the Kotlin
compiler have **not** been run — no toolchain exists in this workspace. Checked
by hand: brace balance, truncation, symbol resolution, import ordering, unused
imports, 80-column Dart / 100-column Kotlin, and every Hamming distance in the
fixture.

`PerceptualHashBridge.kt` is **new native code that has never been compiled**,
which is a larger risk than the Dart. Specific things to check first on device:

1. It compiles at all, and the channel is reachable.
2. Real-world grouping quality. The thresholds (8/10 balanced) are reasoned
   defaults, not tuned against a real camera roll — they may need adjusting
   after you see what it groups.
3. Time to hash a few hundred photos on a real device. If the Photos tab feels
   slow to open, the fix is to stop composing similar photos into
   `photoCleanupProvider` and compute that row lazily.
