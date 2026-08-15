# Phase 1 — Basic App Shell

## Implemented

- Branded Android native splash screen
- Branded in-app splash screen with automatic transition
- Stateful bottom navigation shell
- Home tab
- Clean placeholder tab
- Photos placeholder tab
- Files placeholder tab
- Apps placeholder tab
- Settings tab
- Independent navigation stacks through `StatefulShellRoute.indexedStack`
- Widget test that opens every tab and checks for framework exceptions

## Acceptance test

```bash
flutter analyze
flutter test
flutter run
```

Expected: the splash transitions to Home, every bottom destination opens its corresponding screen, and no crashes occur.
