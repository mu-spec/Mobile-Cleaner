# Phase 29 — UI Polish

Transitions, empty states, haptics, loading states, success animations,
responsive layout, accessibility.

Done deliberately conservatively: there are **531 tests across 29 files**, and
polish that breaks working functionality is not polish. Every change was checked
against the existing suite before committing.

## The change I made and then reverted

I first set an explicit `pageTransitionsTheme` with
`FadeForwardsPageTransitionsBuilder` for a consistent transition across Android
versions. Then I checked the Flutter docs and reverted it.

Modern Flutter defaults Android to `PredictiveBackPageTransitionsBuilder`, which
gives the system back-gesture preview and *already* falls back to fade-forwards
for ordinary pushes. **Naming a builder explicitly would have disabled
predictive back** — a downgrade dressed up as polish. The theme now carries a
comment explaining why the default is left alone.

## Accessibility

The audit found one `Semantics` widget in the whole app.

- **Checkboxes were unlabelled.** In a list of 500 files a screen reader
  announced an anonymous control. They now carry `semanticLabel: file.name`.
- **Photo-strip cells are image-only controls** — completely opaque to a screen
  reader. Each is now wrapped in `Semantics(label:, selected:, button:)`, so it
  announces the file, whether it is kept, and whether it is marked for removal.
- **Empty-state icons are decorative** and now `ExcludeSemantics`, so the words
  are read instead of "image". Titles are marked `header: true`.
- **Icon buttons were already fine** — all 26 have tooltips, which supply
  semantics automatically. No change needed.

## Text scaling: the quiet failure

Nine chip bars were a fixed `height: 52`. At Android's larger font settings the
labels clip — an accessibility bug that never appears at the default scale a
developer tests at.

`Responsive` now scales those heights by `MediaQuery.textScalerOf`, **clamped**
so an extreme scale cannot consume the screen (52→92 max). The two photo strips
get the same treatment, since their multi-line captions are the most
scale-sensitive layout in the app.

## The success animation had to be finite

This was the single largest regression risk. There are **234 `pumpAndSettle`
calls** in the suite; a looping animation never lets the tree settle and would
have hung every test reaching the cleanup screen.

`SuccessCheck` plays **once** over 450ms and holds its final frame. It also
honours `MediaQuery.disableAnimationsOf` — a user who turned animations off in
Android accessibility settings jumps straight to the final frame. Three tests
lock this: that it settles, that it respects the setting, and that it genuinely
animates when it should.

## Haptics, used sparingly

A phone that buzzes on every tap is worse than one that never does. Three
moments only:

| Moment | Feedback |
|---|---|
| Selecting a file | `selectionClick` — lightest, happens often |
| Confirming a delete | `mediumImpact` — irreversible, deserves weight |
| Cleanup completed | `mediumImpact` |

Every call is fire-and-forget and swallows errors, so a device with no vibrator
never turns a working action into a failure. Tested.

## Files

**New:** `core/ui/haptics.dart`, `core/ui/success_check.dart`,
`core/ui/empty_state.dart`, `core/ui/responsive.dart`,
`test/ui_polish_test.dart` (13 cases).

**Changed:** `app_theme.dart` (comment only), `delete_flow.dart`,
`scanned_file_tile.dart`, `video_tile.dart`, `cleanup_complete_screen.dart`,
and nine screens for scaled chip bars.

## What I did not change, and why

- **Loading states already exist** — `FilesScanningView` plus purpose-written
  ones for hashing, comparing, and analysing, each explaining what is happening.
  Replacing them would lose that wording.
- **Twelve empty states already exist** and are well-written. `EmptyState` is
  available as the shared shape for new screens, but retrofitting all twelve
  would touch twelve working screens and their tests for cosmetic gain. That is
  the wrong trade this late.
- **No native changes**, no provider changes, no logic changes.

## Verification status

**Static review only.** Checked by hand across every touched file: brace balance
with string interpolation stripped, truncation, import ordering and duplicates,
every import target resolving, every added import actually used, 80-column
limit, and Riverpod 3 traps.

I also verified structurally — not just by brace count — that the new
`Semantics` wrappers close in the right place, since an off-by-one there would
nest the caption inside the button.

Test-regression checks specifically: keys used by `safe_delete_test.dart` and
`selection_action_bar_test.dart` are preserved; no existing test asserts on
`Semantics` or tooltips; unmocked haptic channel calls are no-ops under test.

On device, the two things worth checking are **Settings → Display → Font size at
maximum** on the chip bars, and TalkBack on a file list.
