# Phase 12 fix — selection action bar visibility and reuse

## Reported problem

Selection worked on real Android devices, but the Clear/Delete bottom action
bar was not visible, so the Phase 12 safe-delete flow was unreachable.

## Root cause

On device the symptoms were: the header showed "1 selected", the row
highlighted, but no action bar appeared **and the whole body stopped
responding** — the list could not be scrolled.

Both symptoms came from putting the bar in `Scaffold.bottomNavigationBar`
while the body was wrapped in a `SafeArea`. The body's `SafeArea` consumes the
bottom inset, and the Scaffold then also reserves space for the bottom slot, so
the two competed for the same region: the bar was laid out beneath the system
navigation bar, and the body's hit-test area no longer matched what was drawn,
which is what made the list unresponsive.

Earlier attempts treated this as a padding problem. It was a **placement**
problem.

## Fix

`SelectionActionBar` is no longer a Scaffold slot. It sits directly in each
screen's body `Column`, immediately below the `Expanded` scrollable list:

```
SafeArea
└── Column
    ├── filter / sort chips
    ├── Expanded(list)        <- keeps all remaining height, scrolls freely
    └── SelectionActionBar    <- takes only the height it needs
```

Because the bar is a sibling in the same `Column`, it takes the height it
needs and the list keeps the rest. Nothing overlaps, nothing competes for the
inset, and the list's hit-test area matches what is drawn, so scrolling and
further selection keep working.

The body's existing `SafeArea` already clears the system navigation bar, so the
bar no longer pads for the inset itself — doing so would double-count it.

The lists also no longer reserve extra bottom padding while selecting; with the
bar outside the scroll view, that space would just be dead room.

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
- **the list still scrolls while selecting** — the regression guard for the
  unresponsive body, asserted by dragging and comparing scroll offsets,
- **more items can be selected after the bar appears**,
- **the bar does not overlap the list**, asserted by comparing their rects,
- correct selected count and size, updating on Select All,
- Delete opens Review and does not delete immediately,
- Review → Confirm reaches Cleanup Complete with the right recovered size,
- Delete is **disabled** when every selected item is a `file://` row,
- the bar survives a 320 dp screen and a 1.5× font scale.

The scroll and overlap tests are the ones that matter: the previous suite only
checked the button existed in the tree, which it always did, even while the
body was unresponsive and the bar was hidden behind the system navigation bar.

## Device verification

1. Select an item in each of Screenshots, Downloads, APKs, and any file
   category. A bar with count, size, Clear, and Delete must appear **fully
   above** the navigation bar.
2. With items selected, **scroll the list** — it must move freely.
3. Select more items, use Select all, then Clear, then Back. All must respond.
4. Repeat with gesture navigation and with three-button navigation.
5. Repeat at the largest system font size.
6. Delete, approve the Android dialog, and confirm Cleanup Complete reports the
   freed space.
7. Decline the Android dialog and confirm nothing is removed.
