# Phase 10 — Downloads Cleaner

## Goal

A cleaner focused on the Downloads folder, filtered by **age** rather than
size, with **multi-selection** so a user can act on many files at once.

Filters: **30+ days, 90+ days, 6+ months, 1+ year.**

Selection is built here; deletion arrives in a later phase. The Delete button
is present but deliberately disabled, so the flow is visible without the app
being able to destroy anything yet.

## Implemented

### Age filters

`DownloadAgeFilter` (`lib/features/files/domain/download_age_filter.dart`):

| Filter | `label` | `threshold` | `minDays` |
| --- | --- | --- | --- |
| `days30` | `30+ days` | `30 days` | 30 |
| `days90` | `90+ days` | `90 days` | 90 |
| `months6` | `6+ months` | `6 months` | 182 |
| `year1` | `1+ year` | `1 year` | 365 |

Age is computed at **day boundaries**, not by raw duration, so a file saved at
23:59 is treated the same as one saved at 00:01 that day. Bounds are inclusive:
exactly 30 days old matches `30+ days`.

Two edge cases are handled deliberately:

- **Unknown timestamps** (epoch zero) never match any filter. A file whose date
  the platform could not read must not be presented as ancient and offered up
  for deletion.
- **Future dates** clamp to an age of 0 rather than going negative, which can
  happen with a bad device clock or a file copied from another timezone.

### Selection model

`FileSelection` is an immutable value type keyed by **URI**, not by object
identity. That matters: a rescan returns freshly constructed `ScannedFile`
instances, and a selection keyed by object would silently empty itself.

It offers `toggle`, `selectAll`, `deselectAll`, `clear`, `contains`,
`containsAll`, `count`, `totalBytes`, and `retainWhereVisible`. The last one
prunes selections that fall outside the current filter, so the action bar can
never act on a file the user can no longer see.

Being a pure model with no Flutter dependency, it is unit tested directly and
is reusable by any future tool that needs bulk selection.

### Summary

`DownloadsSummary` mirrors the Phase 9 shape: matching `files`, `totalBytes`,
`fileCount`, `oldestFile`, `largestFile`. It sorts **oldest first**, since the
strongest cleanup candidates should lead, and de-duplicates by URI because a
downloaded APK is reported under both Downloads and APKs.

### One scan, four views

`downloadsScanProvider` requests only `FileCategory.downloads`, with no size
floor — age is the filter here. Every threshold is a subset of that one scan,
so `downloadsSummaryProvider` narrows in memory and switching chips never
rescans the device.

### Screen

`DownloadsCleanerScreen` shows the four age chips, a total card leading with
the combined size of the stale downloads, and the matching files as selectable
rows, oldest first.

Selection behaviour:

- tap a row or its checkbox to toggle it,
- **Select all** / **Clear all** for everything currently visible,
- the app bar switches to "N selected" with a cancel action,
- a bottom bar shows the count and combined size of the selection,
- long-press still opens the Phase 8 details sheet,
- narrowing the filter prunes selections that are no longer visible.

### Reusable tile

`ScannedFileTile` gained optional `selected`, `selectionMode`, and
`onLongPress`. Defaults keep every existing caller — the Files tab, category
lists, Large Files — completely unchanged.

### Entry point

The Files tab gains a "Downloads Cleaner" card beside "Large Files". The route
is registered top-level as `/downloads-cleaner` and pushed, so back returns to
where the user came from.

## Automated tests

`test/downloads_cleaner_test.dart`:

**Filters** — the four thresholds and their day bounds; inclusive matching;
clock time within a day ignored; future dates never old; unknown timestamps
excluded from every filter.

**Summary** — counts and totals at each of the four thresholds; oldest-first
ordering; URI de-duplication; largest file; empty input.

**Selection** — starts empty; toggle on and off; size totalling; select all and
deselect all; `containsAll` false for an empty list; **keyed by URI so a
rebuilt instance stays selected**; `retainWhereVisible` pruning; clear.

**Screen** — four chips render; only the Downloads category is scanned; stale
files listed and recent ones hidden; narrowing shrinks the list; changing a
filter does not rescan; selecting reveals the bar with the right count and
size; multi-select totals; deselect; select all then clear; app bar reflects
the count; **narrowing the filter drops now-hidden selections**; delete stays
disabled; empty state.

Note on time: widget tests build fixtures against the **real** clock, because
the provider uses `DateTime.now()`. Domain tests pin both the fixture and the
assertion to a fixed date. Fixtures are anchored at midday so a daylight-saving
shift cannot move one across a day boundary.

Run with `flutter test`.

## Device acceptance test

1. Open **Files → Downloads Cleaner**.
2. With 30+ days selected, confirm every listed file really is that old and
   that recent downloads are absent. Check the total against the listed sizes.
3. Tap 90+ days, 6+ months, 1+ year and confirm the list shrinks and the total
   drops each time. Switching should be instant, with no rescan.
4. Tap several rows and confirm the bottom bar count and size are correct.
5. With items selected, narrow the filter and confirm the count drops to only
   what is still visible.
6. Use Select all, then Clear, and confirm the bar disappears.
7. Long-press a row and confirm the details sheet still opens.

## Notes and limits

- Capped at 500 downloads per scan. A larger folder is truncated, though the
  scan requests newest-first from the platform.
- "6 months" is 182 days and "1 year" is 365 days. Calendar months vary, and a
  fixed day count is predictable and matches what the chip implies.
- The total is the size of matching downloads, not a promise of reclaimable
  space; nothing is deleted in this phase.
- Age uses the file's modified date, which is what MediaStore exposes. A file
  edited after download will look newer than its download date.

## Next phase hooks

`FileSelection` already carries the exact files and byte total a delete flow
needs. Wiring deletion means enabling the Delete button, adding a confirmation,
and calling a deletion gateway with `selection.files` — no change to filtering
or selection logic.
