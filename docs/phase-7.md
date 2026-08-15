# Phase 7 — File Categories

## Goal

Build the Files tab as a real category browser on top of the Phase 6 scanner,
covering six categories: **Images, Videos, Audio, Documents, Downloads, APKs.**

Still read-only — Phase 7 browses and classifies, it does not delete.

## Implemented

### New category: APKs

`FileCategory` gains `apks` (key `apks`, label `APKs`), and
`FileCategory.scannable` now lists all six in display order.

On the native side, `FileScannerBridge.queryApks()` finds installer packages
anywhere in shared storage by querying `MediaStore.Files` for either the
`application/vnd.android.package-archive` MIME type **or** a `%.apk` display
name, so packages are still found when MediaStore has not classified the row.
The `LIKE` clause is deliberately loose, so results pass through `isApk()`,
which re-checks the true extension and rejects names such as `notes.apk.txt`.

APKs were previously swept into Documents by the extension allowlist. `apk` has
been removed from `DOCUMENT_EXTENSIONS`, the package MIME type removed from
`DOCUMENT_MIME_PREFIXES`, and the documents query now filters
`isDocument(it) && !isApk(it)`, so each installer appears in exactly one of the
two categories.

### Overlapping categories, honest totals

A downloaded APK genuinely belongs to both **Downloads** and **APKs**, so those
two lists overlap by design. To stop the overview double counting it,
`FileScanResult` gained `uniqueFiles`, which de-duplicates by `uri`;
`totalFiles`, `totalBytes`, and `largestFiles()` all now count each physical
file once, while the per-category lists still show it in both places.

### Category metadata

Each `FileCategory` now carries a `description` and an `emptyMessage`, so empty
states read naturally ("No APK files found") instead of being generated from a
lowercased label ("No apks found").

### Files tab

`files_screen.dart` is now a **2-column category grid**. Every category gets a
card — with its own icon and accent colour — showing file count and total size.
Empty categories stay visible and are rendered in a muted "Empty" state rather
than being hidden, so the tab never looks broken. Below the grid: a totals card
and the ten largest files. Pull-to-refresh and rescan are retained.

### Category screen

`category_files_screen.dart` (extracted to its own file) lists the files in one
category with:

- a header showing the count and combined size of what is visible,
- **sort** by largest / newest / name via `FileListSort`,
- **search** by file name from the app bar,
- a distinct empty state for "category is empty" vs "no search matches",
- pull-to-refresh, and the shared scanning/error views.

Sort and search are per-visit widget state, so browsing one category never
mutates another. `FileScanResult.compareFiles` owns the ordering logic so the
UI does not reimplement it.

### Shared widgets

The scanning and error views moved into `files_status_views.dart`
(`FilesScanningView`, `FilesErrorView`) and are reused by both screens.
`file_category_tile.dart` was replaced by `file_category_card.dart`, which owns
`iconForCategory` and `colorForCategory`.

## Automated tests

`test/file_categories_test.dart` (new):

- the six required categories exist, in order, with the expected labels
- `apks` round-trips through the platform key contract
- APK detection by extension and by MIME type, and the `notes.apk.txt` trap
- every category reports its own files and sizes
- a downloaded APK appears in both lists but counts once in totals
- each sort order returns the expected first item
- **one independent widget test per category** asserting that opening it shows
  that category's real file and none of the other five
- all six cards render, including empty ones
- header count/size, sort reordering, and search filter + clear

Existing Phase 6 tests were updated for the renamed keys
(`category_tile_*` → `category_card_*`) and now run on a phone-sized surface.

Run with `flutter test`.

## Device acceptance test

1. Install on a phone that has photos, videos, music, documents, downloads, and
   at least one `.apk` saved.
2. Open **Files**. All six cards appear with plausible counts and sizes.
3. Open each category in turn and confirm the listed files really belong to it
   — cross-check a few names, sizes, and dates against a file manager.
4. Confirm a downloaded `.apk` appears under **both** Downloads and APKs, and
   that the totals card still counts it once.
5. In a category, change the sort and confirm the order changes; search for a
   partial file name and confirm filtering, then clear it.
6. Open a category you have no files for and confirm the empty message.

## Notes and limits

- Category counts can exceed the totals card, because Downloads and APKs
  legitimately overlap. Totals are de-duplicated; category lists are not.
- Per-category results remain capped by `limitPerCategory`; `truncated` is
  surfaced in the UI.
- APK detection is name/MIME based. It does not parse the package manifest, so
  a renamed `.apk` is classified by its current extension.

## Next phase hooks

Category lists are the natural selection surface for deletion. `ScannedFile.uri`
remains the handle a later phase will use to preview or delete, and
`FileScanRequest(minSizeBytes:)` still backs a Large Files view.
