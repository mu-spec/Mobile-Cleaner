# Phase 12 fix — Delete action not visible after selection

## Reported problem

On a real Android device, files, photos, and screenshots could be selected,
but no Delete action appeared afterwards, so the Phase 12 safe-delete flow was
unreachable from the UI.

## Diagnosis

The wiring was present — each cleaner already passed `_deleteSelected` into a
selection bar that called `runDeleteFlow`. The failure was in **presentation**,
and there were three separate defects, each capable of hiding the action:

1. **The bar could overflow and push Delete off-screen.** Each cleaner had its
   own copy of a `_SelectionBar` built as a fixed `Row`: an `Expanded` text
   column, then Clear, then Delete. On a 320 dp device, or at Android's larger
   accessibility font scales, the row needed more width than the screen. A
   `RenderFlex` overflow clips the trailing children — which is exactly where
   the Delete button sits.

2. **The bar could sit behind the list.** The lists used a fixed 28 dp bottom
   padding, so with the bar showing, the final row and part of the bar area
   overlapped. On a short screen with few results this made the action easy to
   miss entirely.

3. **Three separate copies could drift.** The same bar was duplicated across
   Downloads, APK, and Screenshot cleaners, so a fix in one would not reach the
   others.

## Fix

### One shared action bar

New `SelectionActionBar` replaces all three private copies. It is laid out so
the Delete action cannot be squeezed out:

- the count and size column is `Flexible` and ellipsises, rather than forcing
  the row wider than the screen,
- the Delete button keeps its intrinsic width, so it is never the thing that
  gets clipped,
- `SafeArea(top: false)` keeps it clear of the gesture-navigation inset,
- `elevation: 8` lifts it visually above the list.

Delete is now styled with the theme's error colour, so it reads as the primary
destructive action rather than a neutral button.

Each screen passes its own widget keys, so every existing test and any external
tooling keeps working unchanged.

### Lists reserve room for the bar

Bottom padding grows from 28 dp to 104 dp while a selection is active, so the
last row stays reachable and the bar never covers content.

## What did not change

- The delete path itself: **Review → Confirm → Android system approval →
  Cleanup Complete** is untouched.
- `DeleteBridge` still uses `MediaStore.createDeleteRequest` on Android 11+ and
  `RecoverableSecurityException` on Android 10, so scoped-storage and the
  system confirmation dialog are **not** bypassed.
- No new cleaner features, no changes to filters, sorting, scanning, or any
  unrelated screen.
- Large Files was left alone: it has no selection mode, so it was outside the
  reported problem.

## Automated tests

`test/selection_action_bar_test.dart` runs the same six checks against all
three cleaners:

- no action bar before anything is selected,
- selecting one item reveals a **visible, enabled** Delete — asserted by
  measuring the button's rect against the screen bounds, which is what the
  previous tests missed,
- the selected count and size are correct, and update on Select All,
- Delete opens the **Review** step and does not delete immediately,
- Review → Confirm reaches **Cleanup Complete** with the right recovered size,
- the action survives a **320 dp** screen and a **1.5× font scale** — the two
  conditions that produced the original overflow.

The size and rect assertions are the regression guard: the old suite only
checked the button existed in the widget tree, which it always did, even while
being clipped off-screen.

## Device verification

1. Open Downloads Cleaner, select one item, and confirm a Delete button appears
   at the bottom with the count and size.
2. Repeat in APK Cleaner and Screenshot Cleaner.
3. Set Settings → Display → Font size to its largest and repeat — Delete must
   still be fully visible.
4. Tap Delete, confirm the review sheet, approve the Android dialog, and check
   the Cleanup Complete screen reports the freed space.
5. Decline the Android dialog and confirm nothing is deleted.
