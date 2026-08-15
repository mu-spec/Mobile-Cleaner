# Phase 12 — Safe Delete System

## Goal

One reliable deletion system every cleaner shares, so the safety rules cannot
drift between tools.

Flow: **Select → Review → Confirm → Delete → Result.**

This is the first phase that removes user data. The design bias throughout is
*never overstate what happened*: a file is only reported as deleted once the
platform confirms it is gone.

## The flow

### 1. Select

Reuses the Phase 10 `FileSelection` model — immutable, keyed by URI, so a
rescan that rebuilds `ScannedFile` instances cannot silently drop a selection.
It already provides **Select**, **Select All**, **Deselect All**, a live
**count**, and a running **selected size**.

### 2. Review

A bottom sheet lists what will go: file names with sizes, the total count and
combined size, and — for large selections — the first eight followed by
"and N more" rather than an unreadable wall of rows.

### 3. Confirm

The same sheet carries an explicit, unmissable warning that deletion **cannot
be undone** and that files are not moved to a recycle bin, plus a note that
Android may ask again. The destructive action is styled with the error colour
and labelled with the exact count (`Delete 12`). Cancel is the calmer,
outlined option.

Nothing reaches the platform until this is confirmed.

### 4. Delete

`DeleteBridge` handles the three distinct Android regimes:

| Platform | Mechanism |
| --- | --- |
| Android 11+ | `MediaStore.createDeleteRequest` — one system dialog for the whole batch |
| Android 10 | `RecoverableSecurityException` → `IntentSender`, confirmed per file |
| Android 9 and below | plain `ContentResolver.delete` |

SAF document URIs bypass MediaStore and are removed with
`DocumentsContract.deleteDocument`, which needs no extra dialog because the
user already granted access to that tree.

The system dialog is an **additional** gate, never a replacement for the
in-app confirmation.

A blocking progress dialog is shown during the operation. It is pushed on the
root navigator and dismissed via that navigator, so it can never pop the
caller's route even if the delete completes before the dialog finishes
mounting.

### 5. Result

`DeleteResult` reports honestly, distinguishing four outcomes: complete
success, **partial** success, user cancellation, and total failure. It carries
the files actually removed, the space genuinely freed, and a reason for every
failure.

After a batch the bridge **re-queries each URI** rather than trusting the
system's "OK", so a file the platform declined to remove is reported as failed
instead of being counted as freed space.

The result dialog is shown without awaiting, so the calling screen deselects
the deleted files and rescans immediately rather than waiting for the user to
dismiss it.

## Safety properties

- No deletion without an explicit in-app confirmation.
- A URI reported both deleted **and** failed is treated as **failed** — the
  safer reading when the platform is ambiguous.
- Platform errors and a missing plugin fail every file rather than silently
  reporting success.
- An empty selection never reaches the platform at all.
- Freed-space figures count only confirmed deletions.
- Nothing is deleted outside what the user selected and reviewed.

## Wiring

Both existing cleaners now call the shared flow; their Delete buttons are
enabled. After a successful delete each screen deselects what went and
invalidates its scan provider, so the list matches the device.

- `downloads_cleaner_screen.dart` → `downloadsScanProvider`
- `apk_cleaner_screen.dart` → `apkScanProvider`

## Automated tests

`test/safe_delete_test.dart`:

**Result model** — complete, partial, cancelled, and empty outcomes; freed
bytes count only real deletions.

**Payload parsing** — maps deleted URIs back to files; records failures and
reasons; a URI reported both deleted and failed is treated as failed; ignores
malformed rows and unknown URIs; defaults a missing reason; propagates
cancellation.

**Channel** — an empty selection never calls the platform; every URI is sent;
a `PlatformException` and a `MissingPluginException` both fail safely.

**Flow** — Review shows the count, size and the irreversible warning; Cancel
deletes nothing and keeps the selection; Confirm deletes and reports freed
space; the selection clears afterwards; declining the system dialog reports
"Nothing deleted"; a blocked delete reports failure with its reason; a large
selection is summarised; deleting triggers a rescan and the row disappears.

Existing suites were updated: the two "delete stays disabled" tests now assert
the button is **enabled**, and both cleaners get a recording delete repository
so no test can reach a real platform channel.

## Device acceptance test

1. Select one file in APK Cleaner and tap Delete. Confirm the review sheet
   shows the right name, size and warning.
2. Tap Cancel and confirm nothing was deleted and the selection survives.
3. Tap Delete again, confirm, and approve the Android system dialog. The
   result should report the freed size, and the row should disappear.
4. Repeat but **decline** the Android dialog. The result must say nothing was
   deleted, and the file must still be present.
5. Select several files, delete, and check the freed total matches their
   combined size.
6. Repeat in Downloads Cleaner to confirm both tools behave identically.

## Notes and limits

- Deletion is permanent. There is no recycle bin, which the confirmation states
  plainly.
- On Android 10 the platform confirms one file at a time; a large batch may
  need the operation repeating. Android 11+ handles a batch in one dialog.
- Files inside a SAF tree are deleted without a second dialog, because the
  grant already covers them.
- Freed space is what the platform confirmed removed, which can be less than
  the selected size when some files are protected.

## Next phase hooks

Any future cleaner gets deletion by calling `runDeleteFlow` with a
`FileSelection`. No tool should implement its own delete path.
