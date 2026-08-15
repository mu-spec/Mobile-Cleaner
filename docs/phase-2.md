# Phase 2 — Onboarding

## Implemented

- Three-page onboarding flow:
  1. Understand Your Storage
  2. Clean Smarter
  3. Private by Design
- Next, Get started, and Skip actions
- Page indicators and swipe navigation
- First-launch completion stored with `shared_preferences`
- Splash routing based on onboarding completion
- Replay onboarding action in Settings
- Automated coverage for first launch, later launch, replay, and all app tabs

## Acceptance test

```bash
flutter analyze
flutter test
```

Expected: onboarding opens when no completion flag exists, does not open after completion, and opens again through Settings → Replay onboarding.
