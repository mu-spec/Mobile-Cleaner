# Phase 6 — File Discovery Foundation

## Goal

Build the internal file/media scanner that every later cleaning phase reads
from. Phase 6 is **read-only**: it discovers and describes files, it never
deletes, moves, or opens them.

## Implemented

### Reusable file model

`lib/features/files/domain/scanned_file.dart` — `ScannedFile` carries exactly
the fields the phase requires, plus a stable identity for later selection:

| Field | Meaning |
| --- | --- |
| `name` | Display name with extension, e.g. `IMG_0042.jpg` |
| `path` | Absolute filesystem path when the platform exposes one |
| `uri` | Content URI, e.g. `content://media/external/images/media/42` |
| `sizeBytes` | Size in bytes |
| `category` | `FileCategory` bucket the file was discovered in |
| `dateModified` | Last modified timestamp |
| `mimeType` | MIME type when known (nullable) |
| `relativePath` | Bucket-relative path such as `DCIM/Camera/` (nullable) |
| `id` | MediaStore row id, falling back to the URI or path |

Derived helpers: `extension`, `folderName`, `copyWith`, value equality, and
`ScannedFile.fromPlatformMap` which returns `null` for unusable rows so one bad
MediaStore record can never fail an entire scan. The model has no Flutter or
platform imports, so it is reusable from any layer.

### Categories

`lib/features/files/domain/file_category.dart` — `images`, `videos`, `audio`,
`documents`, `downloads`, plus an `other` fallback. Each enum value carries the
`key` string that is the wire contract with the Android bridge, so a renamed
label can never break parsing. `FileSortOrder` covers size, date, and name.

### Scan result

`lib/features/files/domain/file_scan_result.dart` — `FileScanResult` groups a
flat file list into per-category `FileCategorySummary` totals (count, bytes,
newest file) and exposes `totalFiles`, `totalBytes`, `byCategory`,
`summariesBySize`, and `largestFiles(limit:)`. It also reports `durationMillis`
and `truncated` for diagnostics.

### Native scanner

`android/app/src/main/kotlin/com/mobilecleaner/app/FileScannerBridge.kt` —
a MediaStore-backed bridge on channel `com.mobilecleaner.app/file_scanner`,
registered from `MainActivity`.

- Images / Videos / Audio: the respective `MediaStore.*.Media` collections.
- Documents: `MediaStore.Files` excluding image/video/audio media types, then
  filtered by document MIME prefixes and a known extension allowlist
  (pdf, doc(x), xls(x), ppt(x), txt, csv, epub, zip, apk, …).
- Downloads: `MediaStore.Downloads` on Android 10+, with a bounded
  directory walk of the public Downloads folder as a legacy fallback.
- Zero-byte rows are skipped; `limitPerCategory` (default 500, max 5000) and
  `minSizeBytes` keep large libraries responsive.
- `SecurityException` surfaces as `SCAN_PERMISSION_DENIED` so the UI can send
  the user to the permission screen instead of showing a generic failure.
- Only metadata columns are read — no file contents are ever opened.

### Data layer

- `file_scanner_channel.dart` — thin `MethodChannel` transport, faked in tests.
- `file_scanner_repository.dart` — `FileScanRequest` options plus
  `MediaStoreFileScannerRepository`, which parses rows, de-duplicates entries
  that appear in both a media table and Downloads, and builds the result.

Both are behind Riverpod providers, so any layer can be overridden in tests.

### Presentation

- `file_scan_provider.dart` — `fileScanProvider` (full scan),
  `categoryFilesProvider` (per-category, largest first), and
  `selectedFileCategoryProvider`.
- `files_screen.dart` — replaces the Phase 1 placeholder with a real dashboard:
  totals card, per-category tiles with share-of-storage bars, top 10 largest
  files, pull-to-refresh, a rescan action, and scanning / empty / error states.
  Permission errors offer a shortcut to the permission screen.
- `CategoryFilesScreen` — full per-category list.
- `scanned_file_tile.dart` — name, date, folder, size, and a details sheet
  showing type, size, modified date, and location.
- `core/utils/byte_formatter.dart` — shared B/KB/MB/GB/TB formatting.

## Automated tests

`test/file_scanner_test.dart` covers model parsing (including malformed and
partial rows), category fallback, result aggregation and ordering, repository
mapping/de-duplication/option forwarding/error propagation, byte formatting,
and three widget tests for the overview, category detail, and empty states.

Run with `flutter test`.

## Device acceptance test

1. Install on a real Android phone that has photos, videos, music, documents,
   and downloads.
2. Grant media/storage access when prompted (Home → Quick Tools → Permissions
   if it was skipped earlier).
3. Open the **Files** tab. The scan should complete and show non-zero counts
   for every category that exists on the device.
4. Compare a few entries against a file manager: name, size, and modified date
   should match, and the details sheet should show the real path.
5. Tap a category to confirm the full list opens, sorted largest first.
6. Add a new file (take a photo or download something), pull to refresh, and
   confirm it appears.
7. Revoke storage permission in Android Settings, reopen Files, and confirm the
   permission error state appears with a working "Review permissions" button.

## Notes and limits

- Files outside MediaStore's indexed shared storage (other apps' private data,
  `/Android/data`) are not visible without additional, more invasive
  permissions. That is intentional for a least-privilege cleaner.
- On Android 14+, "Select photos and videos" limited access returns only the
  user-selected items — expect lower counts, not an error.
- Results are capped per category; `truncated` is surfaced in the UI.

## Next phase hooks

`FileScanRequest(minSizeBytes:)` already backs a Large Files view, and
`ScannedFile.uri` is the handle later phases will use for preview and deletion.
