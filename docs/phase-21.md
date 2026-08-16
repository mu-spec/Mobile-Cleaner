# Phase 21 — Best Photo Recommendation

Analyse similar-photo groups on sharpness, resolution, blur, and dimensions.
Mark one as **Suggested Keep**. Never auto-delete the others.

## Never auto-delete — how that is guaranteed structurally

The recommendation is a **label and an ordering**. Nothing more:

- it does not touch `FileSelection` — nothing is ever pre-selected
- it does not touch `DuplicateKeepSelection` — the protected photo is still
  whichever the user chose (default: the first shot)
- it cannot start `runDeleteFlow`
- a suggested shot **can still be selected and deleted** by the user, and a
  test does exactly that

So `Suggested Keep` and the actual keeper are independent, and can differ. That
is intentional: advice that silently rearranged what is protected would be an
action wearing the costume of a hint.

## Measurement (native, on-device)

New 8th channel, `PhotoQualityBridge.kt`, returns per photo:

| Field | How |
|---|---|
| `width`, `height` | Bounds-only decode — full resolution known without decoding a pixel of image data |
| `pixels` | `width * height` as a **long**, so Dart never widens a platform int |
| `sharpness` | Variance of the Laplacian over a greyscale downsample |

Laplacian variance is the standard cheap focus measure: a sharp photo has hard
intensity transitions at edges, so the second derivative varies a lot; a soft
or out-of-focus photo has gentle transitions and low variance. No model, no
library, no network.

Two decisions worth naming:

1. **Sharpness is measured at a fixed 256px working size**, not at native
   resolution. Laplacian variance rises with pixel count, so measuring at
   native size would count resolution twice and declare the bigger file sharper
   regardless of focus. Resolution is scored separately, in Dart.
2. **Border pixels are skipped, not clamped.** A clamped border fabricates
   edges that do not exist and inflates the score of a photo with a plain
   background.

## Scoring (Dart, pure, testable)

`BestPhotoScorer` — every figure is a ratio against the best photo **in the
same group**.

```
score = 0.65 x (sharpness / group best) + 0.35 x (pixels / group best)
```

Sharpness dominates because it is what a person actually notices: between two
shots of one scene, the sharp one is the keeper even if slightly smaller.

### Blur is relative, never absolute

There is no Laplacian variance that means "blurred" across a library — a
landscape and a plain wall differ by an order of magnitude at identical focus.
A photo is flagged **"Softer than the best shot"** only below 55% of its own
group's sharpest. A similar-photo group is photos of the *same scene*, which is
the only case where that comparison is fair. A test asserts the same absolute
sharpness is flagged in one group and not in another.

### It refuses to guess

If the leader beats the runner-up by less than **0.08**, no suggestion is made
and the card says *"These shots are too close to call. Your choice."* A
confident recommendation based on a rounding error would nudge someone into
deleting a shot that was just as good. Identical shots correctly produce no
suggestion.

### The reason is truthful

The label names the factor that actually decided it — `Sharpest shot`,
`Highest resolution`, or `Best overall` — rather than always saying the same
thing. All four cases were verified with independent arithmetic before the
assertions were written.

Ties break on URI, so the ordering is stable and a rebuild cannot silently
change the advice.

### Unmeasured means unranked

A photo with no measurement is **omitted** from the ranking, not scored as
zero — which would falsely brand it blurred. Fewer than two measured photos is
not a comparison, so no opinion is offered.

## UI

Inside each similar group:

- one cell gets a tertiary-coloured border and a **`Suggested Keep`** badge
- a one-line reason under the group caption, ending *"Nothing is selected for
  you."*
- soft shots get *"Softer than the best shot"*
- once measured, the date line becomes the resolution, e.g. `4000 x 3000`
- **kept and selected outrank the suggestion visually**, because those are
  states the user set and advice must not overwrite them

Recommendations load via `.valueOrNull`, so groups render immediately and
badges appear when measuring finishes. A slow analysis never blocks review, and
a library that cannot be measured at all simply shows no advice.

Only **grouped** photos are measured — a lone photo has nothing to compare
against, so analysing it would be wasted decoding. A test asserts exactly three
URIs are sent for a three-photo group.

## Files

**New:** `PhotoQualityBridge.kt`, `photo_quality.dart`,
`best_photo_scorer.dart`, `photo_quality_repository.dart`,
`best_photo_provider.dart`, `test/best_photo_test.dart` (24 cases).

**Changed:** `MainActivity.kt` (registers/disposes the 8th channel),
`similar_photos_screen.dart` (badge, reason note, soft flag, resolution line),
`test/similar_photos_test.dart` (new provider override).

**Method channels — now 8:** `storage`, `file_scanner`, `thumbnails`, `saf`,
`delete`, `hash`, `perceptual_hash`, **`photo_quality`**.

Nothing else changed. The dashboard, the duplicate tool, and the delete flow
are untouched.

## Verification status

**Static review only.** `flutter analyze`, `flutter test`, and the Kotlin
compiler have not been run — no toolchain in this workspace. Checked by hand:
brace balance, truncation, symbol resolution, import ordering, unused imports,
80-column Dart / 100-column Kotlin, and every score in the fixture recomputed
independently.

`PhotoQualityBridge.kt` is **new native code that has never been compiled** —
check that first. Then, on device:

1. Whether the 0.08 minimum lead is right. Too low and it recommends noise; too
   high and it stays silent when the answer is obvious. This is the number most
   likely to need tuning against a real camera roll.
2. Whether 0.55 is the right blur threshold.
3. Decode cost. Measuring is the heaviest thing in the app so far — roughly one
   downsampled decode per grouped photo, on top of the Phase 20 perceptual
   hash decode of the same images. If Similar Photos feels slow, the two
   bridges should be merged into one pass that decodes each image once.
