# Phase 23 — App Analyzer

Read installed applications where Android permits. Show icon, name, and
available size information. Provide Open, App Settings, and Uninstall.

The Apps tab was a `FeaturePlaceholder` since Phase 0. It is now real.

## "Where Android permits" is the whole design

Two hard platform limits shape this phase, and both are surfaced to the user
rather than worked around.

### 1. Package visibility — no `QUERY_ALL_PACKAGES`

Since Android 11 an app cannot see the full package list. `QUERY_ALL_PACKAGES`
would lift that, but it is **Play-restricted and requires case-by-case
approval**; apps have been removed from the Play Store for using it without
justification. It is not used here.

Instead the manifest declares a `<queries>` entry for the LAUNCHER intent:

```xml
<intent>
    <action android:name="android.intent.action.MAIN"/>
    <category android:name="android.intent.category.LAUNCHER"/>
</intent>
```

That reveals exactly the apps a person would call "my apps" — the ones with an
icon. Background services and iconless system components stay invisible, which
is the *correct* answer, not a gap.

**Consequence, stated in the UI:** the count will not match system Settings.
The headline card carries `apps_visibility_note` saying so. A cleaner that
quietly shows 40 apps when Settings shows 180 looks broken; one that explains
why does not.

### 2. Size information is tiered

| Tier | Source | Requires |
|---|---|---|
| APK size (incl. split APKs) | `sourceDir` + `splitSourceDirs` file lengths | nothing |
| App + data + cache | `StorageStatsManager.queryStatsForPackage` | `PACKAGE_USAGE_STATS`, API 26+ |

Usage Access **cannot be requested with a runtime dialog** — Android only
grants it from system Settings. So:

- without it, the row reads **`25.0 MB app`** — labelled, not passed off as a
  total — and the headline says *"App size, excluding data"*
- `totalBytes` returns **null**, never a partial sum. A total silently missing
  data would be compared against Settings and found wrong
- a card offers the one route that exists: open Usage Access settings
- **below Android 8 the card is not shown at all**, because the API does not
  exist there and prompting would be a dead end. `sizeDetailSupported` is
  tracked separately from `hasUsageAccess` precisely for this

Split APKs are counted. A modern app ships a base plus density and ABI splits;
counting only the base understates it badly.

## Nothing is uninstalled by this app

All three actions are handoffs:

| Action | Intent |
|---|---|
| Open | `getLaunchIntentForPackage` |
| App Settings | `ACTION_APPLICATION_DETAILS_SETTINGS` |
| Uninstall | `ACTION_DELETE` — **Android's own confirmation** |

There is no code path that removes a package. The platform dialog does not
report its result, so the outcome is learned by observing: the screen registers
a `WidgetsBindingObserver`, and on `resumed` asks whether the package is still
installed. Only if it is gone does it refresh — a cancelled uninstall costs no
re-read and no icon re-rasterisation. A test asserts exactly that.

Actions that fail return `false` and surface a SnackBar. A dead button that
does nothing is worse than one that says it could not.

Two actions are disabled up front rather than allowed to fail:

- **Uninstall** on system apps — Android refuses, so the row says so instead
- **Open** where there is no launcher intent

This app also excludes **itself** from the list. Listing Mobile Cleaner with an
Uninstall button would be a trap, not a feature.

## Files

### New

| File | Role |
|---|---|
| `android/.../InstalledAppsBridge.kt` | 9th channel: read, and the three handoffs |
| `lib/features/apps/domain/installed_app.dart` | One app; tiered size logic |
| `lib/features/apps/domain/app_inventory.dart` | `AppSort`, `AppFilter`, totals |
| `lib/features/apps/data/installed_apps_repository.dart` | Channel wrapper |
| `.../providers/installed_apps_provider.dart` | One read, re-sorted in memory |
| `.../widgets/app_icon.dart` | Icon with lettered fallback |
| `test/apps_analyzer_test.dart` | 27 cases |

### Changed

- `AndroidManifest.xml` — LAUNCHER `<queries>`, optional `PACKAGE_USAGE_STATS`,
  `xmlns:tools`
- `MainActivity.kt` — registers/disposes the 9th channel
- `apps_screen.dart` — placeholder replaced entirely
- `test/widget_test.dart` — asserted `screen_Apps` (the placeholder key), now
  `apps_list`; new repository override

**Method channels — now 9.** No route change: Apps is already a bottom-nav tab.

## Sorting and filtering

Largest, Name, Updated, Oldest; plus an Installed/All filter for system apps.

`Largest` sorts on `bestKnownBytes` — the full footprint when known, the APK
otherwise — so a device without Usage Access still gets a sensible ordering. A
test proves this matters: **Chatter** has a 40 MB APK but 900 MB of data, so it
outranks **Arcade**'s 300 MB APK. Sorting on APK size alone would have inverted
the two.

Every comparator falls back to the package name, so ties never shuffle between
rebuilds. Apps with no date sort **last**, not first — unknown is not "very
old".

Reading is one platform call that rasterises every icon, so it happens once and
sorting/filtering re-derive in memory. Two tests assert `reads == 1` after
changing sort and filter.

## Icons

Rasterised natively to 96px PNG. Adaptive icons are not `BitmapDrawable`s and
have no intrinsic bitmap, so they are drawn through a `Canvas` rather than
cast — a straight cast would return null for most modern apps. Any failure
falls back to a lettered tile; one bad icon cannot break the list.

## Layout hazards avoided

- Action buttons use `minimumSize: Size(0, 36)` — **height only**. A
  `Size.fromHeight` there is `Size(infinity, 36)`, the `833b7b2` crash.
- The three actions sit in a horizontally scrollable `ListView` (`reverse:
  true`, so Uninstall stays right-aligned). Three labelled buttons overflow a
  narrow phone, and an overflowing `Row` throws rather than clips.
- `ListView.builder` — each row decodes an icon.

## Tests (27 cases)

Fixture: three user apps with deliberately conflicting size/date orderings, and
one system app that is both un-uninstallable and un-openable.

Covers: platform-row parsing including a missing label falling back to the
package name; `totalBytes` null rather than partial; malformed rows dropped;
system filtering and counting; every sort; undated apps last; tie stability;
duplicate packages; totals (1416 MB → `1.4 GB`, verified independently);
`canImproveSizes` false both when access is granted *and* when unsupported;
`withoutPackage` identity when nothing matched; all three actions dispatching;
**uninstall not removing the app locally and not re-reading when cancelled**;
failed actions reporting; disabled actions on system apps; the `25.0 MB app`
label; the usage prompt appearing, opening settings, and being suppressed on
old devices; `reads == 1` across sort and filter changes; empty state.

## Verification status

**Static review only.** `flutter analyze`, `flutter test`, and the Kotlin
compiler have not been run — no toolchain in this workspace. Checked by hand:
brace balance, truncation, symbol resolution, import ordering, unused imports,
80-column Dart / 100-column Kotlin, fixture arithmetic.

Device checks, in priority order:

1. **`InstalledAppsBridge.kt` has never been compiled.** It is the largest new
   native file so far and touches `PackageManager`, `AppOpsManager`,
   `StorageStatsManager`, and `Canvas`.
2. **The manifest changed.** A malformed `<queries>` block or the
   `xmlns:tools` addition can fail the merger at build time. Confirm the APK
   still builds before anything else.
3. **`PACKAGE_USAGE_STATS` in the manifest triggers a lint error** without
   `tools:ignore="ProtectedPermissions"`, which is included — but confirm your
   Gradle setup accepts it.
4. **Icon rasterisation cost.** ~100 apps × a 96px PNG on one background
   thread, all returned in a single channel payload. If the tab is slow to
   open, pass `includeIcons: false` for the first read and fetch icons lazily.
5. Whether Play Console flags `PACKAGE_USAGE_STATS` at submission. It is not
   in the restricted list the way `QUERY_ALL_PACKAGES` is, but it is a special
   access and worth confirming before release.
