# Phase 14 — Smart Scan

## Goal

Combine the existing tools into one pass that checks:

- **Large files**
- **Old downloads**
- **APK installers**

Smart Scan now lives on the **Clean** tab, replacing the placeholder that had
been there since Phase 1. Home's "Smart Scan" button already pointed here.

## Implemented

### Composed, not duplicated

`smartScanProvider` is built from the three existing tool providers —
`largeFileSummaryProvider`, `downloadsSummaryProvider`, `apkSummaryProvider` —
at their default thresholds (100 MB+, 30+ days, all installers).

Two consequences, both deliberate:

- Smart Scan and the individual tools **cannot disagree**, because they read
  the same providers.
- Opening a tool after a scan **reuses the cached result** instead of
  rescanning, since Riverpod already holds it.

The three scans are started before any is awaited, so the wait is the slowest
scan rather than the sum of all three. A scan therefore costs exactly three
device passes — one per tool — verified by a test.

### Overlap is the interesting problem

One file can satisfy all three checks: a 500 MB installer downloaded a year
ago is a large file, an old download, **and** an APK.

`SmartScanResult` handles this honestly:

- **Each group lists the file.** Hiding it from a category the user is
  browsing would be confusing — it really is an old download.
- **The headline counts it once.** `uniqueFiles` and `totalBytes` de-duplicate
  by URI, so "could be recovered" is a figure the device can actually deliver.

With the test fixture the group totals sum to 2.3 GB while the true recoverable
figure is 1.3 GB. Naively adding group totals would overstate it by a gigabyte.

When an overlap exists the screen says so, so a user comparing the headline
against the group rows is not left confused by arithmetic that seems wrong.

### Screen

Laid out as the phase spec describes:

```
Potentially Recoverable
1.3 GB
across 4 files

Large Files        1.3 GB
Old Downloads    502.0 MB
APK Installers   520.0 MB

[ Review Cleanup ]
```

- A **Potentially Recoverable** panel: the headline total, the distinct file
  count, then one row per check showing its label and size.
- **Review Cleanup** opens whichever check holds the most space.
- **Empty checks stay visible**, showing `None`, but are not tappable — there
  is nothing to review, and hiding them would make the scan look incomplete.
- The five biggest items across all checks, using the Phase 8 tile.
- Tapping a row opens that check's existing tool.
- Pull-to-refresh and a rescan action invalidate all three underlying scans.

### Deletion stays where it is

Smart Scan reports and routes; it does not delete. Removal still happens in the
tool that owns each category, so the Phase 12 delete path remains the single
place files are removed. Adding a second delete entry point here would risk the
two drifting apart.

## Automated tests

`test/smart_scan_test.dart`:

**Domain** — the three checks exist with the right labels; each finding is
grouped under the correct check; a file matched by several checks is counted
once; the headline is provably smaller than the summed group totals; no
overlap is reported when checks find different files; unique files are ordered
largest first; non-empty groups rank by size; an all-clear device yields an
empty result; a missing group still resolves.

**Screen** — the "Potentially Recoverable" heading; each check listed with its
label and size; **Review Cleanup** present and enabled, and absent from the
clean state; a row per check; the combined total (1.3 GB across 4 files); the
overlap note; **exactly three scans**, no extra pass for the combined view; the
biggest items listed once; the clean state; an empty check is shown as `None`
and is not tappable.

Two assertions in `widget_test.dart` were updated, since the Clean tab now
renders Smart Scan rather than the placeholder.

## Device acceptance test

1. Open the **Clean** tab, or tap Smart Scan on Home.
2. Confirm the **Potentially Recoverable** panel lists Large Files, Old
   Downloads, and APK Installers with plausible sizes, and that the headline
   total is at least as large as the biggest single row.
3. If a file matches several checks — an old, large `.apk` is the easy case —
   confirm it appears in each relevant group and that the overlap note shows.
4. Tap each row and confirm it opens the matching tool with the same figures.
   Tap **Review Cleanup** and confirm it opens the largest check.
5. Delete something from a tool, return to Smart Scan, and pull to refresh; the
   totals should drop.
6. On a tidy device, confirm the "Nothing to clean" state.

## Notes and limits

- Smart Scan uses each tool's **default** threshold. Choosing 1 GB+ inside
  Large Files does not change what Smart Scan reports; it always reflects
  100 MB+, 30+ days, and all installers.
- Group totals intentionally do not sum to the headline whenever files overlap.
- The same scoped-storage limits apply as elsewhere: on Android 10+, files
  other apps saved are only visible once a folder has been granted through SAF.

## Next phase hooks

`SmartScanResult.uniqueFiles` is already de-duplicated and size-ordered, so a
future "clean everything" action could feed it straight into `runDeleteFlow`
without any new selection logic.
