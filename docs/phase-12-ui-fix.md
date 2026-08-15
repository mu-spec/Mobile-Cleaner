# Phase 12 fix — selection action bar visibility and reuse

## Reported problem

Selection worked on real Android devices, but the Clear/Delete bottom action
bar was not visible, so the Phase 12 safe-delete flow was unreachable.

## Root cause

The earlier fix addressed a horizontal overflow, which was real but was not
what users were hitting. The actual cause is a **bottom inset conflict**:

Every cleaner wraps its `body` in a `SafeArea`. That widget **consumes** the
bottom system inset, and `MediaQuery.padding` is then reported as zero to
everything below it. The action bar is a sibling `bottomNavigationBar`, and it
used its own `SafeArea(top: false)` to clear the gesture pill — but by then the
inset had already been consumed, so it padded by **zero** and rendered
underneath the Android navigation bar.

The bar was in the widget tree the whole time, which is why it passed every
existing test: the widget existed, it was simply drawn beneath the system UI.

## Fix

`SelectionActionBar` now reads **`MediaQuery.viewPaddingOf(context).bottom`**
instead of nesting a `SafeArea`. `viewPadding` reports the true physical system
inset regardless of what an ancestor already consumed, so the bar clears the
navigation bar in every configuration — gesture pill, three-button bar, or
none.

## Reuse across selectable screens

`SelectionActionBar` and `runDeleteFlow` are now used by:

| Screen | Covers |
| --- | --- |
| Screenshot Cleaner | screenshots |
| Downloads Cleaner | old downloads |
| APK Cleaner | installers |
| `CategoryFilesScreen` | **Images, Videos, Audio, Documents, Downloads browser, APK browser** |

`CategoryFilesScreen` is one screen parameterised by category, so adding
selection there covered six of the listed targets at once. It gained the same
behaviour as the cleaners: tap to toggle, Select all / Clear all, an app bar
that switches to "N selected" with a cancel action, and long-press for details.
Search and sort actions hide while selecting, since the selection actions take
over the bar.

Large Photos, Duplicate Photos, and Similar Photos do not exist yet. When they
are built they get the identical bar and flow by passing a `FileSelection` —
no new deletion code.

**There is still exactly one deletion system.** Every screen routes through
`runDeleteFlow`, which is the only caller of `deleteRepositoryProvider`.

## Only offering Delete for what Android permits

`ScannedFile.isDeletable` is true only for `content://` URIs. Deletion goes
through MediaStore or SAF, and both require a content URI; a `file://` row
comes from the legacy pre-scoped-storage directory walk and
`ContentResolver.delete` cannot act on it.

- `FileSelection.deletableCount` counts what is actually removable.
- Delete is **disabled** when that count is zero, rather than starting a flow
  the platform will certainly refuse.
- When only some of a selection is deletable, the bar says so
  (`120.0 MB · 3 can be deleted`), so the count is never misleading.
- `runDeleteFlow` sends only the deletable subset.

## Unchanged

- Review → Confirm → Android system approval → Cleanup Complete is untouched.
- `DeleteBridge` still uses `MediaStore.createDeleteRequest` on Android 11+ and
  `RecoverableSecurityException` on Android 10, so scoped storage and the
  system confirmation dialog are **not** bypassed.
- No new cleaner features, no redesign of unrelated screens, no native changes,
  no new dependencies.

## Automated tests

`test/selection_action_bar_test.dart` runs nine checks against all four
screens:

- no bar before anything is selected,
- selecting reveals a visible, enabled Delete, asserted by measuring the
  button's rect against the screen bounds,
- **the bar clears a 48 dp system navigation inset** — the regression guard for
  this bug, injected via `MediaQuery` so it reproduces the device condition,
- correct selected count and size, updating on Select All,
- Delete opens Review and does not delete immediately,
- Review → Confirm reaches Cleanup Complete with the right recovered size,
- Delete is **disabled** when every selected item is a `file://` row,
- the bar survives a 320 dp screen and a 1.5× font scale.

The inset test is the one that matters: the previous suite only checked the
button existed in the tree, which it always did, even while hidden behind the
system navigation bar.

## Device verification

1. Select an item in each of Screenshots, Downloads, APKs, and any file
   category. A bar with count, size, Clear, and Delete must appear **fully
   above** the navigation bar.
2. Repeat with gesture navigation and with three-button navigation.
3. Repeat at the largest system font size.
4. Delete, approve the Android dialog, and confirm Cleanup Complete reports the
   freed space.
5. Decline the Android dialog and confirm nothing is removed.
