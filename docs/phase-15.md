# Phase 15 — Screenshot Cleaner

## Goal

Detect screenshots and group them by age, showing a **count** and **total
size** for each group:

- **All screenshots**
- **30+ days**
- **90+ days**

## Detection

Android has **no "screenshot" media type** — a screenshot is just a PNG. So
detection is necessarily heuristic, and `ScreenshotDetector` checks two
independent signals, because neither alone is reliable:

1. **Folder** — the file sits in a screenshot folder. Vendors differ, so
   `Pictures/Screenshots`, `DCIM/Screenshots`, `screencapture` and similar all
   count. Matching is done on **whole path segments**, so a folder named
   `MyScreenshotsBackup` correctly does *not* match.
2. **Filename** — the name begins with a known prefix such as `Screenshot_`.
   This catches screenshots a user has moved out of the standard folder.

Both checks are case-insensitive, and `relativePath` is preferred with the full
path as fallback, since SAF-sourced rows populate them differently.

Two deliberate exclusions:

- **Non-images never match**, even inside a screenshots folder. A screen
  *recording* is a video, and deleting it under a tool labelled "Screenshots"
  would surprise the user.
- **Unknown timestamps** are never treated as old, so a file whose date the
  platform could not read is never swept into an age bucket.

Detection is a heuristic, which is why the tool shows every match for review
rather than deleting anything automatically.

## Groups

| Group | Bound |
| --- | --- |
| All screenshots | no age restriction |
| 30+ days | ≥ 30 days |
| 90+ days | ≥ 90 days |

Bounds are inclusive and compared at **day boundaries**, so a screenshot taken
at 23:59 behaves like one taken at 00:01 that day.

One scan of the image library feeds all three groups, so switching chips
filters in memory and never rescans the device.

## Display

The headline card shows exactly what the phase requires: the **count** on the
left and the **total size** on the right, both updating as the group changes.
Below it, the screenshots themselves, **newest first**, as Phase 8 tiles with
thumbnail, name, size, and date.

Selection and deletion reuse the existing machinery unchanged — the Phase 10
`FileSelection` model and the Phase 12 `runDeleteFlow`, so this tool cannot
drift from the others on safety.

## Shared age helper

`DownloadAgeFilter` and `ScreenshotGroup` both need day-boundary age maths, so
it now lives in `core/utils/file_age.dart` and both delegate to it. Duplicating
that logic would have risked the two tools disagreeing about what "30 days"
means.

## Photos tab

The Photos tab was a placeholder. It now lists Screenshots as a working tool,
with Duplicates, Similar photos, and Blurry photos shown greyed out as
upcoming — honest about what the tab can do today rather than hiding the gap.

## Automated tests

`test/screenshot_cleaner_test.dart`:

**Detection** — the standard folder and its DCIM variant; filename prefix
outside the folder; case insensitivity; ordinary photos ignored; the
`MyScreenshotsBackup` lookalike rejected; non-images excluded even inside the
folder; the full-path fallback when `relativePath` is absent.

**Groups** — the three required groups and labels; `all` ignores age entirely;
inclusive bounds; unknown timestamps never old.

**Summary** — counts and totals per group (3/12 MB, 2/9 MB, 1/4 MB); the
camera photo excluded from every group; newest-first ordering; URI
de-duplication; largest screenshot; empty input.

**Screen** — scans only images with no size floor; three chips; the count and
total size; screenshots listed and photos hidden; narrowing shrinks both
figures; changing group does not rescan; selection bar count and size; select
all; narrowing drops hidden selections; app bar count; delete enabled; empty
state.

One assertion in `widget_test.dart` was updated, since the Photos tab no longer
renders the placeholder.

## Device acceptance test

1. Open **Photos → Screenshots**.
2. Confirm the count and total size look right for the device, and that camera
   photos are absent.
3. Switch to 30+ days and 90+ days; both figures should shrink, instantly and
   without a rescan.
4. Check a screenshot you moved out of the Screenshots folder still appears.
5. Confirm any screen recordings are **not** listed.
6. Select a few, delete, and confirm the Cleanup Complete screen reports the
   right recovered size.

## Notes and limits

- Detection is heuristic. An image named `Screenshot_...` that is not really a
  screenshot will be listed, which is why nothing is deleted without review.
- Capped at 1000 images per scan.
- Vendors occasionally use folder names not in the list; adding one is a
  one-line change to `ScreenshotDetector.folderNames`.
- The same scoped-storage limits apply: on Android 10+ some images are only
  visible once a folder has been granted through SAF.
