# Phase 27 — Error Handling

Handle permission denied, missing files, failed deletion, storage unavailable,
scan cancelled, and files moved during a scan. No crashes.

## What was already right, and what was not

Most repositories already caught `PlatformException` and `MissingPluginException`
and degraded to an empty result. The audit found the real gaps:

| Problem | Before | Now |
|---|---|---|
| Storage channel missing | **Uncaught** — crashes Home on launch | `STORAGE_UNAVAILABLE` |
| Scanner channel missing | **Uncaught** — crashes every tool | `SCAN_UNAVAILABLE` |
| File moved during scan | **Contradictory** — success in one path, failure in another | Success in both |
| Error screen | Two outcomes: "permission" or "could not scan" | Seven classified kinds |

## One classifier, `AppFailure`

`AppFailure.from(Object)` maps anything thrown onto a `FailureKind` —
`permissionDenied`, `missingFile`, `deleteFailed`, `storageUnavailable`,
`cancelled`, `unsupported`, `unknown`.

Three properties matter:

- **It never throws.** A test feeds it a bare string, an int, a map, and an
  empty `PlatformException`, and asserts every one produces a showable message.
- **It matches on the platform *code*, not the message**, so rewording an
  error cannot silently reclassify it.
- **Unknown is not swallowed.** An unrecognised error keeps its own text in
  `technicalDetail` rather than becoming a generic shrug.

### `isRetryable` matters

A permission failure and an unsupported feature are **not** retryable — the
same call would fail identically. The error screen therefore does not offer
"Try again" for those, only the action that could actually help. Offering a
button that is guaranteed to fail is worse than offering none.

## The scan-unavailable decision

When the scanner channel is missing, the natural thing is to return an empty
list. That is wrong here: an empty file list renders as *"No files found"* —
a spotlessly clean device — when in fact the app is broken. It now raises
`SCAN_UNAVAILABLE` so the user is told. Test:
`the scanner reports unavailable rather than an empty library`.

## File moved during scan

The two delete paths disagreed:

- direct file delete: file absent → **success**
- MediaStore delete: zero rows → **failure**, "File was already gone"

A file removed or moved between the scan and the delete is the *normal* race,
not an error. The user's goal was "this should not be on my phone", and it is
not. Reporting failure sent people back to a file that no longer existed. Both
paths now treat it as done.

## The error screen carries its own diagnosis

Each kind gets its own icon, headline, and message, and the platform code plus
details are rendered in small print (`files_error_detail`).

This is a direct lesson from the Android 11 scan bug: it went undiagnosed for
several phases because the screen showed a headline and nothing else. A
screenshot of this screen is now enough to identify the cause. A test asserts
`Invalid token LIMIT` — the exact string that was invisible — reaches the UI.

## Cancellation is not failure

`DeleteResult.cancelled()` already existed and the result dialog already said
"Nothing deleted" rather than "Could not delete". Phase 27 adds tests locking
that in: a cancelled delete reports zero deleted, zero *failures*, and is
neither a success nor an error.

## Files

**New:** `lib/core/errors/app_failure.dart`,
`test/error_handling_test.dart` (22 cases).

**Changed:** `files_status_views.dart` (classification-driven error view),
`storage_repository.dart` and `file_scanner_channel.dart` (catch missing
plugin), `DeleteBridge.kt` (moved-file consistency).

All 14 `FilesErrorView` call sites were checked — the constructor signature is
unchanged, so nothing else needed touching.

## Tests (22 cases)

Each of the six specified problems classified correctly; classification never
throwing on hostile input; unknown errors preserved; `AppFailure` passthrough;
platform code retained for diagnosis; storage and scanner degrading rather than
crashing; storage rejecting nonsense values; a failed delete reporting every
file with no exception escaping; deleting with no channel; deleting nothing;
cancellation distinct from failure; partial deletes counting only confirmed
bytes; the screen's per-kind headlines and actions; and a loop asserting
**every failure kind renders with no exception**.

## Verification status

**Static review only** here. Checked by hand: brace balance (stripping string
interpolation), truncation, imports, unused imports, 80-column limit, and all
14 call sites of the changed widget.

Two things worth knowing:

1. **"No crashes" cannot be proven by static review.** These tests prove the
   paths I found handle failure. `flutter analyze` plus a device run is what
   would actually establish it.
2. `DeleteBridge.kt` changed again — the moved-file fix. It is Kotlin, so it
   is unverified until it compiles.
