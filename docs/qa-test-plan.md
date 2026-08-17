# Final QA — Device Test Plan

Phase 30 is device testing. **I cannot run it** — there is no Android device,
emulator, or toolchain in my workspace. What follows is the plan for you to
execute, ordered so the cheapest checks that would block everything else come
first.

Mark each row PASS / FAIL / BLOCKED. A FAIL with a screenshot of the error
screen is now enough to diagnose most problems, because Phase 27 renders the
platform error code on screen.

---

## Step 0 — Gates (do these first)

| # | Check | Expected |
|---|---|---|
| 0.1 | `flutter analyze` | **Zero errors.** Warnings acceptable; errors block everything |
| 0.2 | `flutter test` | All ~560 tests pass |
| 0.3 | `flutter build apk --release` | Builds |

**Do not proceed past a failing 0.1.** Every phase from 6 onward was written
without a compiler; analyze will surface the whole backlog at once instead of
one build failure at a time.

---

## Devices

Minimum useful matrix. The app's floor is **Android 7 (API 24)**.

| Slot | Why it matters |
|---|---|
| Android 14/15 | Your friend's device; scoped storage, predictive back |
| Android 11 or 12 | Where `Invalid token LIMIT` broke scanning |
| Android 9 or 10 | Legacy delete path + `WRITE_EXTERNAL_STORAGE` |
| Android 7 or 8 | **Never exercised.** No `StorageStatsManager`, legacy thumbnails |

---

## 1. Fresh install

| # | Step | Expected |
|---|---|---|
| 1.1 | Install, launch | Splash → Onboarding (not Home) |
| 1.2 | Complete onboarding | Permission education appears |
| 1.3 | Force-stop, relaunch | Straight to Home — onboarding does not repeat |
| 1.4 | Home before any scan | No history card (hides until first cleanup) |
| 1.5 | Settings | Theme = System, thresholds at defaults |

## 2. Permission denial

| # | Step | Expected |
|---|---|---|
| 2.1 | Deny at the prompt | Error reads **"Storage access is required"** |
| 2.2 | Same screen | **"Review permissions"** shown; **no "Try again"** |
| 2.3 | Grant, return | Files list populates without restarting the app |
| 2.4 | Revoke in system settings while running | No crash; error state, not a blank screen |
| 2.5 | Android 13+ | Only media permissions requested — never `MANAGE_EXTERNAL_STORAGE` |

## 3. Storage over 90% full

| # | Step | Expected |
|---|---|---|
| 3.1 | Fill to >90% | Ring shows a plausible % matching system Settings ±2 |
| 3.2 | Delete ~1 GB | Free figure **increases** on the completion screen |
| 3.3 | Near-zero free space | Deletion still works; no crash |

## 4. Thousands of photos

Needs a device with **3,000+ images**. This is where Phase 28 matters.

| # | Step | Expected |
|---|---|---|
| 4.1 | Open Photos | Interactive within ~5s; no ANR |
| 4.2 | Fling the list hard | No stutter; thumbnails fill in progressively |
| 4.3 | Scroll to the end, then back | **Memory plateaus, does not climb** — the `autoDispose` fix |
| 4.4 | `flutter run --profile`, repeat 4.2 | No sustained red bars in the frame graph |
| 4.5 | Rotate mid-scroll | No crash |
| 4.6 | Settings → Font size **maximum** | Chip bars grow; **labels not clipped** |

## 5. Duplicate files

| # | Step | Expected |
|---|---|---|
| 5.1 | Copy a photo 3× with different names | All three appear in one group |
| 5.2 | Check the group | **One copy marked "Kept"** and not selectable |
| 5.3 | "Select copies" | Selects N−1, never all N |
| 5.4 | Large library (>400 candidates) | **Finds more than a pre-Phase-28 build** — the truncation fix |
| 5.5 | Similar Photos | Groups a burst; does *not* group unrelated scenes |
| 5.6 | Similar Photos | One shot marked **Suggested Keep**, or "too close to call" |

## 6. Deletion — the irreversible path

Use **disposable files only.**

| # | Step | Expected |
|---|---|---|
| 6.1 | Select 3, Delete | Review sheet lists them with the correct total |
| 6.2 | Cancel | **Nothing deleted**; result says cancelled, not failed |
| 6.3 | Confirm | Android's own dialog may appear; files disappear from the list |
| 6.4 | Verify in a file manager | Files are **actually gone** |
| 6.5 | Completion screen | Count and freed bytes match what was selected |
| 6.6 | Settings → Cleanup history | New row with the correct date and size |
| 6.7 | Delete a file already removed elsewhere | Counts as **success**, not failure (Phase 27 fix) |
| 6.8 | Android 9/10 specifically | Legacy delete path works — **least-verified code in the app** |

## 7. Dark mode

| # | Step | Expected |
|---|---|---|
| 7.1 | Settings → Dark | Applies immediately, no restart |
| 7.2 | Every tab | No black-on-black or white-on-white |
| 7.3 | Video/duration badges | Still legible (white on dark overlay by design) |
| 7.4 | Kill and relaunch | Dark persists |
| 7.5 | System theme + device toggle | App follows |

## 8. App restart

| # | Step | Expected |
|---|---|---|
| 8.1 | Change all 3 thresholds, force-stop, relaunch | All retained |
| 8.2 | Open a tool | Opens on **its saved threshold** |
| 8.3 | Clean up, force-stop, relaunch | History intact |
| 8.4 | Relaunch after deleting files externally | No stale entries — scans are deliberately not cached |
| 8.5 | Background 10 min, return | No crash, no blank screen |

## 9. Offline use

| # | Step | Expected |
|---|---|---|
| 9.1 | Airplane mode, full pass | **Everything works identically** |
| 9.2 | App info → Permissions | **No network/internet permission listed** |
| 9.3 | Duplicates + Similar Photos offline | Work — all hashing is on-device |

---

## Known-risk list (check these first if short on time)

Ranked by my estimate of failure probability:

1. **`flutter analyze` errors.** Phases 6–29 were never compiled. Highest.
2. **Android 7/8.** No `StorageStatsManager`, legacy thumbnail API, legacy
   file walk. Never exercised on any device.
3. **Kotlin compile.** `PerceptualHashBridge`, `PhotoQualityBridge`, and
   `InstalledAppsBridge` have never been through a compiler.
4. **Deletion on Android 10 and 11+.** Different code paths from the Android 9
   one you tested. Irreversible if wrong.
5. **Large text scale.** Fixed in Phase 29 but never seen rendered.

## Reporting a failure

Include: device + Android version, the screen, the **error detail line**
(small print under the headline), and `flutter logs` output if it crashed.
