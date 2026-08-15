# Phase 9 — Large Files

## Goal

The first real cleaner tool: find the biggest space users on the phone, filter
them by size, and show how much space they occupy.

Filters: **100 MB+, 500 MB+, 1 GB+.**

Still read-only. Phase 9 surfaces what is worth removing and leaves the
decision — and the deletion — to a later phase.

## Implemented

### Filters

`LargeFileFilter` (`lib/features/files/domain/large_file_filter.dart`) defines
the three required thresholds:

| Filter | `label` | `threshold` | `minBytes` |
| --- | --- | --- | --- |
| `over100mb` | `100 MB+` | `100 MB` | 104,857,600 |
| `over500mb` | `500 MB+` | `500 MB` | 524,288,000 |
| `over1gb` | `1 GB+` | `1 GB` | 1,073,741,824 |

Bounds are **inclusive**: a file of exactly 100 MB matches `100 MB+`. Two
labels are carried deliberately — `label` for the chip, `threshold` for
sentences like "3 files over 100 MB" — rather than stripping the `+` at each
call site.

### One scan, three views

`largeFileScanProvider` runs a single scan at `LargeFileFilter.lowestBound`
(100 MB), reusing the `minSizeBytes` hook built in Phase 6. Because every
higher threshold is a subset of that result, `largeFileSummaryProvider`
filters **in memory**, so tapping a chip never triggers another device scan.
Pushing the size floor into the MediaStore query also means the tool ignores
the thousands of small files a phone holds.

### Total space used

`LargeFileSummary` is the headline model:

- `files` — matches, sorted largest first,
- `totalBytes` — the combined size, shown as the big number on the card,
- `fileCount`, `isEmpty`, `largestFile`,
- `bytesByCategory` — the total split per category, biggest contributor first.

It de-duplicates by `uri` before totalling. This matters: Phase 7 deliberately
reports a downloaded APK under both Downloads and APKs, and a "space used"
figure that counted it twice would be wrong.

### Screen

`LargeFilesScreen` shows the three filter chips, then a total card leading with
the combined size in large type, the matching file count, and a per-category
breakdown of where the space went. Below that, every match as a full
Phase 8 row — thumbnail, name, size, date — biggest first.

Empty state is deliberately reassuring rather than an error: a green check and
"No files over 1 GB", since finding nothing is a good result. Pull-to-refresh
and a rescan action re-run the scan.

### Entry points

- **Home → Quick Tools → Large Files** now opens the real tool. It previously
  pointed at the Files tab, which was a placeholder for this phase.
- **Files tab** gains a "Large Files" card above the category grid.

Both `push` onto the current tab, so the back button returns where the user
came from. The route is registered top-level as `/large-files`.

## Automated tests

`test/large_files_test.dart`:

- the three thresholds exist with the correct labels and byte bounds,
- bounds are inclusive (100 MB matches, one byte under does not),
- filtering and totals are correct at each of the three thresholds,
- matches sort largest first,
- a file shared by two categories counts once,
- empty input yields a zero total and a null largest file,
- the category breakdown orders by size,
- all three chips render and default to 100 MB+,
- the total card shows the right figure at each threshold,
- listed files exclude anything under the threshold,
- switching chips narrows the list and updates the total,
- **switching a chip does not trigger a second scan** (`scanCount == 1`),
- the scanner is asked for the lowest bound,
- the empty state renders,
- the category breakdown appears.

Totals are asserted by reading the keyed headline widget, not by string match,
because the same size string can legitimately appear in the breakdown too.

Run with `flutter test`.

## Device acceptance test

1. Open **Home → Quick Tools → Large Files** (or the card on the Files tab).
2. With 100 MB+ selected, confirm every listed file really is at least 100 MB
   and that the list is ordered biggest first.
3. Check the total against the listed sizes — it should equal their sum.
4. Tap 500 MB+ and 1 GB+ and confirm the list shrinks, the total drops, and
   the count sentence updates. Switching should be instant, with no rescan.
5. Cross-check two or three entries against a file manager for name and size.
6. Confirm the category breakdown matches the file types you see.

## Notes and limits

- Results are capped at 300 rows per category. On a phone with an unusual
  number of very large files the list is truncated, though the biggest always
  rank first.
- Only files MediaStore indexes are visible, so app-private data in
  `/Android/data` is not counted. That is the same least-privilege boundary as
  earlier phases.
- The total is the size of the *matching* files, not a promise of reclaimable
  space; nothing is deleted in this phase.

## Next phase hooks

`LargeFileSummary.files` is the natural selection surface for a delete flow:
adding checkboxes and a "free up X" action needs the summary plus a deletion
gateway, without changing the filtering logic.
