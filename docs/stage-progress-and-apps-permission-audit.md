# Stage-based real progress and Apps permission audit

## Delivery status

Implemented locally on top of `baf9348e3b4eb5cc076ccd1cd75fe2b0cf372d51`. **No commit or push performed for this task. Version remains `1.0.1+2`.**

This report supersedes the previous report's operation-wide ring policy: a real stage can now reach 360 degrees without declaring the parent scan successful.

## Progress behavior

### Authentic stages, not an overall estimate

- `ScanStage` holds a stable identity, label, actual completed count, optional reliable total, units and stage outcome. Its fraction is completed / total, independent of any composite-operation flag.
- Native identity is request ID + increasing stage index. A new worklist, label, or count reset creates a new stage generation; repeating a human-readable label does not reuse the previous generation.
- Within a stage, decreasing counts, contradictory known totals and label changes without a generation change are rejected. A previously unknown denominator can become known when the scanner obtains a reliable total.
- Native events require an owned, active request, an increasing sequence, a non-regressing stage index and valid counters. Closed requests, cancelled/finished operations and old generations cannot update the ring.
- The deprecated-in-purpose `numeric` call-site/wire hint remains for compatibility; it no longer disables measured stages inside composite scans or authorizes an overall percentage.
- Current-stage counts and labels are selected together. Percent semantics explicitly say **Current stage progress**.

The ring still starts at 12 o'clock, fills clockwise, retains its completed arc within a stage and places the orange marker at the leading edge. The existing bounded 240 ms interpolation never advances beyond confirmed work. A genuine selected-stage identity change resets the arc; an ordinary count update does not.

A fraction of one fills the **stage** ring while retaining the folder and four moving icons. Only the dedicated parent-success completion transition authorizes its final checkmark. Child completion, partial results, failure, cancellation and presentation timers do not authorize that checkmark. Generic loading views ignore terminal snapshots rather than replaying a cached provider's completion during refresh.

### Measurable versus unknown work

| Work | Honest denominator / display |
| --- | --- |
| MediaStore category discovery | Cursor row count when the returned cursor respects the requested bound. Each category cursor is its own stage, including within multi-category scans. |
| Exact file hashing | Actual submitted, capped native batch length; actual files attempted/checked. Label explicitly says **current batch**. |
| Photo fingerprinting | Actual submitted, capped native batch length; actual files checked. Label explicitly says **current batch**. |
| Installed-app metadata processing | Deduplicated launcher-package worklist length after launcher discovery. Counter advances for each package attempted, including unavailable packages. |
| Photo-quality measurements | Actual native photo-batch length and photos checked; now uses the same request/envelope transport. Optional quality enrichment still does not block the similar-photo results list, and no new loading screen or navigation wait was added. |
| SAF directory discovery and legacy folder traversal | Actual visited counts, unknown overall total: indeterminate ring, no percentage. |
| Initial launcher/query discovery | Unknown until Android returns the worklist/cursor: indeterminate. |
| Flutter comparison/grouping and final aggregation | No reliable incremental telemetry added to the matching algorithms: stage/activity remains indeterminate rather than assigning a guessed percentage. Very short synchronous work may never occupy a rendered frame. |
| Cached hashes/fingerprints/quality/provider results | Results reused as before; no manufactured native progress or completed-stage replay. |

Hash, fingerprint and quality batches are distinct worklists, not an estimate of all remaining batches or the entire library. Counts mean **checked/attempted**, not successfully hashed, matched or reclaimable. Existing batch caps, candidates, caches, matching/scoring algorithms and result payloads are preserved.

### Concurrency, boundaries and visual pacing

1. Sources are ordered by their explicit attachment/request registration order, not by which branch produces callbacks fastest.
2. The earliest active source stays selected until it finishes. Other active branches retain their latest actual stage in the background; their labels/counts cannot overwrite the selected branch's fraction.
3. When the selected source finishes, the next active registered source is selected. A branch that has already finished is skipped, not replayed as new work. Parent failure/partial status still propagates even from undisplayed or cached branches.
4. Terminal cached children propagate outcome only, never a completed arc. Parent success still depends on the parent action and all its awaited work, not on the displayed child's fraction.
5. Native sampling remains 80 ms. Boundary events flush the last real counters even when normal sampling suppressed them. Stage boundaries are preserved separately in a bounded queue (at most 16 pending stage entries, one posted runnable). Very fast undisplayed stages may be skipped, not synthesized later.
6. The terminal result envelope carries the last real stage too, so a MethodChannel result resolving before a queued progress notification cannot lose the final count.
7. `ScanStagePresentation` coalesces stage changes for 240 ms, displaying the old label/count/ring atomically until the latest real stage is selected. It does not queue animations for every fast intermediate stage, generate work, change fractions, delay scanners or delay navigation. A new scan or parent terminal state bypasses this coalescing.
8. The status card no longer cross-fades on every changed counter string.

The four-icon movement/drawing and painter tail were compared byte-for-byte with HEAD and are unchanged. Folder/icon design, colors, dimensions, silent behavior and the 5800 ms motion duration remain unchanged. Existing scan-screen navigation/completion timing gates are preserved and never contribute progress.

## Apps authorization audit

### Why Apps can work after denying storage/photos

`InstalledAppsBridge` asks PackageManager for `ACTION_MAIN` + `CATEGORY_LAUNCHER` activities, deduplicates package names and excludes this cleaner's own package. It does **not** request a complete installed-package inventory. The default Dart filter additionally hides system apps.

The existing manifest declares a matching launcher intent inside `<queries>`. On Android 11+ this provides intent-scoped package visibility; older versions have broader package visibility rules, but this implementation still deliberately queries launcher entries only. Work profiles, disabled/non-launcher packages and OEM visibility rules can make the list differ from Settings.

For those visible packages it reads:

- Package ID and launcher display label/icon, using PackageManager/ApplicationInfo resources.
- System/updated-system flags and whether a launcher intent exists.
- Version name/code, first-install date and last-update date, using PackageInfo.
- Base and split APK file lengths from `sourceDir` / `splitSourceDirs`, using file metadata (`isFile` / `length`), not private app-data traversal or APK-content scanning.

These are package metadata APIs and accessible APK metadata, not shared-photo/storage reads. No runtime storage or photo permission is required just to show this inventory. If APK metadata cannot be read, existing zero/partial fallback behavior remains; it does not justify bypassing filesystem permissions.

**No storage gate was added to Apps. No permission or manifest declaration was added.** In particular, there is no `QUERY_ALL_PACKAGES` permission or all-files permission. The existing `REQUEST_DELETE_PACKAGES` declaration supports a handoff to Android's uninstall confirmation, not silent uninstallation.

### Optional Usage Access

The only extra information obtained with optional Usage Access here is aggregate code/data/cache byte counts, via `StorageStatsManager.queryStatsForPackage` for the current user. This code does not query usage events/history, last-used times, private app files, or offer another app's cache deletion.

- Android below API 26: detailed size API unavailable; report APK-only sizes.
- API 26+: acquire StorageStatsManager only when AppOps says access is authorized. Check again before every cross-package stats query.
- Existing AppOps logic uses `checkOpNoThrow` on API 26–28 and `unsafeCheckOpNoThrow` on API 29+, with the existing MODE_DEFAULT permission fallback. Denied/errored modes and lookup failures fail closed.
- Android itself enforces authorization on the stats query. Permission revocation between the check and query can still race; exceptions are caught and that package stays APK-only.
- Recheck immediately before delivering the inventory. If access was revoked, remove detailed size fields from every returned row and report access unavailable.
- Dart parsing also discards detailed fields when authorization is absent/false or the detailed-size API is unsupported. The inventory provider applies the same safeguard even to cached/custom repository snapshots.
- Apps checks on initial display and foreground resume. While a foreground check is pending, cached detailed sizes are hidden. Grant/revoke changes invalidate the native inventory. Open details observe the refreshed inventory/authorization instead of permanently displaying the original app snapshot. Older asynchronous authorization checks cannot overwrite a newer check.

The existing optional special-access declaration does not itself grant access, and no new settings prompt/card or runtime permission request was added.

### Defects found and fixed

1. **Cache counted twice:** Android `StorageStats.getDataBytes()` already includes cached data. `InstalledApp.totalBytes` previously added cache again. The correct measured total is now **appBytes + dataBytes**; cache remains separately available as a subset, and the details row says **Data (includes cache)**. This intentionally corrects Apps footprint/sorting figures, not duplicate/reclaimable-file algorithms.
2. **Misleading coverage:** the summary previously used the Usage Access boolean alone to claim full app space, even if individual queries failed. It now distinguishes complete coverage of the listed apps, mixed/partial known size, and APK-only size. Individual rows explicitly say **Total** or **APK only**.
3. **Overly absolute visibility explanation:** the note now describes this feature's launcher-only, system-hidden-by-default scope instead of claiming Android universally permits only launcher apps.
4. **Stale/contradictory authorization presentation:** native delivery, Dart payloads, cached inventory and open details now fail closed/revalidate as described above.

**No evidence of an existing storage/photo authorization bypass was found in the Apps enumeration path.** The defects concerned optional-size authorization freshness and misleading size/scope presentation. A storage denial does not grant any additional media, SAF tree, broad filesystem or private app-data access. Existing scoped MediaStore visibility and previously granted SAF trees remain separate capabilities; denying photos is not a revocation of an independently granted SAF tree. Central permission policy, SAF rules and media/deletion authorization code are unchanged.

### Android reference checks

- [Package visibility declarations](https://developer.android.com/training/package-visibility/declaring): Android 11+ visibility filtering and intent-scoped `<queries>` declarations.
- [StorageStatsManager.queryStatsForPackage](https://developer.android.com/reference/android/app/usage/StorageStatsManager#queryStatsForPackage(java.util.UUID,%20java.lang.String,%20android.os.UserHandle)): API 26+, cross-package stats require Usage Access, worker-thread operation.
- [StorageStats.getDataBytes](https://developer.android.com/reference/android/app/usage/StorageStats#getDataBytes()): data includes cache/code-cache and applicable external data/cache locations, explaining the double-counting correction.

This is a code/permission audit, not a guarantee of Google Play approval. Existing declarations and package-data handling still need normal release-policy review; no new broad visibility or sensitive permission was introduced.

## Verification on final code

| Check | Result |
| --- | --- |
| Flutter full suite, sequential | **799 passed, 0 failed**, exit 0. Final run: `flutter test --no-pub --concurrency=1 --reporter expanded`. |
| New task regression coverage | **24 additional tests** over the 775-test baseline: 16 stage/transport/presentation tests and 8 Apps access/size tests. Existing operation/pipeline assertions intentionally updated for stage-360 semantics. |
| Native progress contract | **43 assertions passed**, exit 0: counts, stage boundary flush, increasing identity/sequence, repeated labels, terminal envelope, bounded coalescing and terminal immutability, plus prior cancellation/partial/result tests. |
| All application Kotlin sources | Standalone compile **passed**, JVM target 17, using Android API/Flutter embedding/AndroidX compile jars; two existing API-deprecation warnings. Not a Gradle build. |
| Flutter analyzer | **0 errors**, 103 material-library deprecation infos and 1 existing missing `assets/icons/` directory warning; exit 1, not claimed clean. |
| APK / AAB | Both attempted; **blocked by missing Android SDK**, exit 1. No release artifact produced. |
| `git diff --check` | Passed. |
| Preservation checks | Version, original lock, manifest, all central permission/router implementation files and duplicate/similar/scoring algorithms unchanged. Four-icon motion/drawing unchanged byte-for-byte. |
| Git | HEAD remains `baf9348e3b4eb5cc076ccd1cd75fe2b0cf372d51`; no new commit or push. |

Verification used Flutter 3.50.0 / Dart 3.14.0 and Kotlin 2.2.0 / JDK 17. Flutter dependency setup resolved seven SDK/transitive versions for that SDK. The original tracked `pubspec.lock` was restored unchanged; final `--no-pub` tests used the resolved package configuration. The original exact lock resolution was not separately retested under a matching older Flutter SDK. No dependency was added to the app.

Detailed final logs are in `/home/user/stage-baseline/`: `full-suite-final.log`, `analyze-final.log`, `kotlin-final.log`, `native-final.log`, `apk.log`, `aab.log`. Temporary toolchains are outside the repository.

### Remaining device/build QA

No physical-device/emulator validation was performed. Injected transport tests and compilation do not execute Android AppOps, PackageManager or MediaStore behavior on a real device. Verify:

- API 25/26/28/29/30/33/34+ launcher visibility, system-app filtering, missing packages and split APK sizes.
- Usage Access absent/granted/revoked during inventory, foreground/resume, open details, query failures and managed profiles.
- Multi-category MediaStore cursors, empty/unknown totals, SAF/cloud/removable traversal, long hash/fingerprint/quality batches, partial/unreadable results and cache reuse.
- Concurrent photo/Smart Scan branches, repeated scans, cancellation/back/background/resume, reduced motion and stage transitions on real displays.
- Release APK/AAB under the actual SDK 37 compile/SDK 36 target configuration, Gradle toolchain and existing signing setup.

## Files created or modified

The exact task file list is appended below. Existing documentation from the previous implementation is historical and was not rewritten.

```text
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/FileHashBridge.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/InstalledAppsBridge.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/MainActivity.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/PerceptualHashBridge.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/PhotoQualityBridge.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/ScanProgressBridge.kt
docs/stage-progress-and-apps-permission-audit.md
lib/core/scanning/scan_progress.dart
lib/core/ui/circular_file_scanner.dart
lib/core/ui/scan_stage_presentation.dart
lib/features/apps/data/installed_apps_repository.dart
lib/features/apps/domain/installed_app.dart
lib/features/apps/presentation/providers/installed_apps_provider.dart
lib/features/apps/presentation/screens/app_details_screen.dart
lib/features/apps/presentation/screens/apps_screen.dart
lib/features/cleaner/presentation/screens/scan_progress_screen.dart
lib/features/files/data/photo_quality_repository.dart
lib/features/files/presentation/providers/best_photo_provider.dart
lib/features/files/presentation/widgets/photo_tool_ui.dart
test/apps_analyzer_test.dart
test/native/ScanProgressContract.kt
test/real_scan_progress_test.dart
test/scan_progress_pipeline_test.dart
test/stage_scan_progress_test.dart
```
