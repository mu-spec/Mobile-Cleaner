# Selection-mode freeze — diagnosis and fix

## Reported behaviour

On a real device, in Screenshot Cleaner:

- tapping a screenshot selects it,
- the header changes to "1 selected",
- **after that the screen stops responding** — the list will not scroll, no
  further items can be selected, and Clear/Delete are unusable.

## What was ruled out

Working through the suspects in order:

**1. What happens after `_selection` changes.** Every mutation is a plain
`setState` assigning a new immutable `FileSelection`. No async work, no
navigation, no provider invalidation on the selection path. Nothing there
blocks.

**2. Touch interceptors.** Searched the screen, the action bar, the tile and
the thumbnail for `AbsorbPointer`, `IgnorePointer`, `ModalBarrier`,
`Positioned`, `Stack`, `GestureDetector`, `Overlay`, and barrier dialogs. The
only `Stack` is inside `FileThumbnail`, sized 44 dp — it cannot cover the
screen. **No interceptor exists.**

**3. Rebuild loop.** `build` watches `screenshotSummaryProvider(_group)`, which
depends on `screenshotScanProvider`. Neither is invalidated by selection, and
`ScannedFile` has correct `==`/`hashCode`, so the `family` provider is not
re-keyed on rebuild. **No endless loop.**

**4. Debug logging.** Not needed — the cause was visible statically once the
list widget was read.

## Root cause

`_ScreenshotList` used a **non-lazy** `ListView(children: ...)`. That
constructor builds **every child up front**, and the screenshot scan allows
**1000 files**.

So a single tap on a checkbox meant:

- ~1000 `ScannedFileTile`s rebuilt (`ListTile` + `Checkbox` + three `Text`s),
- ~1000 `FileThumbnail`s rebuilt, each a `ConsumerWidget` re-establishing a
  watch on `thumbnailProvider`,
- for images, thumbnail decode requests crossing the platform channel.

Roughly six thousand widget builds plus a thousand provider subscriptions, on
the UI thread, for one tap. That is seconds of jank on a mid-range phone, and
it presents exactly as reported: **the tap registers and the header updates**
— because `setState` completes — **and then the app appears frozen** while the
rebuild runs. It is not a true deadlock; the UI is simply never idle long
enough to handle the next gesture.

This also explains why it survived earlier fixes: the previous rounds moved the
action bar around, but the cost was in the list, not the bar. And it explains
why the widget tests passed — they use small fixtures, where building every row
is cheap.

## Fix

`_ScreenshotList` now uses `ListView.builder`, so only visible rows are built.
The two header widgets (total card, sort row) become indices 0 and 1, with
files offset by `headerCount`.

A rebuild now costs a handful of rows regardless of library size, so selecting
is O(visible) rather than O(library).

Once verified, the identical change was applied to `_DownloadsList` and
`_ApkList`, which had the same structure with a 500-file cap.

The remaining plain `ListView`s are the filter chip bars and empty states —
fixed, tiny, and correct as they are.

## What was not changed

- The Phase 12 deletion backend: `DeleteBridge`, `delete_repository`,
  `delete_result`, and `runDeleteFlow` are untouched.
- `SelectionActionBar` and its placement in the body `Column`.
- No UI redesign, no new features, no native or dependency changes.

## Regression tests

`test/selection_performance_test.dart` builds a **600-screenshot** library and
asserts:

- fewer than 50 rows are built — the old eager list would build all 600,
- fewer than 50 thumbnail requests are made,
- selecting an item does not fan out thumbnail requests library-wide,
- the list still scrolls after selecting,
- a second item can still be selected.

The existing suites used fixtures of two or three files, which is why they
never caught this. These tests fail loudly against the eager list.

## Device verification

1. Open Screenshot Cleaner on a device with a large screenshot library.
2. Tap one item. The header should update **and the UI should stay
   responsive**.
3. Scroll the list, select several more, use Select all, then Clear.
4. Confirm the same in Downloads Cleaner and APK Cleaner.
5. Delete a selection and confirm the Android dialog and Cleanup Complete
   screen behave as before.
