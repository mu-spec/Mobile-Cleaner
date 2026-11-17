# Real scanning progress — pre-implementation audit

Date: 2026-11-16
Baseline: commit `1ec0be26a47a25f22e582b09e78c0fda6957e643`.
Status at creation: pre-implementation audit. The user subsequently approved this scope and authorized 1.0.1+2 on the assumption that no higher code has been uploaded. See real-scanning-progress.md for the implementation and actual verification results. No commit or push is authorized for this task.

## 1. Root cause

`lib/core/ui/circular_file_scanner.dart` already accepts a nullable progress fraction, but callers do not supply measured progress. Its painter uses the 5800 ms decorative controller to rotate a fixed 0.24-circle arc when progress is null. Thus the existing blue line indicates activity, not completed work.

`ScanProgressScreen` explicitly uses indeterminate mode because the existing platform interfaces return one final result. Its 2800 ms minimum presentation gate, 650 ms completion transition and 420 ms result-navigation delay are presentation-only. Those durations must not become progress denominators.

The four tiny internal file icons share the decorative controller. Their 5800 ms motion, easing, paths, fading and vector artwork can be preserved independently of the ring. No audio API is involved.

## 2. Native pipeline

### MediaStore and filesystem discovery

Files:

- `android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/MainActivity.kt`
- `FileScannerBridge.kt`
- `SafDocumentScanner.kt`
- `SafAccessBridge.kt`

`MainActivity` registers a normal MethodChannel handler for file scanning. `FileScannerBridge.onMethodCall` performs the query/scan synchronously rather than scheduling it on an executor. Emitting progress from this loop without moving work off the platform thread would not provide dependable live delivery or smooth UI interaction.

Each requested category is queried in turn. MediaStore rows are converted to maps, then non-media rows may be merged with SAF traversal. Sorting, per-category limits, name/size de-duplication and the existing truncated/needsFolderAccess metadata must remain unchanged.

A cursor can expose a row count after the query, making a cursor-local visited-row denominator possible. However:

- a cursor row is not automatically a successfully processed eligible file;
- invalid rows may be skipped;
- query providers differ in how limits are honored;
- result limits and traversal safety bounds define the bounded scan, not the entire device;
- subsequent category queries, SAF traversal, merging and Flutter analysis may remain;
- summing cursor counts cannot claim a count of distinct files, since categories overlap.

Progress must label work units accurately and increment only after the corresponding required processing finishes. It must not report a cursor-local fraction as an entire multi-source scan fraction.

The pre-Android-10 Downloads fallback walks directories. Its final total is likewise not known before traversal completes.

### SAF

SAF performs breadth-first traversal through granted trees with existing bounds of 400 directories and 20,000 visited documents, plus result limits. It filters directories/files, applies MIME/name/size predicates and suppresses duplicate document IDs. Grants can disappear during traversal; existing code catches inaccessible/broken subtrees and continues safely.

Visited-document counts are possible without extra traversal. A trustworthy total of all eligible matching files is not available in advance. A separate counting traversal would duplicate expensive provider I/O and can race with filesystem changes. Do not add it merely to animate a percentage. SAF discovery should remain explicitly indeterminate while the denominator is unknown.

### Exact hashes

`FileHashBridge.kt` uses a two-thread executor, streams SHA-256 with a fixed buffer, and caps each call at 400 URIs. A per-batch denominator is available from its capped URI list. A hash is available only after the full stream has been read and the digest computed. Unreadable files are omitted intentionally.

`PlatformFileHashRepository` chunks larger requests and reuses a bounded session cache. Native-batch counts must not restart the overall progress at zero for every batch, nor omit cached work from a declared operation plan. Cached hashes must retain their current semantics; do not recompute files just to obtain animation events.

### Perceptual hashes

`PerceptualHashBridge.kt` similarly uses a worker pool and caps batches at 600. It decodes downsampled images and computes the existing dHash/aHash pair. Report a processed image only after decoding/hash processing has returned; distinguish unreadable images. The Flutter repository chunks requests and caches fingerprints.

### Installed apps

`InstalledAppsBridge.kt` already uses a single-thread executor. It enumerates launcher activities, excludes this app, de-duplicates packages and reads metadata, optional usage statistics and optional icons. Launcher-activity count is not an eligible-app count. A unique eligible package worklist is needed before publishing an app denominator. Reuse the same enumeration; do not rescan packages for the progress UI.

The bridge/repository currently convert some failures into empty snapshots. A progress terminal status must not infer successful completion solely from receiving an empty result.

## 3. Flutter and permission boundary

`FileScannerChannel.scan` is a result-only MethodChannel call. `MediaStoreFileScannerRepository.scan` parses and de-duplicates the payload and builds the existing category summaries. `PermissionAwareFileScannerRepository` refreshes the central permission manager before each new scan and removes inaccessible categories.

Progress accounting must be downstream of that permission filter. Never count the denied categories from the original request, never call selected visual access unrestricted storage access, and never broaden SAF scope or introduce new permissions.

The centralized manager, capability policy, manifest and permission-related routing should remain intact. A new scan/session identifier and progress/cancellation transport can be added without replacing their authority.

## 4. Analysis and module coverage

| Module | Actual existing pipeline | Count opportunities and limitations |
|---|---|---|
| Smart Scan | RecommendationsController → cleanupScanDataProvider → large files, Downloads, APKs, screenshots, duplicate detection, videos, storage capacity → recommendation/score evaluation | Several concurrent cached-provider branches. Whole-operation progress requires coordination of every required branch, including hashing/grouping and final evaluation. Otherwise remain indeterminate overall; stage counts may still be reported. |
| Photos Cleaner | photoCleanupProvider → duplicate photos, screenshots, large photos, similar photos → combined summary | Multiple discovery and analysis stages; no existing whole-operation denominator. |
| Duplicate Photos | images + Downloads discovery → image filtering → size candidates → SHA-256 → exact grouping | Candidate/hash counts become known only after discovery. Hashing completion is not comparison/grouping completion. |
| Similar Photos | images + Downloads discovery → candidate selection → perceptual hashes → leader-based comparison/grouping | Candidate count is bounded/known after discovery; the number of pair comparisons depends on the leaders formed. Do not invent a pair count or use a worst-case count as an exact total. |
| Similar Photos best-photo suggestions | completed similar groups → quality measurements → best-photo ranking | Separate derived work watched by the similar-photo screen. Explicitly distinguish the base similarity scan from optional quality recommendations; do not silently claim optional later work was already performed. |
| Screenshots | image metadata discovery → ScreenshotSummary filter/group | Cursor-local rows can be counted. Final summary processing remains part of the required operation. |
| Large Photos | image metadata discovery with existing size floor → LargePhotoSummary | Same distinction between discovery and final summary. |
| Videos / Large Videos | video metadata discovery → VideoSummary sorting/filtering | A single cursor can expose a bounded metadata-work count; hold success until required Flutter result processing finishes. |
| Files Cleaner / Files | authorized categories → MediaStore/SAF/fallback → parse/de-duplicate/aggregate | Multiple unknown sources; numeric overall progress is unavailable while any required denominator remains unknown. |
| Large Files | authorized categories with existing size floor → metadata result → LargeFileSummary | Same multi-source limitations as Files; no changes to size thresholds or totals. |
| Duplicate Files | authorized mixed-category discovery → size candidates → chunked SHA-256 → exact grouping | Discovery, hashing and grouping all count; do not complete the ring at discovery or the last hash. |
| APK Cleaner | APKs + Downloads + Documents discovery/SAF → APK filtering and summary | Overlapping sources and SAF make the initial overall eligible count unknown. |
| Downloads Cleaner | Downloads discovery/SAF or legacy directory walk → age filter and summary | SAF/legacy traversal may remain indeterminate. |
| Installed Apps | launcher enumeration → unique packages → metadata/stats/icons → Flutter snapshot/inventory | Measured package counts are feasible once the eligible worklist is fixed. Errors must not masquerade as a successful empty scan. |

`DuplicateDetector` first groups by size and URI, then groups hashes and sorts confirmed copies. `SimilarPhotoDetector` uses leader-based comparisons rather than transitive chaining. Their matching rules and ordering must not change for progress instrumentation.

## 5. Lifecycle and error limitations

The current scan screen prevents navigation after disposal using mounted checks, but it does not cancel native scans. Existing providers are shared/cached; leaving one screen does not imply nobody else needs the same work. Native hasher/app executors are released on activity destruction, not on per-scan cancellation.

A safe change therefore needs:

- independent operation, child-request and generation IDs;
- stale-event rejection, including queued native events after retry/disposal;
- consumer/session ownership so cancelling one screen does not abort unrelated shared work;
- cooperative cancellation checks between rows, directory visits and file-processing units, with safe stream/cursor cleanup;
- explicit running, successful, failed, cancelled and partial/unavailable outcomes;
- no 100% inference from existing swallowed errors or partial payloads;
- no new prompt loops or broad access requests on permission failure;
- latest-state recovery on app resume rather than replaying stale visual events.

A pending OS/provider query or one large decoding operation may not be immediately interruptible. Cancellation should be documented as cooperative, not instantaneous.

## 6. Proposed implementation scope requiring approval

1. Add a typed request-scoped progress contract and throttled native-to-Flutter notifications using the existing platform-channel architecture, without an extra package.
2. Move file discovery off the platform thread while preserving query arguments, iteration order, filters, limits, result payloads and SAF security behavior.
3. Add native row/document/hash/app counters at actual completed-work boundaries. Keep unknown totals null. Do not block scanning waiting for progress acknowledgements.
4. Add Flutter operation coordination covering required child requests, cache reuse, analysis, final aggregation, terminal status and cancellation ownership.
5. Publish a numeric whole-operation fraction only when its complete work denominator is reliable. Otherwise keep the ring indeterminate and expose actual stage/count information without claiming an overall percentage. Do not average stage percentages, assign arbitrary weights, or freeze an inaccurate maximum after a denominator grows.
6. Separate ring geometry from the existing internal icon controller. Fix the ring start at twelve o'clock; draw a persistent clockwise sweep; move the orange marker to its leading edge. Unknown work must not rotate a fixed blue arc. Smooth interpolation may approach but never exceed confirmed values. A new session resets; an existing session never moves backward. Only a successful entire operation can produce a full ring.
7. Preserve presentation gates and navigation. Those gates must not delay native work or advance progress. Preserve silent 5800 ms internal file animation.
8. Add unit/widget/channel and feasible native tests, then run dependency resolution, analyzer, full tests and diff checks. Attempt release APK/AAB builds only with the necessary SDK/toolchain/signing environment; report limitations accurately.

### Risks

This spans concurrency and lifecycle boundaries, not only UI. Primary risks are accidentally double-counting provider-reused work, failing to include late analysis stages, cancelling shared work, and changing thread/partial-error behavior. The planned mitigation is explicit operation ownership and terminal accounting plus result-regression tests. Some composite/SAF operations may legitimately remain indeterminate; a universal numeric percentage cannot be promised without extra enumeration or changing the scan plan, neither of which should be hidden in this task.

## 7. Version preflight

- Current `pubspec.yaml`: `version: 1.0.0+1`.
- Requested version: `1.0.1+2`.
- Android `defaultConfig` uses `versionName = flutter.versionName` and `versionCode = flutter.versionCode`.
- Application ID: `com.KoreAppsTek.PhoneStorageCleaner`.
- Existing release signing reads `android/key.properties`; no signing change is proposed.
- No release AAB/APK or repository evidence of version code 2 or higher was found in the inspected release/configuration locations and recent history.
- Repository inspection cannot establish whether Google Play has already received version code 2 or higher. User confirmation or Play release history is required to settle that condition. Do not imply Play was checked.

## 8. Current verification environment

At audit time, Flutter is not on PATH and the Flutter SDK cache used in the prior task is no longer present. ANDROID_HOME/ANDROID_SDK_ROOT are unset; no Android signing key/config was found in the inspected Android locations. Java 11 is present, whereas Android build configuration targets Java 17. These are environment observations, not new build attempts. No tests, analyzer or release builds have been claimed for this task yet.
