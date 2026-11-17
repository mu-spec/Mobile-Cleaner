# Circular File Scanner — implementation and verification

## Scope

Visual-only replacement of scanning/loading artwork. Native scanning, repositories, algorithms, result calculations, permissions, deletion, and route destinations are unchanged.

## Inspection findings

- The water-fill implementation was shared in `ScanProgressScreen`: `_PremiumScanRing` / `_PremiumScanPainter`, including waves and bubbles. There were no separate water-fill implementations in individual tools.
- That route serves Smart Scan, Photos, Files, Apps, Screenshots, Duplicates, and large-video scanning.
- Other tool loading states use `FilesScanningView` -> `PhotoToolLoadingState`, or `PhotoToolLoadingState` directly. These now use the same circular scanner, including APKs and downloads.
- The native scanner returns a completed result, not incremental counts or fractions. The old 0–90% display was an elapsed-time estimate, including its accessibility value. It is no longer represented as actual progress.
- Existing palette reused: Home blue `#2563EB`, orange `#FF8A00`, white surfaces, and AppColors dark-mode equivalents.

## New shared component

`lib/core/ui/circular_file_scanner.dart`

- Blue circular stroke with round caps and a small orange marker.
- Stable blue folder at the center.
- Four lightweight vector icons: Photos, Videos, Audio files, Documents.
- Icons move inward with sine easing, gently shrink, and fade to zero at the repeat boundary; no sudden reset is visible.
- Gentle 5.8-second decorative loop (four former 1.45-second wave cycles). The loop has no connection to scan completion.
- Single AnimationController and CustomPainter(repaint: controller), isolated by RepaintBoundary. The screen and center folder are not rebuilt every frame.
- No image/video/GIF assets, blur filters, shaders, glow, audio calls, haptics, or added packages.
- `active: false` freezes activity for errors/cancellation. `completed: true` shows a static completed ring/check.
- TickerMode, app foreground/background lifecycle, and reduced-motion accessibility are respected. Controller and lifecycle observer are disposed.

### Progress contract

```dart
// Existing native scanners: no measured fraction is available.
const CircularFileScanner();

// Only for a caller that actually has measured progress:
CircularFileScanner(progress: completedFiles / totalFiles);
```

Null progress draws an indeterminate arc and announces “Scanning”, with no numeric percentage. Supplied progress controls the ring sweep and marker directly, and the measured percentage is exposed to accessibility. Elapsed time never advances determinate progress. Completion is passed by the caller after the real scan succeeds.

The status card's existing horizontal indicator is also indeterminate until success; it no longer displays simulated progress. Its surrounding layout is preserved. Time-derived phase descriptions were replaced by an activity description rather than claiming unmeasured scan stages.

## Timing and lifecycle preservation

The existing sequence remains:

1. Start the exact same real scan and the existing 2800 ms presentation gate together.
2. Await both, so a long scan never navigates early.
3. Retain the existing 650 ms completion transition gate.
4. Mark completion only after success.
5. Retain the existing 420 ms pause before the same navigation operation.

The new artwork does not add a gate or wait. Only the old visual rotation controller was removed from the screen; the shared artwork owns its decorative controller.

Source comparisons confirmed `_runRealScan`, `_openResults`, and `_goBack` are unchanged, and `_startScan` sequencing is unchanged after excluding the old visual-only rotation calls. Back navigation still does not cancel native work: it disposes the UI and the existing mounted guards prevent a later redirect. No scan-engine cancellation behavior was added.

The animation area stays 228 px on the scan route and 92 px in compact loading views. Existing headings, actions, screen structure, and navigation remain intact. Deletion/cleanup animations and unrelated storage, permission, onboarding, and history indicators were not replaced.

## Coverage

| Screen or flow | Shared integration |
|---|---|
| Smart Scan, photo cleanup, files, installed apps, screenshots, duplicates, large videos | ScanProgressScreen |
| Clean results rescanning; Files dashboard/category browser; Photos dashboard; Apps list | FilesScanningView -> PhotoToolLoadingState |
| APK Cleaner, Downloads Cleaner, Large Files, Videos | FilesScanningView -> PhotoToolLoadingState |
| Screenshot Cleaner, Large Photos, Duplicate Files, Duplicate Photos, Similar Photos | PhotoToolLoadingState (directly or through a local wrapper) |

## Files

Created:

- `lib/core/ui/circular_file_scanner.dart`
- `test/circular_file_scanner_test.dart`
- `test/scan_progress_lifecycle_test.dart`
- `docs/circular-file-scanner.md`

Modified:

- `lib/features/cleaner/presentation/screens/scan_progress_screen.dart`
- `lib/features/files/presentation/widgets/photo_tool_ui.dart`
- `test/widget_test.dart`

No dependency or lockfile changes are included. No Android/native files or audio assets were added or changed.

## Verification results

Environment used: Flutter 3.50.0 stable / Dart 3.14.0, installed under the workspace cache for verification.

| Command/check | Final result |
|---|---|
| `flutter test --reporter expanded` | **701 tests passed**, including all existing suites and 12 new focused tests |
| Focused component/widget run | **18 tests passed** (9 new component tests + 9 existing app widget tests) |
| Focused `scan_progress_lifecycle_test.dart` | **3 tests passed** |
| `flutter analyze` | Completed, exit 1: **0 errors**, 1 missing `assets/icons/` directory warning, 92 SDK deprecation notices and 1 existing directive-order notice |
| `dart format --output=none --set-exit-if-changed` on six changed/new Dart files | Passed; zero changes required |
| `git diff --check` | Passed |
| `flutter build apk --debug --no-pub` | Blocked: **No Android SDK found**; no APK produced |
| Widget-rendered artwork inspection | Captured and inspected with the real Material icon font; temporary capture test removed |
| Source scope/coverage check | Old water-fill symbols absent; scan calls, navigation, native code and deletion unchanged |

Focused tests cover long-running activity without invented completion, caller-supplied determinate progress, stopping on completion/inactivity/disposal, retry, offstage/background/reduced-motion behavior, light/dark compact rendering, shared loading-state adoption, timing gates, and leaving an unfinished scan without a later redirect. The existing slow-scan widget test now waits an additional 20 seconds before completing its fake scanner.

The first run of the new timing tests exposed test-harness boundary/viewport assumptions, which were corrected; the final focused and full-suite runs passed. A concurrent analyzer attempt was killed by the environment; the subsequent serial analyzer run completed with the diagnostics above. None of these diagnostics were suppressed or fixed through unrelated refactoring.

Flutter 3.50's SDK pins required temporary transitive dev-dependency resolution during testing. The repository's original `pubspec.lock` was restored unchanged after verification; no dependency upgrades are delivered.

## Remaining limits

- Actual device frame pacing and low-end Android performance have not been profiled; a 60 FPS guarantee would require device measurements.
- Native MediaStore/SAF behavior and Android system dialogs require device testing. They are not redesigned by this change.
- Existing scanning APIs do not expose intermediate real progress. An indeterminate ring is intentional, not a missing timer-based percentage.
- APK verification needs an Android SDK and compatible Java/build tooling. This workspace currently has no Android SDK.
- The pre-existing missing asset directory warning and SDK-wide deprecation notices remain outside this animation-only scope.
