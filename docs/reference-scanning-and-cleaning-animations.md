# Reference-based scanning and cleaning animations

## Delivery status

Implemented in the working tree; **not committed or pushed**. Version remains **1.0.1+2**. Existing unrelated working-tree changes were preserved. No dependency was added; `pubspec.lock` was restored byte-for-byte to the task-start copy after toolchain dependency resolution.

The supplied annotated JPEG is the visual source, specifically the upper-left Smart Scan and lower-right Cleaning Progress orbs. This is a scalable vector reconstruction, not an assertion of pixel-identical rendering from a compressed, annotated screenshot. Device visual approval remains pending.

## Components changed for this task

- `lib/core/ui/reference_progress_art.dart`: shared sampled palette, concentric geometry, gradient/glow, measured orange arc, scanner beam, custom broom, subtle shine and reference-style bar.
- `lib/core/ui/circular_file_scanner.dart`: renders the shared artwork while preserving lifecycle, reduced-motion, interpolation and parent-completion semantics; distinguishes cleaning accessibility labels.
- `lib/features/cleaner/presentation/screens/scan_progress_screen.dart`: uses the reference-style progress bar without replacing the real stage architecture.
- `lib/features/files/domain/delete_progress.dart`: operation-scoped channel observation, cumulative evidence validation, final-result reconciliation and exception recovery.
- `lib/features/files/domain/delete_result.dart` and `data/delete_repository.dart`: successful removals, failures, skips, cancellations and confirmed logical sizes remain separate.
- `lib/features/files/presentation/widgets/delete_flow.dart`: cleaning UI reads actual outcomes rather than elapsed time; actual known current item, confirmed bytes and processing progress.
- `lib/features/files/presentation/screens/cleanup_complete_screen.dart`: partial/cancelled/skipped and unknown-size disclosure, including safe handling of empty failure lists.
- Native `DeleteProgressLedger.kt`, `DeleteBridge.kt`, `MainActivity.kt`: cumulative per-item evidence, worker I/O, coalesced progress notifications, consent verification and lifecycle cleanup.
- Tests: `reference_animation_and_cleaning_test.dart`, `native/DeleteProgressContract.kt`, and updated scanner/stage/safe-delete tests.

## Sampling and geometry

Median RGB samples from unmarked 5-pixel patches in the original 757×1600 JPEG were used to reduce JPEG noise. Coordinates and values are retained in [color-samples.json](reference-animation-evidence/color-samples.json). Red circles and green handwriting were excluded from the art.

| Role | Sample |
|---|---|
| Royal blue | `#3367ED` |
| Blue | `#164AD3` |
| Deep blue | `#032C99` |
| Cyan | `#49C4F3` |
| Ice | `#B4DFFE` |
| Pale ring | `#CEDAF5` |
| Outer halo | `#EFF2FB` |
| Orange | `#F79516` |
| White | `#F4FBFC` |

Geometry scales with the widget's shortest side: halo radius .49; pale rings .45/.411; illuminated rims .386/.366; blue center .342; orange arc radius .375 and solid stroke .036. Gradients, alpha layers and blurred lips reproduce the reference's depth rather than using the app theme or a generic radar palette. The broom is a custom tilted white path with bristles, not a stock replacement icon.

Actual Flutter widget captures (illustrative partial progress, not a device render):

- [Scanning capture](reference-animation-evidence/scanning.png)
- [Cleaning capture](reference-animation-evidence/cleaning.png)

## Measured progress and animation

The orange sweep is `2π × confirmed fraction`, clockwise, with butt caps to avoid implying extra completed work. Scanning begins at the top; cleaning begins at −π/6, matching the lower/right reference segment. The 5800 ms scanner rotation and cleaning pulse/shine are decorative, silent, and independent of measured progress. Existing 240 ms confirmed-value interpolation remains; elapsed time never creates progress.

The real stage-based scan controller remains authoritative. Unknown totals are not converted to invented percentages. A finished stage can show its complete arc without becoming parent success. The white success check requires the parent operation to have actually succeeded. Lifecycle pause/resume, reduced motion and operation identity/reset are retained.

Cleaning progress is **processed unique selected items / requested unique items**, not successful deletions / requested items. Failed and skipped items can finish processing without being described as reclaimed. A full processing bar is not a successful-cleanup declaration. Old repositories with no intermediate telemetry remain unchanged until their real future resolves rather than simulating progress.

## Deletion audit and accounting

The deletion pipeline was inspected before exposing progress. The old cleaning animation used elapsed-time progress and planned-byte estimates; these are removed.

1. Each operation carries a distinct ID; native events contain a sequence and cumulative per-URI outcomes. Wrong IDs, stale sequences, foreign URIs, contradictory outcomes, regressive counts/bytes and changes to already confirmed sizes are rejected.
2. Per-item work runs on a single native worker, with coalesced main-thread progress delivery. Preparing, waiting for authorization and verification do not fabricate successful removals.
3. Direct filesystem deletion, MediaStore deletion and SAF retain their authorization paths. An already-absent file or zero affected rows is skipped, not cleaned. SAF failure is not counted as removal.
4. Android confirmation does not itself prove deletion. System-mediated removals require prior presence and confirmed subsequent absence; unknown verification is a failure, not success. Android 10 retains its recoverable per-file authorization path; Android 11+ retains the system bulk consent path. The legacy write-permission path remains.
5. Successful deletions and sizes confirmed before a later failure or cancellation survive in the result. Untouched cancelled items are not counted as processed or reclaimed. Repository exceptions preserve valid prior evidence and fail unresolved items.
6. The final repository future, not a native terminal notification, authorizes completion/navigation. Final outcomes are reconciled against the original selection: each URI counts once, failure wins over skip, and skip wins over success. Missing non-cancelled outcomes fail closed.
7. Native accounting version 1 supplies known pre-delete logical sizes only for confirmed removals. Missing or invalid sizes contribute zero and receive unknown-size disclosure. Legacy/custom repositories with no size map retain scanned-size compatibility; their byte total is not a fresh native size measurement.
8. Disposing the UI detaches observation; it does not pretend to cancel a deletion already authorized. Native pending confirmations interrupted by bridge disposal are resolved conservatively. Per-prompt request codes protect later operations from ordinary stale Android callbacks; they use Android's bounded 16-bit range and eventually wrap.

**Measurement limit:** the displayed confirmed byte total is the sum of known logical sizes of confirmed removed files, not a measured increase in physical volume free space. Cloud-backed providers, compression, shared allocation, concurrent modification and OS cleanup can make these differ. The UI labels this as confirmed removed / known file sizes. No claim of exact physical reclaimed-space measurement is made.

## Validation

| Check | Result |
|---|---|
| Full Flutter suite, final run | **813 passed**, `flutter test --no-pub --concurrency=1 --reporter expanded` |
| Native delete ledger/verification contract | **37 assertions passed** |
| Existing native scan progress contract | **43 assertions passed** |
| Standalone compile of all production Kotlin sources | **Passed**, Kotlin 2.2 / JDK 17 / Android API classpath; two deprecation warnings in existing Apps/SAF code |
| Flutter analysis | **0 errors; 1 warning and 110 informational findings**; command exits 1, not a clean analyzer run |
| Analyzer warning | Existing missing `assets/icons/` directory in `pubspec.yaml` |
| Whitespace/diff check | `git diff --check` passed |
| Release APK and AAB attempts | Both blocked: **No Android SDK found** |
| Version/dependency check | `1.0.1+2`, no added dependencies, original lockfile preserved |

Evidence logs are in `docs/reference-animation-evidence/`: [Flutter](reference-animation-evidence/full-final.log), [analysis](reference-animation-evidence/analyze-final.log), [Kotlin compilation](reference-animation-evidence/kotlin-final.log), [delete contract](reference-animation-evidence/delete-contract.log), [scan contract](reference-animation-evidence/scan-contract.log), [APK](reference-animation-evidence/apk.log), [AAB](reference-animation-evidence/aab.log).

Coverage includes actual stage progression/completion/reset, measured orange arc geometry, stale callbacks, unknown sizes, failures/skips/cancellation, permission-wait progress, delayed repository completion, exception evidence preservation, malformed final-result reconciliation, repeated deletion scopes, animation pause/resume/disposal and widget captures. JVM contract checks are not Android instrumentation: actual ContentResolver, SAF providers and OS dialogs still require device testing.

## Device QA still required

No emulator or Android device was available. Standalone Kotlin compilation is not a Gradle APK/AAB build or platform integration test.

Before release, test on representative devices:

- Android 9 legacy permission grant/denial; Android 10 per-item recoverable authorization; Android 11+ bulk system deletion confirm/cancel, including a mixed authorized/denied batch.
- SAF writable, revoked, read-only, missing, cloud-backed and unknown-size documents; verify actual outcomes against provider contents and ensure no inaccessible item is counted as cleaned.
- Already-absent files, zero rows deleted, partial batches and interruption after some confirmed removals.
- Background/resume and activity recreation during scanning, deletion and a pending Android dialog; verify no frozen overlay, duplicate completion or stale callback updating the next operation.
- Repeated scans/deletions, back/navigation, disposal and reduced-motion settings; no audio and no success check before parent success.
- Compare the two orbs with the original reference at target display size, including cyan softness, blue depth, arc spacing, broom silhouette and bar layout; profile smoothness on a lower-end device.
- Build signed release artifacts and run installation/smoke tests once a complete Android SDK/build environment is available.
