# Phase 3 — Permission System

## Implemented

- Permission education shown after first onboarding completion
- Android 13+ granular photo, video, and audio permissions
- Android 12 and lower legacy read-storage permission
- Android 14 selected-media declaration
- Granted state
- Denied state with safe retry and continue-without-access actions
- Permanently denied state with an Open settings action
- Defensive exception handling around plugin/platform calls
- Permission education status stored locally
- Media and storage access entry in Settings
- Injectable permission gateway for deterministic tests

## Android permissions

The implementation deliberately uses least-privilege media/read permissions. It does not request broad `MANAGE_EXTERNAL_STORAGE` access, which is restricted by Google Play and should only be added if a later feature proves it is essential and policy-eligible.

## Acceptance test

The widget test uses a denied fake permission gateway and verifies that the denied state appears, no exception is thrown, and the user can continue into the app.
