# Phase 16 — Large Photos

## Goal

Find the images taking the most space, with three suggested thresholds:

- **5 MB+**
- **10 MB+**
- **20 MB+**

## Why these thresholds and not Phase 9's

Large Files starts at 100 MB, which would hide essentially every photo — a
modern camera shot is a few megabytes. `LargePhotoFilter` is a separate enum
rather than a reuse of `LargeFileFilter`, because the two tools answer
different questions: "what is huge on this device" versus "which pictures are
unusually heavy".

Bounds are **inclusive**: a photo of exactly 5 MB matches `5 MB+`.

## Photos, not media

`LargePhotoSummary.isPhoto` trusts an explicit MIME type over the category
bucket, falling back to `FileCategory.images` when the platform reports no MIME
type. So an image saved into Downloads still counts, and a video misfiled under
Images does not.

**Videos are excluded deliberately.** They are the largest media on most
phones, so including them would dominate the list — but a tool labelled "Large
Photos" offering to delete a home video would be a nasty surprise. Large videos
remain reachable through Large Files and the Videos category.

## One scan, three views

`largePhotoScanProvider` requests **images only**, with the 5 MB floor pushed
into the MediaStore query so the platform never returns the thousands of small
pictures a phone holds. Every higher threshold is a subset of that result, so
`largePhotoSummaryProvider` filters in memory and switching chips never
rescans.

## Screen

- Threshold chips: 5 MB+, 10 MB+, 20 MB+.
- A headline card: combined size, the count, and the **average photo size**,
  which gives useful context — twelve 8 MB photos is a different problem from
  one 96 MB panorama.
- Every match as a Phase 8 row, largest first, with thumbnails.
- Selection and deletion reuse `FileSelection` and `runDeleteFlow` unchanged,
  so this tool cannot drift from the others on safety.
- The action bar sits in the body `Column` below the `Expanded` list, and the
  list is a `ListView.builder`, matching the fixes made after the earlier
  selection-freeze work.
- Empty state is reassuring rather than an error: finding no huge photos is a
  good result.

## Entry point

The Photos tab promotes **Large photos** from "coming soon" to a working tool,
beside Screenshots. Duplicates, Similar and Blurry remain listed as upcoming.

Route `/large-photos`, pushed so Back returns to Photos.

## Automated tests

`test/large_photos_test.dart`:

**Filters** — the three thresholds with the right labels and byte bounds;
inclusive matching.

**Summary** — counts and totals at each threshold (3/48 MB, 2/42 MB, 1/30 MB);
videos excluded even at 400 MB; MIME type beats category, with a category
fallback when MIME is absent; largest-first ordering; URI de-duplication;
average size; empty input.

**Screen** — scans only images at the lowest bound; three chips; count and
total size; photos listed largest first with videos and sub-threshold images
hidden; raising the threshold narrows both figures; changing threshold does not
rescan; the selection bar count and size; select all; raising the threshold
drops now-hidden selections; delete enabled; empty state.

## Device acceptance test

1. Open **Photos → Large photos**.
2. Confirm the count and total look right, and that no videos appear.
3. Switch to 10 MB+ and 20 MB+; both figures should shrink instantly, with no
   rescan spinner.
4. Cross-check two entries against a gallery app for name and size.
5. Select several, delete, approve the Android dialog, and confirm Cleanup
   Complete reports the recovered size.
6. Confirm the deleted photos are gone from the gallery.

## Notes and limits

- Capped at 500 images per scan, largest first.
- The size floor is applied by the platform query, so sub-5 MB photos are never
  transferred at all.
- The same scoped-storage limits apply: on Android 10+ some images are only
  visible once a folder has been granted through SAF.
- A large photo is not necessarily a bad photo. Nothing is deleted without
  review.
