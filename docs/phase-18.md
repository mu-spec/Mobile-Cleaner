# Phase 18 — Duplicate Photos

Use the duplicate engine specifically for images. Group copies visually and let
the user choose which one to keep.

## What was built

A photo-only front end onto the **existing Phase 17 duplicate engine**. No new
detection logic, no second deletion path, no AI.

```
scan (images + downloads)  ->  keep images only  ->  same size
                           ->  candidate group   ->  hash  ->  exact duplicate
```

`DuplicateDetector` is untouched. Phase 18 changes only *what goes in* and *how
the result is shown*.

### New files

| File | Role |
|---|---|
| `lib/features/files/domain/photo_duplicates.dart` | `PhotoDuplicates.isPhoto` / `.only` — narrows a scan to images |
| `lib/features/files/domain/duplicate_keep_selection.dart` | Which copy of each set the user keeps |
| `lib/features/files/presentation/providers/photo_duplicates_provider.dart` | `photoDuplicateScanProvider`, `photoDuplicatesProvider` |
| `lib/features/files/presentation/screens/photo_duplicates_screen.dart` | `PhotoDuplicatesScreen` |
| `test/photo_duplicates_test.dart` | 17 cases |

### Changed files

- `lib/app/router/app_router.dart` — new route `/photo-duplicates`
  (`AppRoutes.photoDuplicates`). 15 declared routes, 15 builders.
- `lib/features/photos/presentation/screens/photos_screen.dart` — new
  **Duplicate photos** entry. The existing entry was relabelled
  *All duplicates — identical copies of any file type* so the two tools are
  distinguishable. Its key and route are unchanged.

## Why images are filtered, not queried

`FileCategory.images` alone would miss a picture saved into Downloads by a
messaging app — one of the most common sources of a second copy. The scan
therefore requests `images` **and** `downloads`, then
`PhotoDuplicates.only()` drops everything whose category is not `images` and
whose MIME type is not `image/*`. An identical video pair is not shown here; it
belongs to the general Duplicates tool.

## Choosing which copy to keep

`DuplicateKeepSelection` maps group hash → kept URI.

- Default keeper is `DuplicateGroup.original`, the oldest copy — usually what
  the camera wrote rather than a re-download.
- `keep(group, file)` ignores a file that is not in the group, so a stale
  callback cannot protect an unrelated photo.
- If the chosen copy disappears (deleted, or gone after a rescan) `keptUri`
  falls back to the oldest remaining copy rather than returning nothing.
- `removable(group)` is *always* `copyCount - 1` items. Every selection path —
  per-photo tap, per-set button, global select — derives from it, so **no code
  path can select every copy of a photo.**
- `prune(groups)` drops choices for groups that no longer exist.

Switching the keeper also deselects that photo in the same `setState`, so a
photo can never be simultaneously kept and queued for deletion.

## UI

Each set is a card:

- header — `N identical photos · X MB each` and `save Y MB`
- a **horizontal strip of picture cells**, so copies are compared side by side
  rather than read as file names
- each cell — thumbnail, file name, relative date, folder, and either a `Keep`
  button or a `Kept` lock badge
- kept cell gets a primary-coloured 3dp border and a lock badge; a selected
  cell gets an error-coloured border and a tick badge
- per-set `Select N extra copies` / `Clear this set`
- header row `Select copies` / `Clear all` across every set

The list is `ListView.builder`; each strip is also a `ListView.builder`. A group
holds several decoded thumbnails, so eager construction would stall the UI
thread — the same failure mode fixed in `59999c8`.

### Layout hazards deliberately avoided

- `SelectionActionBar` sits in the body `Column` below the `Expanded` list,
  never in `Scaffold.bottomNavigationBar` (`f3d1c23`).
- The `Keep` button uses `minimumSize: Size(0, 30)` — a **height only**. A
  `Size.fromHeight` there would be `Size(double.infinity, 30)` and would throw
  *BoxConstraints forces an infinite width* inside the horizontal strip. That
  is exactly the bug behind `833b7b2`.
- Cells are wrapped in a fixed-width `SizedBox`, so nothing asks a horizontal
  `ListView` for unbounded width.

## Deletion

Unchanged. `runDeleteFlow` — the single Phase 12
`Select → Review → Confirm → Delete → Result` path. On success the selection is
pruned and `photoDuplicateScanProvider` is invalidated.

## Tests (`test/photo_duplicates_test.dart`)

Fixture: a 5 MB photo trio, a same-size non-matching photo pair, an identical
**video** pair, an 8 MB photo duplicated across gallery and Downloads, and a
unique photo.

- images-only filter keeps the Downloads picture, drops the video
- the engine is reused unchanged: 2 groups, no video
- only size-matched photos are hashed (7 of 8)
- reclaimable = 18 MB (5×2 + 8×1)
- keep-selection: default oldest; user override; **one copy always retained for
  every possible choice**; foreign file rejected; totals unchanged by choice;
  pruning
- provider requests `images` + `downloads` with the hashing floor
- screen: totals, visual grouping, kept photo not tappable, keeper switching,
  keeping a selected photo deselects it, select-all never selects a keeper,
  per-set selection, empty state

## Not done

- No perceptual/similar-photo matching. Byte-identical only. *No AI.*
- Blurry photos remain listed as upcoming.

## Verification status

**Static review only.** `flutter analyze` and `flutter test` have **not** been
run — no Dart/Flutter toolchain exists in this workspace. Checked by hand:
brace/paren balance, no truncation, symbol resolution, import ordering
(`directives_ordering`), unused imports, 80-column limit. Static review has
previously missed a real crash (`833b7b2`), so treat this as unverified until
`flutter pub get && flutter analyze && flutter test` is run locally.
