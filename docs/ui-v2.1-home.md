# Mobile Cleaner UI V2.1 — Home Screen Redesign

Presentation-only milestone. No storage calculation, scan algorithm, native
bridge, permission, deletion, or persistence code changed.

## Visual direction

Teal is gone as the Home identity. The new family:

| Token | Value | Role |
| --- | --- | --- |
| `AppColors.brandBlue` | `#1246B8` | Major brand moments and hero surfaces |
| `AppColors.actionBlue` | `#1F63E9` | Navigation, links, icons, compact actions |
| `AppColors.navy` | `#172033` | Strong light-theme headings |
| `AppColors.cleanupOrange` | `#FF850A` | Recoverable-space/cleanup emphasis only |
| `AppColors.softOrange` | `#FFF1DF` | Warm low-emphasis cleanup surface |
| `AppColors.softBlue` | `#EEF3FF` | Low-emphasis interactive/info surface |
| `AppColors.lightBackground` | `#F7F8FC` | Page background |
| `AppColors.card` | `#FFFFFF` | Card and navigation surface |
| `AppColors.textPrimary` | `#171B22` | Primary text |
| `AppColors.textSecondary` | `#6F7680` | Supporting text |
| `AppColors.border` | `#E5E8F0` | Card hairlines and dividers |
| `AppColors.success` | `#22B573` | Genuine success only |
| `AppColors.danger` | `#E53935` | Destructive actions only |

Cards are white, radius 18, hairline border, no shadow, no glassmorphism.
Dark mode keeps seed-derived tones — cards use the dark surface, not white.

## New/changed pieces

- `lib/app/theme/app_tokens.dart` — `AppSpacing` (4/8/12/16/20/24/32 scale)
  and `AppRadius`, reusable by every future screen.
- `lib/core/ui/app_card.dart` — `AppCard`, the one card surface.
- `lib/core/ui/app_visuals.dart` — reusable responsive section headers and
  tinted icon containers.
- Theme: blue scheme, one card language, refined bottom navigation (white
  surface, blue selection, gray rest, subtle top divider). Destinations are
  untouched; labels scale down within their own slot instead of clipping.
- Home header: compact "Mobile Cleaner" identity + tagline, with Settings in
  a subtle rounded surface. Same key, same route.
- Storage Overview: two-column hierarchy — large blue used-percentage left,
  storage ring right (blue arc, small orange accent tip, light track) with
  real available space at its centre, and a real `used / total` summary row.
  All figures still come straight from `StorageInfo`; the orange tip restyles
  the head of the real used arc, it never adds to it.
- Smart Scan hero: deep-blue gradient card, two-line supporting copy, compact
  white "Scan Now" CTA, static cyan/blue radar motif with an orange accent.
  Card and CTA both call the existing navigation. No fake progress.
  Privacy cue ("Files stay on your device.") kept directly beneath.
- Quick Tools: four compact category-tinted tiles in one row when space
  allows, with the same callbacks and destinations. Narrow layouts move to
  two columns; large text moves to compact rows rather than clipping.
- Cleanup summary: real lifetime total and last-cleanup date when history
  exists; an honest "No cleanups yet" empty state before that, plus explicit
  loading/error states. Nothing is invented.
- Existing data-backed recommendations are preserved after the required Home
  flow rather than being removed or placed ahead of Quick Tools.

## Data integrity

Zero hardcoded metrics. Every number on Home renders from
`storageOverviewProvider`, `recommendationsProvider`, or
`cleanupHistoryProvider`, with loading/error/empty states for each.

## Tests

`test/home_screen_test.dart` and the Home-card group in
`test/cleanup_history_test.dart` updated for the new presentation
(hero card, "Scan Now" casing, required section order, responsive Quick
Tools, and cleanup-history empty/error states).
All keys used by cross-cutting tests are preserved: `home_dashboard`,
`smart_scan_button`, `home_settings_button`, `storage_percentage`,
`used_storage`, `free_storage`, `total_storage`, `quick_*`,
`recommendations_*`, `home_history_*`.
