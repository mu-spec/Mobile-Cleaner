# Phase 13 — Cleanup Completion Screen

## Goal

After a successful deletion, show a dedicated **Cleanup Complete** screen
reporting three figures:

- **Files deleted**
- **Storage recovered**
- **Free storage now**

## Implemented

`CleanupCompleteScreen` replaces the small result dialog on the success path.
A green check, the "Cleanup Complete" headline, and three stat cards:

| Card | Source | Key |
| --- | --- | --- |
| Files deleted | `DeleteResult.deletedCount` | `cleanup_files_deleted` |
| Storage recovered | `DeleteResult.freedBytes` | `cleanup_storage_recovered` |
| Free storage now | `StorageInfo.freeBytes` | `cleanup_free_storage` |

### Free storage is read fresh

The important correctness detail: **`storageOverviewProvider` is invalidated
before the screen is pushed.** Without that, Riverpod would serve the value
cached when Home last read it — from *before* the deletion — and the screen
would claim the phone has less free space than it now does. Invalidating
forces a new `StatFs` read through the Phase 4 bridge.

### Honest reporting is preserved

Phase 12's rule carries through: only files the platform confirmed removed are
counted, so "storage recovered" never overstates what happened.

- A **partial** delete still shows the completion screen — real space was
  freed — but adds a warning panel naming how many files survived and why.
- A **cancelled** or **fully failed** delete never reaches this screen. Those
  keep the Phase 12 dialog, which is the proportionate response when nothing
  changed.
- A **storage read failure** degrades to "Unavailable" for that one figure
  rather than failing the screen. A cleanup that worked should not look broken
  because `StatFs` hiccuped.

### Navigation

The screen is pushed on the local navigator, so **Done** returns to the cleaner
the user came from, with its list already refreshed. The push is not awaited,
so the calling screen deselects deleted files and rescans immediately rather
than waiting for the user to dismiss anything.

## Automated tests

Added to `test/safe_delete_test.dart`:

- reports all three figures correctly — 3 files, 100.0 MB recovered, and
  25.0 GB free read from the platform,
- singular wording and figures for a single file,
- a storage read failure shows "Unavailable" while still reporting the
  recovered space,
- a partial delete shows the completion screen **and** the warning panel, and
  counts only the file that really went,
- cancelling never reaches the completion screen — the dialog is shown instead,
- **Done** returns to the cleaner.

Four existing Phase 12 assertions were updated, because the success path now
shows this screen rather than the dialog. The suite also gains a fake storage
repository, so no test reaches a real `StatFs` channel.

## Device acceptance test

1. In APK Cleaner, note the device's free space (Home shows it).
2. Select a few installers and complete the delete.
3. The Cleanup Complete screen should report the right file count, a recovered
   figure matching their combined size, and a **free storage** figure larger
   than the one you noted in step 1.
4. Tap Done and confirm you return to the cleaner with those rows gone.
5. Cancel a delete instead and confirm this screen does **not** appear.

## Notes and limits

- "Free storage now" comes from `StatFs` on the data partition, so it can
  differ slightly from Android Settings, which rounds differently and reserves
  some system space. This is the same caveat documented in Phase 4.
- Recovered space is what the platform confirmed deleted, which can be less
  than the selected size when some files are protected.
- The figure is a point-in-time read; other apps writing concurrently can move
  it between the delete and the read.
