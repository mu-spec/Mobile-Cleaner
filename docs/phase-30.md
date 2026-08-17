# Phase 30 — Final QA

## What this phase is, and what I could actually do

Phase 30 is **device testing**. I have no Android device, emulator, or
toolchain, so I cannot execute it. Saying otherwise would be the most damaging
thing I could do at the end of a 30-phase build.

What I did instead, in order of value:

1. **Audited the nine scenarios statically** and found two real bugs.
2. **Automated every scenario that can be automated** — 24 new regression tests.
3. **Wrote `docs/qa-test-plan.md`** — an executable plan for the parts only a
   device can answer, ordered by risk.

---

## Bugs found and fixed

### 1. A second, divergent byte formatter

`storage_overview_card.dart` carried a private `_formatBytes` that never
handled bytes below 1 KB. Home rendered 500 bytes as **"0.5 KB"** while every
other screen said **"500 B"**, using `ByteFormatter`. It also lacked the
negative-input guard.

Deleted; Home now uses the shared formatter. This is exactly the class of bug
that survives 29 phases: harmless-looking duplication that silently diverges.

### 2. A hardcoded colour that ignored dark mode

Free storage was a fixed `Color(0xFF22C55E)` — a light-mode green — instead of
a theme colour. Now `colorScheme.primary`.

The other hardcoded colours were checked and **left alone deliberately**:
category accents are brand colours by design, and the duration/video badges are
white-on-black overlays drawn on top of thumbnails, where a theme colour would
be wrong.

### 3. Lint debt

Four files had `directives_ordering` violations and one Kotlin line exceeded
100 columns. Fixed, so `flutter analyze` output is not noisy when you run it.

---

## Scenario coverage: what is automated vs. device-only

| Scenario | Automated | Needs a device |
|---|---|---|
| Fresh install | Defaults, empty-library handling | Onboarding flow, splash routing |
| Permission denial | Classification, no-retry rule, delete-during-revoke | The actual system dialog |
| 90%+ full storage | Percentage math, full/zero/inconsistent inputs | Real `StatFs` figures |
| Thousands of photos | 5,000-file aggregation, 1,000-group detection, lazy build | **Frame times, real memory** |
| Duplicate files | Leader grouping, one-copy-kept invariant | Real photo content |
| Deletion | Partial/cancelled results, history recording | **Irreversible platform behaviour** |
| Dark mode | Both themes build; infinite-width regression guarded | Visual contrast |
| App restart | Settings + history persist; scans deliberately not cached | Real process death |
| Offline use | No network code, no INTERNET permission | Airplane-mode pass |

**Offline was fully verifiable and passes:** the manifest declares no INTERNET
permission, there is no HTTP client anywhere in `lib/`, and no dependency
performs network I/O. The privacy policy's central claim is therefore true.

One test deserves calling out: the dark-mode group asserts
`filledButtonTheme.minimumSize.width == 0` in **both** themes. That is the
`Size.fromHeight(56)` bug from `833b7b2` — the one that took four wrong guesses
before you found it — pinned so it cannot come back.

---

## Honest status of the whole project

**Everything from Phase 6 to Phase 29 was written without a compiler.** You
have compiled exactly once, and it failed on the first file it reached
(`valueOrNull`). That tells us nothing about the other 153 Dart files or the
nine Kotlin bridges.

563 tests exist. **None have ever been run.**

Ranked risk:

1. **`flutter analyze` errors** — near-certain there are more.
2. **Android 7/8** — no device has ever run this; no `StorageStatsManager`,
   legacy thumbnails, legacy file walk.
3. **Kotlin compilation** — `PerceptualHashBridge`, `PhotoQualityBridge`,
   `InstalledAppsBridge` have never been through a compiler.
4. **Deletion on Android 10 and 11+** — different paths from the Android 9 one
   you verified, and irreversible if wrong.
5. **Large text scale** — fixed in Phase 29, never seen rendered.

## The one thing to do next

```
flutter analyze
```

Not a build — analyze. It reports every error in the project at once, instead
of stopping at the first bad file. Paste the output and I will work through it.
Until that is clean, device testing will mostly be re-discovering compile
errors.
