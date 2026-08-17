# Phase 24 — Smart Recommendations

Make Home intelligent. Fixed rules over real scan findings. **No generative AI.**

## The three rules, exactly as specified

| Rule | Fires when | Recommends |
|---|---|---|
| Screenshots | `count(older than 90 days) > 20` | Screenshot review |
| Duplicates | `reclaimable > 500 MB` | Duplicate cleanup |
| Large video | `any single video >= 1 GB` | Large video review |

Thresholds live in `RecommendationEngine` as named constants, and a test
asserts each one matches the spec — so a future edit that quietly changes a
number fails the suite.

`> 20` is implemented as strictly greater than: **exactly 20 does not fire**,
21 does. Same for 500 MB. Both boundaries are tested, because "greater than"
and "at least" are one character apart and produce different products.

## Why rules, not a model

This is the right answer for V1, not a stopgap:

- **The advice is checkable.** Each card states the evidence it fired on —
  *"34 screenshots older than 90 days · 210 MB"* — so the user can verify the
  claim instead of trusting it.
- **Identical on every device**, and fully testable without one.
- A model would be slower, unpredictable, and impossible to justify to someone
  deciding whether to delete their photos.

## Advice only — it never acts

The engine returns text and a destination. It does not select, delete, or
change state. Tapping a recommendation just opens the tool that owns it, where
the normal Phase 12 review-and-confirm flow applies:

| Recommendation | Opens |
|---|---|
| Screenshot review | `/screenshot-cleaner` |
| Duplicate cleanup | `/duplicates` |
| Large video review | `/videos` |

A widget test taps a card and asserts the only observable effect is the
callback reporting which kind was tapped.

## Duplicates are measured on *reclaimable* space

Not total occupied. One copy of every set is always kept, so the space all
copies occupy is not what the user gets back. The card says so explicitly:
*"one copy of each is always kept"*. Promising the larger number and
delivering the smaller one is exactly the dishonesty this codebase has avoided
since Phase 18.

## An empty result is a real answer

If nothing crosses a threshold, Home says *"Nothing needs attention right now.
Your storage looks tidy."* It does not invent filler advice to look busy.

Loading and error also fall back to the plain card rather than a spinner or an
error state — **Home must stay usable while background scans run**. All four
states keep the `recommendations_section` key, so the existing Phase 2 widget
tests still pass unchanged.

## Ordering

High priority first (anything recovering >= 1 GB), then biggest saving, then a
stable tiebreak on rule identity so the order never shuffles between rebuilds.
A test evaluates the same inputs twice and asserts identical ordering.

The returned list is unmodifiable; a test asserts `clear()` throws.

## Composed, not re-scanned

`recommendationInputsProvider` watches three existing providers —
`screenshotSummaryProvider(days90)`, `duplicatesProvider`, and
`videoSummaryProvider(largest)` — started together and awaited afterwards, so
the wait is the slowest scan rather than the sum. Same pattern as
`smartScanProvider` and `photoCleanupProvider`.

Consequence: a recommendation always matches what the tool shows when opened,
and opening it reuses the cached scan. The `days90` bucket is requested
directly rather than filtering a wider scan afterwards, because that is
precisely what the rule asks about.

## Files

**New:** `recommendation.dart` (kinds, priority, inputs),
`recommendation_engine.dart` (the rules), `recommendations_provider.dart`,
`test/recommendations_test.dart` (22 cases).

**Changed:** `recommendations_card.dart` — was a static placeholder, now
renders real advice; `home_screen.dart` — routes each kind, and pull-to-refresh
now also refreshes recommendations.

No new route, no new channel, no new scan, **no new delete path.**

## Tests (22 cases)

Every threshold boundary on both sides; singular/plural wording; the exact
detail strings; a single oversized video firing on its own; other large videos
mentioned only when present; all three rules firing together in the right
order; stable ordering; unmodifiable result; thresholds matching spec; and
widget tests driving the card from a real stubbed scan — 25 stale screenshots
producing `25 screenshots older than 90 days · 100.0 MB`, a 3 GB video
producing `wedding.mp4 is 3.0 GB`, the tidy state, and an empty device.

All byte formatting in the assertions was recomputed independently before
being written.

## Verification status

**Static review only** in this workspace — no toolchain here. Checked by hand:
brace balance, truncation, symbol resolution, import ordering, unused imports,
80-column limit, and every formatted byte value.

I also specifically swept the new code for the Riverpod 3 breakage that just
failed your build: no `valueOrNull`, no `StateProvider`, no `requireValue`. The
`.when(loading/error/data)` shape used here is the same one already compiling
elsewhere in the app.

You now have a real compiler, so please run `flutter analyze` before building —
it will surface every error at once instead of stopping at the first file, which
is much faster than round-tripping build failures.
