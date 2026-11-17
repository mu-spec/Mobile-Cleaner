# Real circular scanning progress and version 1.0.1+2

## Delivery status

Implemented locally on top of `1ec0be26a47a25f22e582b09e78c0fda6957e643`. **Not committed or pushed.** The pre-implementation audit is in `real-scanning-progress-audit.md`; the user approved its architectural scope before implementation.

- Full Flutter regression suite: **775 passed, 0 failed**.
- Native progress contract: **26 assertions passed**.
- All Android Kotlin sources: standalone Kotlin compile check **passed**.
- Flutter analyzer: **0 errors**, 94 deprecation infos and one existing missing-asset-directory warning; exit status 1, not claimed clean.
- Release APK and AAB: both attempted, both **blocked by missing Android SDK**. No release artifact produced.
- Version: **1.0.0+1 → 1.0.1+2**.

## Root cause

The previous circular painter used its decorative 5800 ms controller to rotate a fixed-length blue arc whenever `progress` was null. Although the widget accepted measured progress, native scanners returned only final method-call results, so callers had no incremental values to supply.

Discovery, hashing, comparison and aggregation are separate operations. Treating the end of discovery, a completed hash batch, or a presentation timer as overall completion would be inaccurate. Several operations also do not have a stable total before discovery finishes.

## Native changes

### Request-scoped reporting

New `ScanProgressBridge.kt` multiplexes progress over a MethodChannel using a unique `progressId`/`requestId` for each child request. Events carry:

- current stage;
- number of work units actually checked;
- nullable stage total;
- whether the native request has a trustworthy single-worklist numeric denominator;
- unit label, such as rows checked, documents checked, files checked or apps checked;
- running, succeeded, failed, cancelled or partial outcome.

Progress notifications are throttled to an 80 ms minimum sampling interval per request. At most one pending delivery runnable per request coalesces updates. Terminal state replaces a pending intermediate sample. Scanning does not wait for Dart acknowledgements.

A result envelope, used only for requests carrying progress IDs, also carries terminal outcome. Flutter unwraps the original payload unchanged. This means a terminal event lost to disposal or channel timing cannot turn an unreadable/partial operation into an apparent success.

### Execution and actual counters

- **MediaStore:** discovery now runs on a single worker executor rather than the platform/UI thread. Existing query arguments, ordering, filters, caps, metadata conversion, merges and result calculations are retained. For a single images/video/audio worklist, an already-open cursor's count can provide a metadata-row denominator. If a provider returns a count exceeding the requested bound, numeric progress is not used. Counts advance after checking a row, including legitimate rejected/invalid rows—not before processing it.
- **SAF:** existing breadth-first traversal reports documents checked with an unknown total. There is no preliminary counting traversal. Security failures, null/unavailable cursors, broken grants and uncompleted traversal safety bounds prevent successful full-circle status, while existing safe partial results are retained.
- **Legacy Downloads traversal:** reports directories checked without inventing an eligible-file total. Adds cooperative cancellation checks and incomplete-source reporting without changing filtering or file selection.
- **Exact hashes:** reports completed file-processing attempts after streaming/digest processing returns. Existing SHA-256, buffer size, chunk caps and omission of unreadable files remain. Checks cancellation between files and stream reads.
- **Perceptual hashes:** reports completed image-processing attempts after decode/fingerprint processing returns. Existing downsampling, dHash/aHash math, caps and unreadable-image omission remain. Cancellation is cooperative between processing boundaries; an individual bitmap decode may not be immediately interruptible.
- **Installed Apps:** forms the unique, non-self launcher package worklist from the existing enumeration, without a second PackageManager scan. Progress advances after metadata, optional statistics and requested icon processing for each package. Existing results, ordering and optional-statistics fallback remain intact.
- **MainActivity:** owns/disposes the progress transport and file discovery executor with the other native bridges.

### What the counters mean

A MediaStore row is not necessarily a distinct eligible file: categories overlap, rows can be filtered, and existing query/traversal caps intentionally bound discovery. Consequently the UI says **rows checked**, not “all device files processed.” Hash counters describe the current batch, not a whole duplicate scan. Missing or inaccessible files are never counted as having been successfully hashed. An unreadable-file outcome retains existing safe results but prevents the complete operation from receiving successful 100% status.

No extra storage permission, all-files access request, SAF grant or package was introduced.

## Flutter operation coordination

New `lib/core/scanning/scan_progress.dart` provides request-scoped snapshots, operation lifetimes, a registry/stream per module and ambient operation context through Dart zones.

- Native channel calls register request IDs only while owned by an active operation; closed or unknown IDs are ignored.
- New generations start with fresh state. Old progress cannot overwrite the current registry generation.
- Provider scopes cover both discovery and required derived analysis. Parents follow required child operations, including cached/in-flight provider dependencies.
- A child reaching its total or completing successfully does **not** complete its parent. The full parent Future, including required parsing, grouping, aggregation and recommendation computation, must resolve successfully.
- Required child failures, cancellation or partial terminal envelopes prevent a successful full circle even when an existing repository intentionally returns safe fallback/partial data.
- Single-worklist operations may consume confirmed numeric samples. Composite operations do not average child percentages or assign artificial stage weights.
- Native samples reporting processed == total do not independently authorize 100%. Until the entire required operation succeeds, the ring retains its last confirmed intermediate sample. This is a terminal-success gate, not an arbitrary 90/95/99% cap.
- Invalid counters and mismatched/stale request IDs are rejected. Lower callbacks cannot rewind the displayed fill.

The existing public repository and channel interfaces remain usable by existing fakes/consumers. Their result types, scan filters and duplicate algorithms are preserved.

## Circular visual behavior

- A new scan starts with zero blue sweep and the orange marker at twelve o'clock.
- Blue sweep starts at `-π/2` and fills clockwise from zero toward `2π`.
- The blue line has no decorative rotation and retains completed portions.
- A separate 240 ms ease-out interpolation moves only toward the latest confirmed value; it never overshoots it. Reduced-motion/inactive views use confirmed values without decorative interpolation.
- Blue sweep end caps stay inside the exact confirmed angle, avoiding a round-cap overlap that could make a nearly complete ring look complete prematurely. The orange leading marker preserves the soft tip.
- The marker follows the blue leading edge.
- Unknown totals leave the ring unfilled/indeterminate, with the existing moving internal icons indicating activity. No timer or decorative rotating arc substitutes for a percentage.
- Exactly 360° is authorized only by successful completion of the entire required operation. Failure, partial/unavailable data and cancellation never authorize it.
- The existing checkmark/completion transition remains separate from the success of actual work.

### Internal artwork preserved

The internal four-icon motion block and vector icon drawing were compared byte-for-byte against their pre-task copies and remain unchanged. The 5800 ms duration, easing, paths, fading, folder artwork, icon size, colors, track width and scanner dimensions remain. Rendering is silent; no audio code or sound package exists in this change.

## Module coverage and honest limitations

| Module | Numeric overall progress while running? | Behavior |
|---|---|---|
| Screenshots | **Supported when the single image cursor has a reliable bounded count** | Counts actual metadata rows checked; the operation waits for required screenshot summary processing before successful completion. Discovery before a count exists is indeterminate. |
| Large Photos | **Supported under the same single-cursor condition** | Existing size filter and summary are unchanged. |
| Videos / Large Videos | **Supported under the same single-cursor condition** | Existing video discovery and summary/sort are retained. |
| Installed Apps | **Supported after the unique launcher worklist is known** | Counts checked apps through required metadata/icon processing and Flutter snapshot/inventory processing. Not a count of every installed/system package. |
| Files Cleaner / Files | **Indeterminate overall** | Authorized category counts/stages are reported, but mixed MediaStore/SAF/fallback work has no reliable combined denominator. |
| Large Files | **Indeterminate overall** | Same mixed-source limitation; existing thresholds and totals are unchanged. |
| Downloads Cleaner | **Indeterminate overall** | SAF or legacy traversal may have an unknown matching total. Stage counts are still reported. |
| APK Cleaner | **Indeterminate overall** | Overlapping APK/Downloads/Documents sources and optional SAF prevent a reliable combined total. |
| Duplicate Files | **Indeterminate overall** | Reports discovery and real hash-batch counts, then comparison stage. Does not present hashing completion as whole-operation completion. |
| Duplicate Photos | **Indeterminate overall** | Same requirement to include discovery, size candidates, hashing and final exact grouping. |
| Similar Photos | **Indeterminate overall** | Reports discovery/fingerprint counts and comparison stage. Leader-based comparison work depends on groups formed; no pair denominator is fabricated. |
| Photos Cleaner dashboard | **Indeterminate overall** | Waits for all existing photo branches and combined summary. No equal/arbitrary branch weights. |
| Smart Scan | **Indeterminate overall** | Waits for all existing authorized discovery/analyzer branches and required recommendation calculation. No individual category or hash fraction is represented as the overall percentage. |

All operations above may reach a complete circle only after their entire required operation succeeds. For indeterminate composite scans, the ring legitimately moves from unknown/zero sweep to successful completion; it does not manufacture intermediate percentages.

Similar Photos' existing optional best-photo quality suggestions remain a separate derived activity after similarity groups are available. They are not newly included in the base scan completion claim or silently counted as completed work. Their existing analysis/ranking logic is untouched.

A fast scan may finish before a throttled intermediate notification is delivered. It can correctly show no intermediate percentage rather than an artificial animation through made-up samples.

## Lifecycle, sharing and cancellation

- A screen owns its presentation operation, not every cached Future it watches. Leaving the screen cancels/detaches that presentation scope, stops its animation subscription and prevents later navigation. It does not abort shared provider-owned work needed by another consumer.
- Invalidating or disposing the owning provider requests cancellation of its native requests. Native checks cancellation cooperatively and closes streams/cursors through existing use/finally scopes.
- Existing non-auto-disposed provider caching is preserved: leaving a tool can allow its cached work to finish. This is intentional, not a claim that Back instantly stops all disk I/O.
- Backgrounding pauses widget tickers. Native work may continue; snapshots retain the latest state. Foreground rendering catches up to confirmed work, without elapsed-time progress.
- Cancellation cannot immediately interrupt every blocked content-provider call or image decoder. Native terminal results are still ignored by a disposed/cancelled presentation generation.
- Empty scans complete only when their required operation succeeds. Errors, permission revocation, partial grants and inaccessible sources do not trigger automatic prompts or a success circle.
- Safe partial results and existing result navigation are preserved; partial completion is not labeled successful 100%.

## Permissions, results and presentation timing

The centralized permission gateway, manager, snapshots, policy, router and manifest were checksum/diff checked and remain unchanged. `PermissionAwareFileScannerRepository` is unchanged. Native requests are instrumented only after that wrapper filters unauthorized media categories, so denied categories are not included in native work counts. Limited visual access remains limited; SAF stays inside granted trees.

Duplicate matching/hash math, deletion/uninstall algorithms, cleanup recommendations, storage/result arithmetic, themes, application ID, release-signing configuration and result navigation remain unchanged.

The existing **2800 / 650 / 420 ms** presentation gates are retained and tested. Actual scanning runs concurrently with the minimum gate. Timers never determine or advance progress. A genuinely fast successful scan can reach the full ring during the minimum presentation interval without navigating early.

## Version

| Field | Before | After |
|---|---|---|
| Flutter version | 1.0.0+1 | **1.0.1+2** |
| Android versionName input | 1.0.0 | **1.0.1** |
| Android versionCode input | 1 | **2** |

`android/app/build.gradle.kts` still uses `flutter.versionName` and `flutter.versionCode`. Application ID remains `com.KoreAppsTek.PhoneStorageCleaner`. No signing settings changed.

The update follows the user's explicit instruction to assume no code higher than the supplied testing AAB's code 1 has been uploaded. Google Play upload history was **not independently verified**. No built artifact is available here to inspect final packaged metadata because release builds are blocked.

## Verification actually performed

Environment: Flutter 3.50.0 / Dart 3.14.0, Linux. Checks were run sequentially where necessary because concurrent analyzer/compiler/test work exceeded this workspace's practical memory budget; an earlier incomplete concurrent suite run was stopped and is not counted as a successful run.

| Command/check | Actual result |
|---|---|
| `flutter pub get` | **Succeeded**, exit 0. No new dependency declared. |
| `flutter analyze` | **0 errors**, 95 diagnostics: 94 `material.dart` deprecation infos and 1 existing `assets/icons/` missing-directory warning. Exit 1 due to diagnostics. |
| `flutter test --concurrency=1 --reporter expanded` | **775 passed, 0 failed**, exit 0, on the final application code. Includes existing permissions, cleanup, deletion, duplicates, recommendations, storage, widgets and scan-lifecycle tests. |
| New Dart progress tests | **24 new tests** across `real_scan_progress_test.dart` and `scan_progress_pipeline_test.dart`; includes actual mocked native channel → permission-aware repository → summary → parent-operation integration. |
| Standalone native contract | **26 assertions passed**, exit 0. Tests injected-clock throttling/coalescing, exact counters, unknown totals, partial/failure/cancellation state, result preservation and legacy no-progress requests. |
| Standalone Kotlin compile | **Passed**, exit 0, for every application Kotlin source with JVM target 17 against Android API, Flutter embedding and required AndroidX compile jars. Two existing Android API deprecation warnings. This is not a Gradle/Android release build. |
| `git diff --check` | **Passed**, exit 0. |
| `flutter build apk --release --target-platform android-arm64` | **Attempted; blocked**, exit 1: `No Android SDK found`. |
| `flutter build appbundle --release` | **Attempted; blocked**, exit 1: `No Android SDK found`. |
| Protected permissions/router/manifest | Unchanged checksums/diffs. |
| Internal four-icon movement/drawing | Byte-for-byte comparison passed. |
| Git commit/push | **Not performed**. |

The new Flutter SDK resolved seven SDK/transitive versions during dependency setup. Verification used that resolved configuration. The original tracked `pubspec.lock` was restored after verification to avoid an unrelated dependency upgrade. Its original exact dependency resolution was not separately retested under a matching older Flutter SDK. Temporary compiler/API jars are verification tools outside the repository, not new app dependencies.

### Remaining device/release QA

No physical device/emulator run was performed. Standalone Kotlin compilation and injected-clock tests do not prove Android content-provider runtime behavior. Required QA includes:

- Real MediaStore cursor counts and query limits across Android 7–16/OEM providers.
- Selected-photo access and revocation during metadata queries/hashing.
- SAF local/cloud/removable providers, overlapping trees, revoked grants and traversal bounds.
- Large files, slow streams, unreadable images, cache reuse and repeated/concurrent scans.
- Back/disposal, provider invalidation, process/activity recreation, background/resume and delayed native messages.
- Visual smoothness and accessibility on real devices, including reduced motion.
- Release APK/AAB build with the project's actual Android SDK, supported JDK/Gradle toolchain and existing release signing materials.
- Inspect packaged versionName/versionCode and confirm Play code availability before upload.

## Files created and modified

The exact task file list follows. Permission-management implementation files, native deletion/security bridges, domain matching/calculation algorithms, Android manifest and signing/build configuration are not modified.

```text
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/FileHashBridge.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/FileScannerBridge.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/InstalledAppsBridge.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/MainActivity.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/PerceptualHashBridge.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/SafDocumentScanner.kt
android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/ScanProgressBridge.kt
docs/real-scanning-progress-audit.md
docs/real-scanning-progress.md
lib/core/scanning/scan_progress.dart
lib/core/ui/circular_file_scanner.dart
lib/features/apps/data/installed_apps_repository.dart
lib/features/apps/presentation/providers/installed_apps_provider.dart
lib/features/apps/presentation/screens/apps_screen.dart
lib/features/cleaner/presentation/screens/clean_screen.dart
lib/features/cleaner/presentation/screens/scan_progress_screen.dart
lib/features/files/data/file_hash_repository.dart
lib/features/files/data/file_scanner_channel.dart
lib/features/files/data/perceptual_hash_repository.dart
lib/features/files/presentation/providers/apk_provider.dart
lib/features/files/presentation/providers/best_photo_provider.dart
lib/features/files/presentation/providers/downloads_provider.dart
lib/features/files/presentation/providers/duplicates_provider.dart
lib/features/files/presentation/providers/file_scan_provider.dart
lib/features/files/presentation/providers/large_files_provider.dart
lib/features/files/presentation/providers/large_photos_provider.dart
lib/features/files/presentation/providers/photo_cleanup_provider.dart
lib/features/files/presentation/providers/photo_duplicates_provider.dart
lib/features/files/presentation/providers/screenshot_provider.dart
lib/features/files/presentation/providers/similar_photos_provider.dart
lib/features/files/presentation/providers/smart_scan_provider.dart
lib/features/files/presentation/providers/videos_provider.dart
lib/features/files/presentation/screens/apk_cleaner_screen.dart
lib/features/files/presentation/screens/category_files_screen.dart
lib/features/files/presentation/screens/downloads_cleaner_screen.dart
lib/features/files/presentation/screens/duplicates_screen.dart
lib/features/files/presentation/screens/files_screen.dart
lib/features/files/presentation/screens/large_files_screen.dart
lib/features/files/presentation/screens/large_photos_screen.dart
lib/features/files/presentation/screens/photo_duplicates_screen.dart
lib/features/files/presentation/screens/screenshot_cleaner_screen.dart
lib/features/files/presentation/screens/similar_photos_screen.dart
lib/features/files/presentation/screens/videos_screen.dart
lib/features/files/presentation/widgets/files_status_views.dart
lib/features/files/presentation/widgets/photo_tool_ui.dart
lib/features/photos/presentation/screens/photos_screen.dart
pubspec.yaml
test/circular_file_scanner_test.dart
test/native/ScanProgressContract.kt
test/real_scan_progress_test.dart
test/scan_progress_pipeline_test.dart
test/widget_test.dart
```
