# Phase 19 — Photo Cleaner Dashboard

Build the Photos tab properly: Duplicate Photos, Screenshots, Large Photos, and
Similar Photos (coming next), each with what it could recover.

```
Photo Cleanup

Duplicate Photos      640 MB
Screenshots           820 MB
Large Photos          1.4 GB
Similar Photos        Analyze
```

## What replaced what

The Photos tab was a static list of link tiles. It is now a dashboard with a
real figure per tool, so the tab answers *where is my storage going* before the
user opens anything.

### New files

| File | Role |
|---|---|
| `lib/features/files/domain/photo_cleanup_summary.dart` | `PhotoCleanupTool`, `PhotoCleanupEntry`, `PhotoCleanupSummary` |
| `lib/features/files/presentation/providers/photo_cleanup_provider.dart` | `photoCleanupProvider`, `refreshPhotoCleanup` |
| `test/photo_cleanup_dashboard_test.dart` | 15 cases |

### Rewritten

- `lib/features/photos/presentation/screens/photos_screen.dart` —
  `StatelessWidget` → `ConsumerWidget`, now the dashboard.

### Changed

- `test/widget_test.dart` — the bottom-tab test asserted
  `Key('photos_tools')`, which no longer exists; it now asserts
  `Key('photo_cleanup_dashboard')`. The offline overrides gained
  `fileHashRepositoryProvider`, because the Photos tab now reaches the hash
  channel through the duplicate scan and would otherwise spin forever in tests.

No new route, no new screen, no new scan, **no new delete path.** This screen
reports and routes only.

## Composed, not re-scanned

`photoCleanupProvider` watches the three existing tool providers:

| Row | Source |
|---|---|
| Duplicate Photos | `photoDuplicatesProvider` (Phase 18) |
| Screenshots | `screenshotSummaryProvider(ScreenshotGroup.all)` (Phase 15) |
| Large Photos | `largePhotoSummaryProvider(LargePhotoFilter.over5mb)` (Phase 16) |

Consequences that matter:

- A figure on the dashboard is **the same figure the tool shows**, because it
  came from the tool. They cannot drift apart.
- Opening a tool after the dashboard has loaded reuses the cached scan rather
  than hitting the device again.
- The three futures are started together and awaited afterwards, so the wait is
  the slowest scan, not the sum. Same pattern as `smartScanProvider`.
- `refreshPhotoCleanup(ref)` invalidates the three underlying **scan**
  providers; the summaries and the dashboard rebuild from them.

## Duplicates report *reclaimable*, not *occupied*

Two 6 MB copies occupy 12 MB, but the tool always keeps one, so the row shows
**6 MB**. Promising 12 MB and delivering 6 MB would be a lie the tool is
structurally incapable of honouring.

## The headline does not double count

The tools overlap by design — a 12 MB duplicated screenshot is a duplicate, a
screenshot, *and* a large photo. Each row shows its own honest figure, but
`PhotoCleanupSummary.totalBytes` de-duplicates by URI. In the test fixture the
rows sum to 53 MB while the truthful total is 47 MB, and when the figures
disagree the card shows an explicit note (`photo_cleanup_overlap_note`).
Same reasoning as `SmartScanResult`.

## Similar Photos

Listed, not hidden, and honest about its state:

- trailing value is **`Analyze`**, never a size it has not measured
- subtitle reads **`Coming next`**
- `PhotoCleanupTool.similarPhotos.isAvailable == false`
- tapping shows a SnackBar (`similar_photos_coming_soon`) explaining that
  duplicates today are matched byte for byte — rather than routing nowhere,
  which would be an unexplained dead row

It has no route and no screen. **No AI, no perceptual matching was added.**

## Layout hazards avoided

- `Review Photos` is wrapped in `SizedBox(width: double.infinity)` locally,
  because the theme's `minimumSize` was fixed to `Size(0, 56)` in `833b7b2` and
  no longer stretches buttons.
- Row labels are `Expanded` + `maxLines: 1` + `ellipsis`, so a long tool name
  cannot overflow.
- The dashboard is a `ListView` with `AlwaysScrollableScrollPhysics` inside a
  `RefreshIndicator`; four fixed rows, so `.builder` buys nothing here.

## Tests

Fixture: a 6 MB duplicate pair, two screenshots (2 MB + 3 MB), a 30 MB
panorama, and a 200 KB thumbnail nothing matches.

Domain — tool order; duplicates reported as reclaimable (6 MB, not 12 MB);
screenshots 5 MB; large photos 42 MB; Similar Photos never carries a figure;
headline de-duplicates to 47 MB / 5 photos with `hasOverlap`; findings ranked
largest-first with pending tools excluded; a tidy library is empty but still
lists all four tools.

Widget — heading and headline; all four values including `Analyze`;
`Coming next`; tapping Similar Photos shows the SnackBar and throws nothing;
overlap note present; all three built rows tappable; `Review Photos` enabled
when something was found and disabled when not; tidy state shows `None` per row
rather than a blank tab; **the dashboard issues exactly three scans**, proving
it composes the tools instead of scanning independently.

## Verification status

**Static review only.** `flutter analyze` and `flutter test` have **not** been
run — there is no Dart/Flutter toolchain in this workspace. Checked by hand:
brace/paren balance, truncation, symbol resolution, import ordering
(`directives_ordering`), unused imports, 80-column limit, and the fixture
arithmetic. Static review has previously missed a real crash (`833b7b2`), so
treat this as unverified until `flutter pub get && flutter analyze &&
flutter test` runs locally.

One behavioural change worth re-checking on device: `test/widget_test.dart`
needed a new provider override, which is a signal that the Photos tab now
touches the hash channel on tab open. On a large library that means the tab
does real work the moment it is selected.
