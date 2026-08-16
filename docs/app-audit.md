# App audit — Phases 0–15

Static audit of every route, button, handler and platform channel.
HEAD `8824b3c`. 85 Dart + 6 Kotlin files, 122 test cases across 16 files.

**Method: static tracing only.** No SDK is installed, so nothing here was
compiled or executed. This confirms wiring, not runtime behaviour. Items
marked *unverified* need a device.

## Navigation

13 routes declared, 13 route builders — no dangling routes.

| Route | Screen | Reachable from |
| --- | --- | --- |
| `/splash` | Splash | app launch |
| `/onboarding` | Onboarding | splash (first run), Settings replay |
| `/permissions` | Permission education | splash, Settings, Quick Tools, error views |
| `/home` | Home | bottom nav |
| `/clean` | Smart Scan | bottom nav, Home Smart Scan, recommendations |
| `/photos` | Photos | bottom nav, Quick Tools |
| `/files` | Files | bottom nav |
| `/large-files` | Large Files | Files card, Quick Tools, Smart Scan |
| `/downloads-cleaner` | Downloads Cleaner | Files card, Smart Scan |
| `/apk-cleaner` | APK Cleaner | Files card, Smart Scan |
| `/screenshot-cleaner` | Screenshot Cleaner | Photos |
| `/apps` | Apps | bottom nav, Quick Tools |
| `/settings` | Settings | bottom nav, Home app bar |

## Interactive elements

Every `onPressed`/`onTap` resolves to a real handler. No empty callbacks, no
`TODO`, no `UnimplementedError` anywhere in `lib/`.

- **Home** — Settings, Smart Scan, 4 Quick Tools (Photos, Large Files, Apps,
  Permissions), Recommendations, pull-to-refresh.
- **Files** — rescan, 3 cleaner cards, 6 category cards, largest-files rows.
- **Smart Scan** — rescan, 3 check rows, Review Cleanup, pull-to-refresh.
- **Photos** — Screenshots. Duplicates / Similar / Blurry shown disabled as
  upcoming.
- **Screenshots / Downloads / APK cleaners** — filter or sort chips, rescan,
  select, Select all, Clear, Delete, long-press details, pull-to-refresh,
  cancel selection.
- **Category browsers** — sort menu, sort chips, search, Select all, Clear,
  Delete, long-press details.
- **Large Files** — 3 size chips, rescan, pull-to-refresh. Read-only by design.
- **Settings** — permissions, replay onboarding. Appearance and App version are
  intentionally informational.
- **Onboarding** — Next / Get started, Skip.
- **Permissions** — grant, open settings, continue.

## Platform channels

Five channels, each paired Dart ↔ native and registered in `MainActivity`:

| Channel | Methods | Bridge |
| --- | --- | --- |
| `/storage` | `getStorageInfo` | inline `StatFs` |
| `/file_scanner` | `scanFiles` | `FileScannerBridge` |
| `/thumbnails` | `getThumbnail` | `ThumbnailLoader` |
| `/saf` | `getGrantedTrees`, `requestTreeAccess`, `releaseTree`, `isAccessRequired` | `SafAccessBridge` |
| `/delete` | `deleteFiles` | `DeleteBridge` |

All 8 invoked methods have a native counterpart. No orphan providers, no
unreferenced Dart files.

## Deletion

One path. All four selectable screens call `runDeleteFlow`, the only caller of
`deleteRepositoryProvider`. Each refreshes its scan and clears deleted items
afterwards; the flow refreshes storage totals centrally.

## Phase coverage

| Phase | Status |
| --- | --- |
| 0–3 shell, theme, nav, onboarding, permissions | present |
| 4 real storage via `StatFs` | present |
| 5 Home dashboard | present |
| 6 scanner + `ScannedFile` model | present |
| 7 six categories | present |
| 8 thumbnails + 5 sort orders | present |
| 9 Large Files, 3 size filters | present |
| 10 Downloads Cleaner, 4 age filters, multi-select | present |
| 11 APK Cleaner | present |
| 12 safe delete | present |
| 13 Cleanup Complete | present |
| 14 Smart Scan | present |
| 15 Screenshot Cleaner | present |

## Gaps

1. **Apps tab is a placeholder.** Reachable from bottom nav and Quick Tools but
   shows "coming in a future phase". No phase 0–15 specified it.
2. **Photos: Duplicates / Similar / Blurry** are listed as upcoming, correctly
   disabled.
3. **Large Files has no selection or delete** — browse only. Deletion of a
   large file is done through its category.
4. **`[DELETE_DEBUG]` logging is still active** from the diagnostic commit. It
   is verbose and should be removed before release.
5. **Nothing has been compiled or tested in this workspace.** `flutter analyze`
   and `flutter test` have not been run since the SDK was removed.

## Recommended before release

```bash
flutter pub get && flutter analyze && flutter test
```

Then on a device: launch → onboarding → permissions → Home totals → each
bottom tab → each cleaner → select → Delete → approve → Cleanup Complete →
verify the file is gone and free space increased. Repeat declining the Android
dialog and confirm nothing is removed.
