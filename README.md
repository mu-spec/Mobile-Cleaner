# Mobile Cleaner

A safe, fast, and transparent Android storage cleaner built with Flutter.

## Phase 0 status

- Flutter project created on Flutter 3.47 / Dart 3.13
- Android application ID: `com.mobilecleaner.app`
- Feature-first, Clean Architecture-ready folder structure
- Material 3 light and dark theme system
- Declarative routing with `go_router`
- Riverpod app scope for scalable state management
- Base storage, device, permissions, logging, and testing dependencies
- Branded launcher icon and initial home/settings shells
- Static analysis, widget test, and Android debug build verified
- Local Git repository initialized; add a GitHub remote when available

## Requirements

- Flutter 3.47.0 or newer compatible stable SDK
- Dart 3.13.0 or newer compatible SDK
- JDK 17+
- Android SDK

## Run

```bash
flutter pub get
flutter run
```

## Quality checks

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

## Project structure

```text
lib/
├── app/
│   ├── router/             # Navigation configuration
│   └── theme/              # Material 3 colors and themes
├── core/
│   ├── constants/          # App-wide constants
│   └── utils/              # Shared helpers
└── features/
    ├── cleaner/
    │   ├── data/           # Data sources and implementations
    │   ├── domain/         # Entities, contracts, and use cases
    │   └── presentation/   # UI and state/controllers
    ├── home/presentation/
    └── settings/presentation/
```

## GitHub setup

Create an empty GitHub repository, then run:

```bash
git remote add origin https://github.com/YOUR_USERNAME/mobile-cleaner.git
git push -u origin main
```

Do not commit signing keys, API secrets, or `android/local.properties`.
