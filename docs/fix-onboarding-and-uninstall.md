# Fix — onboarding skipped on fresh install, and Uninstall doing nothing

Two device-reported bugs. Both were in `AndroidManifest.xml`, and neither could
have been caught by `flutter analyze` or `flutter test` — they are Android
platform configuration, not Dart.

---

## Bug 1 — No onboarding or permission screens on a "fresh" install

### It was not actually a fresh install

The Dart logic is correct:

```dart
return preferences.getBool('onboarding_completed') ?? false;
```

A genuinely empty preference store returns `false` and shows onboarding. So the
store was **not empty** — something had put the flags back.

### Cause: Android auto-backup

`android:allowBackup` defaults to **true** when unset. Android then backs up the
app's `SharedPreferences` to Google Drive and **restores them automatically on
reinstall**. So:

1. You installed an earlier build and completed onboarding → flags saved.
2. Android backed those flags up.
3. You uninstalled and installed the new APK.
4. Android silently restored the flags **before first launch**.
5. Splash read `onboarding_completed == true` and went straight to Home.

The app was behaving exactly as designed on data that should not have survived.

### Fix

```xml
<application
    android:allowBackup="false"
    android:fullBackupContent="false"
    tools:ignore="DataExtractionRules">
```

Correct for this app on the merits, not just to fix the symptom: the only
persisted data is local settings and a cleanup history that is meaningless on a
different device. There is nothing worth restoring, and silently carrying state
across installs makes testing unreliable — as it just did.

### To verify

A restored backup can still be sitting in your Google account. Before
retesting:

```
adb shell bmgr wipe com.google.android.gms/.backup.BackupTransportService com.mobilecleaner.app
```

Or simply: uninstall, then **turn off backup for the app** in Google Drive
settings, then install. Uninstalling alone does not clear the cloud copy.

---

## Bug 2 — Uninstall button did nothing, for every app

### Cause: a missing normal permission

Since **Android 9 (API 28)**, firing `ACTION_DELETE` to uninstall a package
requires:

```xml
<uses-permission android:name="android.permission.REQUEST_DELETE_PACKAGES" />
```

Without it the system **silently drops the intent**. No dialog, no exception,
no crash — `startActivity` returns normally, so my code returned `true` and the
UI had nothing to report. That is precisely why the button looked dead rather
than broken.

It is a *normal* permission: granted at install, no runtime prompt, nothing for
the user to approve.

### Fix

Added the permission. Also added a `Log.w` when an intent fails to start, so a
future failure of this kind leaves a trace in logcat instead of being invisible.

### Why the tests passed anyway

`apps_analyzer_test.dart` asserts the Uninstall button *dispatches* to the
repository — and it does. The repository called the channel, the channel called
`startActivity`, and Android threw it away. Every layer behaved correctly; the
manifest was wrong. No unit test could have found this.

---

## Files changed

- `android/app/src/main/AndroidManifest.xml` — `REQUEST_DELETE_PACKAGES`,
  `allowBackup="false"`, `fullBackupContent="false"`
- `InstalledAppsBridge.kt` — log failed intent launches
- `test/final_qa_test.dart` — two regression tests pinning the fresh-install
  contract

## What this says about the remaining risk

Both bugs were **manifest configuration**, a category that:

- `flutter analyze` does not inspect
- `flutter test` cannot reach
- my static review had no way to catch, because the code was correct

The lesson for the rest of QA: the Dart and Kotlin may well be fine while the
app still misbehaves. Keep testing on-device, and when something looks dead
rather than broken, suspect the manifest.

## Verification status

Manifest XML parsed and validated. Kotlin brace-balanced, imports ordered, no
long lines. **Not compiled** — rebuild and confirm:

1. Uninstall now shows Android's confirmation dialog.
2. After clearing the backup, a fresh install shows onboarding.
