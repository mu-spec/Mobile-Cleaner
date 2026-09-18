# Application Identity Migration

Production-release rename of the app and its Android package identity. This is an
identity-only change: no functionality, UI design, permissions, dependencies, or
cleaning/storage behaviour was modified.

## Old → new

| Concern | Old | New |
| --- | --- | --- |
| Product / display name | `Mobile Cleaner` | `Phone Storage Cleaner` |
| Android `namespace` | `com.mobilecleaner.app` | `com.KoreAppsTek.PhoneStorageCleaner` |
| Android `applicationId` | `com.mobilecleaner.app` | `com.KoreAppsTek.PhoneStorageCleaner` |
| Launcher label | hardcoded `"Mobile Cleaner"` | `@string/app_name` → `Phone Storage Cleaner` |
| Kotlin package | `com.mobilecleaner.app` | `com.KoreAppsTek.PhoneStorageCleaner` |
| Kotlin source root | `android/app/src/main/kotlin/com/mobilecleaner/app/` | `android/app/src/main/kotlin/com/KoreAppsTek/PhoneStorageCleaner/` |
| Dart/pubspec package | `mobile_cleaner` | `phone_storage_cleaner` |
| Root widget class | `MobileCleanerApp` | `PhoneStorageCleanerApp` |
| Platform channels | `com.mobilecleaner.app/<name>` | `com.KoreAppsTek.PhoneStorageCleaner/<name>` |
| Launcher icon asset | `assets/branding/phone_cleaner_icon.png` | `assets/branding/phone_storage_cleaner_icon.png` |
| Splash drawable | `res/drawable-nodpi/phone_cleaner_splash.png` | `res/drawable-nodpi/phone_storage_cleaner_splash.png` |

## Platform channels

All ten app-owned `MethodChannel` names were migrated on the Kotlin and Dart sides
together, so no channel pairing changed:

`delete`, `file_scanner`, `hash`, `installed_apps`, `perceptual_hash`,
`photo_quality`, `saf`, `share`, `storage`, `thumbnails`.

External dependency package names (for example `io.flutter.embedding.*`,
`com.android.*`, Phosphor icon identifiers) were deliberately left untouched.

## Historical documents

The `docs/phase-*.md` logs describe work completed while the app still carried the
old identity. Their references were updated to the new identity so the docs stay
runnable and copy-pasteable. Where a phase log needs to be read as a historical
record of what the identity *was* at the time, this file is the authoritative
old → new mapping.

## Intentional remaining references

`docs/identity-migration.md` is the only file that still contains the literal
string `com.mobilecleaner.app`, and it does so on purpose — it is the record of
the migration itself. No build file, manifest, source file, resource, or test
references the old identity.

## Not done in this change

- Release signing configuration (`buildTypes.release` still falls back to the
  debug signing config, exactly as before).
- No keystore created or committed; no secrets added.
- No new dependencies, no AdMob, no analytics, no `INTERNET` permission added to
  the release manifest. The pre-existing debug/profile manifests keep the
  `INTERNET` permission Flutter requires for hot reload.
- `versionCode` / `versionName` unchanged (`1.0.0+1`).
