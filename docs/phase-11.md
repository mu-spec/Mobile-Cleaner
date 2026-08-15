# Phase 11 — APK Cleaner

## Goal

Detect `.apk` installer files stored on the device, show each one's **name,
size, and date**, and allow **multi-selection**.

Read-only. Selection is built here; deletion arrives in a later phase, so the
Delete button is present but disabled.

## Implemented

### Detection

`ApkSummary.from` filters on **`ScannedFile.isApk`**, not on category. That
distinction matters: an installer sitting in the Downloads folder is still an
installer, and Phase 7 deliberately reports a downloaded package under both
Downloads and APKs.

`isApk` matches either the `.apk` extension or the
`application/vnd.android.package-archive` MIME type, so a package is still
found when MediaStore has not classified it — and a file named
`notes.apk.txt` is correctly rejected, because the check is on the true
extension rather than a substring.

`apkScanProvider` scans **APKs, Downloads, and Documents** in one pass. Relying
on the APKs category alone would miss packages the platform filed elsewhere;
scanning the three plausible sources and filtering on the file itself is more
reliable.

Results are de-duplicated by URI, so a package reported by two categories is
listed and counted exactly once.

### Display

Each row is the existing Phase 8 `ScannedFileTile`, which already shows exactly
what this phase requires:

| Element | Source |
| --- | --- |
| Name | `file_name_<id>`, ellipsised |
| Size | `file_size_<id>`, via `ByteFormatter` |
| Date | `file_date_<id>`, relative, via `DateFormatter` |

Above the list, a total card shows the combined size of every installer, the
count, and a short note that removing an installer does **not** uninstall the
app — the most likely user misconception for this tool.

Sorting reuses `FileListSort` (largest, smallest, newest, oldest, name) from
the app bar menu. Sorting filters the cached scan in memory, so changing order
never triggers another device scan.

### Selection

Reuses the Phase 10 `FileSelection` model unchanged — an immutable set keyed by
URI, so a rescan that rebuilds `ScannedFile` instances does not silently drop
the selection.

- tap a row or its checkbox to toggle,
- **Select all** / **Clear all** for everything listed,
- the app bar switches to "N selected" with a cancel action,
- a bottom bar shows the count and combined size,
- long-press opens the Phase 8 details sheet,
- Delete is present but disabled until the deletion phase.

### Entry point

The Files tab gains an "APK Cleaner" card beside Large Files and Downloads
Cleaner. The route is registered top-level as `/apk-cleaner` and pushed, so
back returns where the user came from.

## Automated tests

`test/apk_cleaner_test.dart`:

**Detection** — keeps only real installers; finds them across all three
categories; detects by MIME type alone; rejects `notes.apk.txt` and images;
totals size; counts a doubly-reported package once; each sort order; largest
installer; empty input.

**Screen** — scans the three categories; shows name, size and date; excludes
lookalikes; displays the combined size and count; largest first by default;
sorting reorders **without rescanning**; selecting reveals the bar with the
right count and size; multi-select totals; deselect; select all then clear;
app bar reflects the count; clear button; delete stays disabled; empty state.

Size assertions read the keyed `Text` widget rather than matching a string,
because the same size can legitimately appear in both a row and the selection
bar.

## Regression fixed in existing tests

Adding a third cleaner card pushed the category grid down roughly 76px, which
put the bottom grid row (Downloads and APKs) **below the fold** on the
420x1000 test surface. Six card taps in `file_categories_test.dart` and two
assertions in `file_scanner_test.dart` interacted with those cards without
scrolling and would now fail. All of them scroll the card into view first.

## Device acceptance test

1. Save an `.apk` to the device, then open **Files → APK Cleaner**.
2. Confirm it is listed with the correct name, size, and date, and that the
   total matches the sum of the listed sizes.
3. Confirm non-installers are absent, including any file merely named
   `something.apk.txt`.
4. Change the sort order and confirm the list reorders instantly, with no
   rescan spinner.
5. Select several installers and confirm the bottom bar count and size.
6. Use Select all, then Clear, and confirm the bar disappears.
7. Long-press a row and confirm the details sheet shows the full path.

## Notes and limits

- Capped at 500 rows per scanned category.
- On Android 10+, installers other apps saved are only visible once a folder
  has been granted through the Storage Access Framework. The Files tab banner
  prompts for this; without a grant the list can legitimately look sparse.
- Classification is name and MIME based. It does not parse the package
  manifest, so a renamed `.apk` is judged by its current extension, and the
  tool cannot tell whether the matching app is already installed.
- The total is the size of the installers found, not a promise of reclaimable
  space; nothing is deleted in this phase.

## Next phase hooks

`FileSelection` already carries the files and byte total a delete flow needs.
Enabling deletion means turning on the Delete button, adding a confirmation,
and calling a deletion gateway with `selection.files`.
