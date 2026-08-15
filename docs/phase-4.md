# Phase 4 — Real Storage Overview

## Implemented

- Native Android `StatFs` bridge using the device data partition
- Total storage in bytes
- Available/free storage in bytes
- Used storage calculated as total minus available
- Used percentage clamped between 0% and 100%
- Circular storage indicator on Home
- Human-readable KB, MB, GB, and TB values
- Loading, unavailable, and retry states
- Injectable repository for deterministic widget testing

## Accuracy notes

The app reads `Environment.getDataDirectory()` through Android `StatFs`, which represents the internal data partition available to apps and user content. Values can differ slightly from Android Settings because Settings may reserve system space, round units differently, or refresh at a different moment.

## Device acceptance test

1. Open Android Settings → Storage and note total and available storage.
2. Open Mobile Cleaner → Home.
3. Compare Total and Free values, allowing for rounding and storage changes between readings.
4. Confirm Used equals Total minus Free and the circular percentage matches Used divided by Total.
