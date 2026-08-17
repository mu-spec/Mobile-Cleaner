# Phase 26 — Settings

Finish Settings: theme, three cleanup thresholds, permissions, privacy policy,
replay onboarding, about, and version.

## What is there now

| Section | Item |
|---|---|
| Appearance | System / Light / Dark |
| Cleanup defaults | Large-file threshold, Screenshot age, Download age |
| Privacy and data | Permissions, Cleanup history, Privacy Policy |
| About | Replay onboarding, About, App version |

## Thresholds are starting points, not locks

Each tool still shows its own chips. This setting decides what the tool **opens
on**; changing it inside the tool affects only that visit. Settings says so
directly (`settings_defaults_note`), because a user who sets "1 GB" here and
then sees a `100 MB+` chip highlighted in the tool would reasonably think the
setting was ignored.

The three screens were changed from a non-null field to a nullable one:

```dart
LargeFileFilter? _filter;                       // null until the user picks
final filter = _filter
    ?? ref.watch(settingsProvider).value?.largeFileFilter
    ?? LargeFileFilter.defaultFilter;
```

Null means "not chosen this visit", so the saved default applies — but once the
user taps a chip, a later settings rebuild can never yank it back. Getting this
backwards would have made the chips feel broken.

## Enum names are persisted, never indexes

```dart
preferences.setString(largeFileKey, settings.largeFileFilter.name);
```

Storing `index` would mean that adding or reordering a threshold silently
converts a saved choice into a different one. Same for `ThemeMode`, which gets
an explicit `'system' | 'light' | 'dark'` mapping rather than relying on the
framework's enum order. A test asserts the encoded theme is not parseable as an
integer.

Every field decodes independently with its own fallback, so **one corrupt value
cannot reset the others** — also tested.

## No theme flash on launch

`MobileCleanerApp` became a `ConsumerWidget` and falls back to
`ThemeMode.system` while preferences load. That load resolves during the splash
screen, so a saved Light or Dark choice is applied before any real content is
visible.

## Privacy Policy is in-app, not a link

Held in the app deliberately:

- the policy describes behaviour verifiable **in this build**; a web page could
  drift from the code it describes
- it is readable offline, which matters for an app that asks for storage access
- the app has no internet permission, so a link would be the only network-shaped
  thing in it

It states what is actually true of this codebase: nothing leaves the device, no
accounts or analytics, the cleanup history stores no file names, why each
permission is asked for, and that deletion is always confirmed and is permanent.

`About` covers what the app does and — more usefully — **what it will not do**:
no automatic deletion, no promising space it cannot free, no claiming to clean
things Android does not expose.

## Two Flutter/Riverpod traps avoided

1. **`RadioListTile.groupValue` and `onChanged` were deprecated after Flutter
   3.32** in favour of a `RadioGroup` ancestor. The option sheets use plain
   `ListTile`s with a check mark instead, which sidesteps the deprecation
   entirely. Worth knowing since your toolchain is past 3.32.
2. **No `ChangeNotifierProvider`** — discouraged and moved to a legacy import in
   Riverpod 3. Settings uses `FutureProvider` plus a `saveSettings` helper that
   invalidates it, matching the pattern already compiling in this app. I
   drafted a `ChangeNotifier` controller and deleted it before committing.

`saveSettings` takes a **`WidgetRef`**, not a `Ref`.

## Files

**New:** `app_settings.dart`, `settings_repository.dart`,
`settings_provider.dart`, `test/settings_test.dart` (18 cases).

**Changed:** `settings_screen.dart` (rewritten), `app.dart` (theme wiring),
the three tool screens (honour saved defaults), `test/widget_test.dart`.

### `test/widget_test.dart` needed fixing

Settings is now taller than a 420×1000 test surface, so `replay_onboarding` and
`App version` fell below the fold and their taps/finds would have failed. Added
a `scrollSettingsTo` helper and used it in both places. This is the same class
of breakage as the Phase 19 and 23 test fixes — a screen grew, and an old test
assumed it fit.

## Tests (18 cases)

Encoding round-trips; unknown values falling back; `copyWith` isolation; a real
`SharedPreferences` save-and-reload; fresh-install defaults; **one corrupt value
not resetting the rest**; names-not-indexes on disk; every required item
present; theme saving; each threshold changing and updating its displayed value;
**re-picking the current value writing nothing**; stored settings reflected on
open; the defaults note; the privacy sheet opening and stating the key promise;
About stating its limits; the version row.

## Verification status

**Static review only** here — no toolchain in this workspace. Checked by hand:
brace balance (stripping string interpolation first), truncation, symbol
resolution, import ordering and duplicates, unused imports, 80-column limit.

Run `flutter analyze` before building. On device, the two things worth
confirming are that **Dark actually applies immediately** and that a tool opened
after changing its threshold starts on the new value.
