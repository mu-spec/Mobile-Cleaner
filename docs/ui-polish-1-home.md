# UI/UX Polish 1 — Home screen

UI only. No storage calculation, scan logic, file discovery, permission,
deletion, or algorithm was touched, and every navigation destination is
unchanged.

## Before → after

| Before | After |
|---|---|
| Page heading + blurb restating the app name | Removed — the storage card says it better with real numbers |
| Storage card: ring + three equal rows | Ring, then **Used** and **Available** side by side, with internal storage as context |
| "Total storage" | **"Internal storage"** |
| Button labelled "Smart Scan" | Heading "Smart Scan" + button **"Scan now"** + privacy note |
| Quick Tools: 4 large grid cards | One card of 4 compact rows |
| Recommendations below Quick Tools | **Above** — real findings outrank generic tools |
| Ad-hoc spacing per widget | One `HomeMetrics` scale |

## Information hierarchy

Storage first, because it is the question the user opened the app to answer.
**Used** and **Available** are the two figures anyone acts on, so they get
equal weight side by side; the ring stays for the at-a-glance percentage.

### Why "Internal storage"

Android reports the *usable internal partition*, which is always smaller than
the number on the box — a "128 GB" phone reports about 118 GB. Labelling that
"Total storage" invites the user to conclude the app is miscounting. "Internal
storage" is accurate and matches Android's own wording.

It is also demoted to a small context line, since it is not actionable.

## Smart Scan as the primary CTA

Full-width filled button reading **"Scan now"** — the action, not the product
name — under a heading that names the feature. The privacy line sits directly
beneath:

> 🔒 Files stay on your device.

Placed there rather than in Settings because the moment someone is deciding
whether to let a cleaner scan their phone is when the reassurance is worth
something. It is also **verifiably true of this build**: no INTERNET
permission, no HTTP client anywhere in `lib/`.

## Recommended for you — real data only

Unchanged data path. It still composes `screenshotSummaryProvider`,
`duplicatesProvider`, and `videoSummaryProvider` through the Phase 24 rule
engine, and each row still shows the numbers the rule fired on
(*"25 screenshots older than 90 days · 100.0 MB"*).

Nothing is fabricated: on a clean device there is no count badge and no rows.
A test asserts exactly that.

Moved **above** Quick tools — a concrete finding about this device deserves
more prominence than a generic tool list.

## Quick tools

Four large grid cards became one card of compact rows. The grid gave every
secondary tool the same visual weight as the primary action and pushed
recommendations below the fold; rows take roughly half the height and read as
clearly secondary. Subtitles are now useful ("Duplicates, screenshots, large
images") rather than filler ("Review media").

Same four destinations, same four keys.

## Consistency

`HomeMetrics` centralises spacing (26 section / 14 row / 12 heading), padding,
icon size (20 in a 40 tile), and a 56dp minimum row height. `HomeSectionHeader`
and `HomeIconTile` give every section identical typography and iconography.
Card radius comes from the theme, unchanged.

All colours are theme colours, so light and dark both work. No gradients, no
animations, no fake data, no ads.

## The trap I nearly walked into

Renaming the button to "Scan now" removes the text `'Smart Scan'` from Home —
and **five existing tests in `widget_test.dart` use `find.text('Smart Scan')`
as their proof of having landed on Home.** All five would have failed.

Rather than edit five working tests, I added the section heading "Smart Scan"
above the button. That is better hierarchy on its own merits — a heading naming
the feature and a button stating the action — and it preserves the assertions.

Every other Home key is preserved deliberately: `home_dashboard`,
`smart_scan_button`, `home_settings_button`, `storage_percentage`,
`total_storage`, `used_storage`, `free_storage`, `quick_tools_section`,
`quick_photos`, `quick_files`, `quick_apps`, `quick_permissions`,
`recommendations_section`, `recommendations_title`, `recommendations_count`,
`recommendations_message`, `recommendations_scan`, `recommendation_*`,
`home_history_card`.

## Tests

New `test/home_screen_test.dart`, 22 cases: hierarchy and visual ordering
(storage before scan, recommendations before tools); "Internal storage" present
and "Total storage" absent; the CTA text, width, and privacy note; no invented
recommendations on a clean device and real figures when there are findings;
all four tool rows with a ≥48dp touch target; history hidden until earned;
**dark mode, 1.8× text scale, a 320×560 screen, and a 100%-full device**; and a
guard that every navigation destination string is unchanged.

All byte figures were recomputed independently before being asserted.

## Verification

Structural audit clean: brace balance with string interpolation stripped,
imports ordered and all resolving, no unused imports, no truncation.

**`flutter analyze` and `flutter test` have not been run here** — still no
toolchain in this workspace. Please run both. Given the last run was clean, I
expect this to be too, but the new test file has never executed.
