# Centralized permission management

Implemented 2026-11-16 in the working tree. This work preserves the earlier, uncommitted Circular File Scanner work; it does not replace it or commit/push the repository.

## Audit and root causes

The permission audit covered the manifest/Gradle SDK settings, Flutter runtime gateway and preferences, Home/tab/shortcut routing, permission explanation screen, individual module recovery actions, SAF repository/banner, Android SAF and MediaStore bridges, installed-app/usage-access behavior, deletion authorization, and existing tests. Initial findings were reported before implementation.

Previously:

- Home and the Smart Scan tab sent users through the explanation screen even if Android had already granted access.
- The gateway bundled photos, videos and audio into a single aggregate decision. Feature requirements were not distinguished, and limited access could be treated too broadly.
- Module error actions opened a generic permission page, losing the intended feature/scan context.
- Settings was checked immediately after launching it, before the user could change anything. There was no shared lifecycle-aware state for revocation.
- The optional SAF explanation remained visible after a persisted tree grant, encouraging repeated requests. A folder grant and runtime media access are different capabilities.
- The native mixed-category scan can abort on a SecurityException from one denied media collection. Merely allowing partial access in the router would therefore not be sufficient.

The duplicate behavior was mostly repeated navigation/check logic, not several independent native permission dialogs. The existing explanation design is reused; a new per-module explanation UI was not added.

## Shared architecture

- `PermissionGateway`: the only Flutter runtime-permission transport. Reads actual Android statuses via the existing permission_handler plugin and maps granted, denied, permanently denied, restricted and limited separately. Uses device_info_plus for the SDK version. Neither package is new.
- `PermissionSnapshot`: immutable runtime capabilities plus separate, actual persisted SAF tree URIs. Capability decisions are feature-specific. No permanent `permissionGranted` preference exists.
- `PermissionManager`: one Riverpod manager for fresh reads, requests, folder picking and foreground/resume refresh. Concurrent reads share a flight; runtime dialogs and folder pickers share a single-flight operation. It requests only missing, requestable capabilities, and never opens a dialog from a read, route redirect or lifecycle callback. Permanent/restricted denial is not repeatedly requested.
- `permission_policy.dart` and the router: centralized entry/deep-link policy and validated local continuation destinations. Sufficient access skips education; missing access retains the existing explanation. Successful grants replace it with the requested feature automatically. Apps analysis is not storage-gated.
- `PermissionEducationScreen`: keeps the existing presentation, adds shared state handling, automatic continuation, restricted-state handling and Settings/resume continuation. The existing education-seen preference remains presentation-only and is never proof of permission.
- App-level snapshot listening: checks the visible pushed feature after a changed OS snapshot. GoRouter.refresh alone is insufficient because it may recheck the underlying Home URI rather than a tool pushed above it.
- `PermissionAwareFileScannerRepository`: an access boundary in front of the unchanged scanner. Freshly checks the manager, excludes denied media categories from mixed scans, and preserves each permitted request's limits, minimum size and ordering. Delegate parsing, totals, result calculations and native algorithms are unchanged. A wholly denied specific-media request fails with SCAN_PERMISSION_DENIED rather than looking like a successful empty scan.

An in-memory snapshot supports UI rendering only. Feature entry, actual new scans, restart and resume perform live checks. Read failures are not accepted as cached grants. Android/content providers remain the final enforcement boundary, including revocation between a check and a query.

## Exact feature requirements

| Destination | Requirement and legitimate scope |
|---|---|
| Photos, Screenshots, Large Photos, Duplicate Photos, Similar Photos, photo-cleanup scans | Legacy shared read on API <33; images capability on API 33+. Selected visual access is allowed only within Android's visible selection. |
| Videos / Large Videos scan | Legacy shared read on API <33; video capability on API 33+. Does not borrow a photo grant. |
| Audio category recovery | Legacy shared read on API <33; audio capability on API 33+. A limited visual grant is never an audio grant. |
| Files dashboard, APK Cleaner, Downloads Cleaner | API <29: legacy shared read. API 29+: visible scoped MediaStore rows and optional explicitly granted SAF trees; unrelated media grants are not required to open these limited tools. Files remains reachable without media grants so the optional folder chooser is available. |
| Smart Scan, Clean, Large Files, general Duplicates | Reuses legitimate accessible media subsets; a persisted SAF tree also permits limited discovery on scoped-storage Android. Missing categories remain missing and are filtered from new scans, not treated as granted. |
| Installed Apps / apps scan | No media/storage permission gate. Existing optional Usage Access in system Settings remains separate; it enriches app statistics and is not required for the basic app list. |
| File-category permission recovery | Carries the original category through a recognized local route, with images/video/audio/non-media requirements as appropriate. Existing ordinary category navigation is preserved. |
| Delete / uninstall | Existing per-operation Android authorization, confirmation and SAF write enforcement remain unchanged. Read access is not represented as deletion authorization. |

A photo grant therefore serves all photo tools, but never all files, audio or video. General discovery may use a subset; it does not declare unrestricted file access. SAF is limited to the selected tree(s), and a read grant does not imply write access. The repeated SAF banner hides after a live persisted read grant; the explicit Permissions overview retains a user-initiated option to choose another folder. New grants from the Files chooser invalidate its discovery provider as before.

## Android versions and manifest

- **Android 7–9 / API 24–28:** existing legacy storage permission group is reused. The existing WRITE_EXTERNAL_STORAGE declaration stays capped at API 28; permission_handler's legacy storage request includes applicable manifest read/write permissions. Existing deletion handling is untouched.
- **Android 10 / API 29:** shared-media read uses the legacy read permission; non-media discovery is scoped and can use SAF. No requestLegacyExternalStorage or all-files workaround was added.
- **Android 11–12 / API 30–32:** shared-media read uses READ_EXTERNAL_STORAGE. Non-media remains scoped/SAF. No MANAGE_EXTERNAL_STORAGE is declared or requested, so the implementation does not invent an all-files flow.
- **Android 13 / API 33:** images, videos and audio are separate capabilities. A specific module requests only its necessary media type.
- **Android 14 / API 34:** the existing READ_MEDIA_VISUAL_USER_SELECTED support is preserved; limited images/video statuses remain limited, and can support the corresponding selected-media tools. They are never converted into full storage or audio access.
- **Android 15–16 / API 35–36:** the same granular/selected-media policy applies without changing existing target compatibility. Gradle remains targetSdk 36 and compileSdk 37. minSdk remains Flutter-defined (24 in the SDK used for verification).

Manifest and native Android files are unchanged. Existing READ_EXTERNAL_STORAGE max32, WRITE_EXTERNAL_STORAGE max28, READ_MEDIA_IMAGES/VIDEO/AUDIO, READ_MEDIA_VISUAL_USER_SELECTED, optional PACKAGE_USAGE_STATS and REQUEST_DELETE_PACKAGES remain as-is. No sensitive permission or package was added. No SDK/build configuration migration was performed.

## Files/modules changed

New shared implementation:

- `lib/features/permissions/domain/permission_snapshot.dart`
- `lib/features/permissions/presentation/providers/permission_manager.dart`
- `lib/app/router/permission_policy.dart`

Focused integration:

- Permission gateway/status/education screen.
- `lib/app/app.dart`, `lib/app/router/app_router.dart`, Home and app shell launch actions.
- File scanner repository access wrapper; original MediaStore scanner implementation is retained.
- Files/Photos/Clean and individual photo/video/file cleaner permission-recovery actions, including category recovery.
- Folder-access banner uses shared live grants rather than a permanent UI flag.

Tests:

- `test/permission_manager_test.dart`
- `test/permission_gateway_test.dart`
- `test/permission_navigation_test.dart`
- `test/permission_scan_boundary_test.dart`
- `test/support/permission_fakes.dart`
- Updated `test/widget_test.dart` for the actual shared gateway and automatic continuation. Its SAF channel is mocked explicitly so Android channel I/O is deterministic in widget tests.

## Preservation checks

The three protected scanner files were compared byte-for-byte against their pre-permission-task copies and are unchanged:

- `lib/core/ui/circular_file_scanner.dart`
- `lib/features/cleaner/presentation/screens/scan_progress_screen.dart`
- `lib/features/files/presentation/widgets/photo_tool_ui.dart`

No changes were made to native scanning algorithms, scan delays, duplicate matching/hashing, deletion/cleanup algorithms, result arithmetic, storage calculations, themes or the scanner's visuals. Permission-related routing and filtering of unauthorized categories are intentional. Git diffs still include the earlier uncommitted scanner implementation, which must not be mistaken for new permission-task changes.

## Verification actually performed

Environment: Flutter 3.50.0 / Dart 3.14.0 on Linux.

| Check | Actual result |
|---|---|
| Complete `flutter test --no-pub --reporter expanded` | **751 passed, 0 failed**. Includes existing scanning, storage, deletion, cleanup, duplicate, navigation and animation/lifecycle regression tests. |
| New permission coverage | 50 tests across snapshot/manager, gateway, navigation and scan-boundary tests. Covers version policy, cross-module reuse, missing/denied/permanent/restricted/limited access, Settings return, revocation, restarted manager, single-flight requests, no implicit prompt loops, SAF separation and partial-scan preservation. |
| Final navigation rerun after strengthening the scoped-Files assertion | **7 passed, 0 failed**; verifies Files/SAF entry remains available without unrelated media grants. |
| `flutter analyze --no-pub` | **0 errors; 94 diagnostics: 93 material.dart deprecation infos and 1 existing missing assets/icons/ directory warning**. Exit status 1 due to diagnostics; not claimed clean. |
| `flutter build apk --debug` | Attempted, **blocked: No Android SDK found**. No APK produced. |
| `git diff --check` | Passed. |
| Manifest/native/package configuration | Unchanged; no package added. Original pubspec.lock restored. |

The available newer Flutter SDK resolved seven SDK/transitive dependency versions during setup. Tests/analyzer used that resolved package configuration. The original tracked lockfile was restored to avoid an unrelated dependency upgrade; the repository's original exact lock versions were not separately re-resolved and retested under a matching older SDK.

### Device limits / remaining device QA

All Android-version and lifecycle coverage above is unit/widget/channel-mock coverage, not a device compatibility certification. No emulator, physical device, Android SDK build or store-policy verification was performed. Actual selected-photo picker behavior, process death after Settings, OS-level persisted SAF grants, OEM permission dialogs, Android 7–16 runtime behavior and real deletion consent still require Android device/emulator QA. Revocation between a check and an operation can still be reported by Android; the code does not bypass OS enforcement or retry permission prompts automatically.
