# Phase 25 — Cleanup History

Store locally: date, number of files removed, space recovered.

```
Today          1.8 GB cleaned
August 11      620 MB cleaned
```

## Recorded in one place

Recording happens inside `runDeleteFlow` — the single Phase 12 delete path
every tool routes through. So every deletion from every screen is logged, and
no tool can forget to log. Adding a future cleaner requires no history work.

It is fired with `unawaited` and swallows its own errors: history is a
convenience, and a storage failure must never turn a successful deletion into
an error the user sees, or delay the result screen.

Only `result.deletedCount` and `result.freedBytes` are recorded — files Android
**confirmed** were removed. A partially-failed batch logs what actually went,
not what was attempted.

## No file names are stored

The log holds three fields per cleanup: a timestamp, a count, and a size.

A record of exactly *which* files someone deleted is far more sensitive than a
count, and it is not needed to answer the question this feature exists for —
"how much have I cleaned, and when". A test asserts the stored JSON keys are
exactly `{at, files, bytes}`, so a future change that starts persisting paths
fails the suite. The screen states this too: *"Kept on this device only. No file
names are stored."*

## Grouped by calendar day

The spec's example shows days, not individual deletions, and that is what a
person means — three cleanups this afternoon read as one line, `Today · 1.8 GB
cleaned`. `CleanupEntry.day` discards the time; `CleanupHistory.byDay` combines
and orders newest first. A day holding several cleanups also says so
(`16 files removed · 2 cleanups`).

Dates render through the existing `DateFormatter.relative`, so recent days read
`Today` / `Yesterday` and older ones fall back to an absolute date.

## Corrupt storage never crashes the app

`decode` returns an empty history on any failure, and drops unreadable rows
individually while keeping the good ones. Losing a corrupt log is a minor
annoyance; crashing on launch over a convenience feature is not.

A cleanup that removed nothing is never recorded — neither at write time nor
when parsing — so the lifetime total cannot be inflated by no-op rows.

## Capped at 200 entries

`SharedPreferences` loads its whole contents into memory, so the log must not
grow unbounded. Newest-first ordering means trimming drops the oldest.

## Files

**New:** `cleanup_entry.dart`, `cleanup_history.dart`,
`cleanup_history_repository.dart`, `cleanup_history_provider.dart`,
`cleanup_history_screen.dart`, `cleanup_history_card.dart`,
`test/cleanup_history_test.dart` (24 cases).

**Changed:** `delete_flow.dart` (records the cleanup), `home_screen.dart`
(summary card), `settings_screen.dart` (entry point), `app_router.dart`
(`/history` — 18 routes, 18 builders).

No new channel, no native change, **no new delete path.** The history screen is
read-only; its only action is clearing the log, which asks first and states
plainly that files are not affected.

## Home card hides itself

Before the first cleanup, `CleanupHistoryCard` renders `SizedBox.shrink()`. A
card reading "0 B recovered" on a fresh install is noise, not information.

## Tests (24 cases)

Fixture reproduces the spec example exactly: two cleanups today totalling
1.8 GB, one on 11 August at 620 MB.

Covers: JSON round-trip; **no file names in storage**; corrupt rows dropped;
day grouping ignoring time; newest-first ordering; same-day combination
(1200 + 643 MB → `1.8 GB`); lifetime totals (2463 MB → `2.4 GB`, 25 files);
windowed totals excluding older days; four kinds of corrupt storage; a partly
corrupt log keeping readable rows; a real `SharedPreferences` save-and-reload;
no-op cleanups not recorded; the cap; clearing; the screen's day rows, totals
and privacy note; empty state; clear-confirm and clear-cancel; and the Home
card both showing a total and hiding when empty.

Every byte figure was recomputed independently before being asserted.

## Verification status

**Static review only** here — no toolchain in this workspace. Checked by hand:
brace balance (stripping string interpolation first, which produced a false
positive on the raw count), truncation, symbol resolution, import ordering,
unused imports, 80-column limit, and all arithmetic.

Swept for the Riverpod 3 breakage that failed your last build: no
`valueOrNull`, no `StateProvider`, no `requireValue` in any new file.
`recordCleanup` deliberately takes a **`WidgetRef`**, not a `Ref` — they are
distinct types, and the only caller is the widget-layer delete flow.

Please run `flutter analyze` before building. On device, the thing to confirm
is that deleting from any tool produces a row here with the right size.
