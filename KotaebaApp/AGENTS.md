# KotaebaApp Agent Guide

## Surface Scope

This directory owns the native macOS app:

- `App/`: app lifecycle, menu bar, windows, onboarding launch behavior.
- `Core/`: app state orchestration, constants, runtime/model selection decisions.
- `Server/`: Python runtime and `mlx_audio.server` subprocess management.
- `Audio/`: microphone capture and audio format conversion.
- `Network/`: WebSocket protocol client and Swift message parsing.
- `Hotkey/`: Accessibility permission checks and global keyboard event tap handling.
- `TextInsertion/`: Accessibility, Unicode event, and clipboard insertion behavior.
- `Views/`: SwiftUI app UI, settings, main window, onboarding, and recording bar.
- `Data/`: SwiftData models and statistics persistence.

## Swift Skills To Use

Use `macos-design-guidelines` for Mac-native UX changes, especially:

- menu bar items and keyboard shortcuts
- Settings structure and command discoverability
- hotkey semantics and cancellation behavior
- native window behavior and onboarding flow
- Accessibility labels, keyboard navigation, and reduced-motion/reduced-transparency support

Use `swiftui-expert-skill` for SwiftUI implementation quality:

- view decomposition
- state ownership and bindings
- async `.task` work and cancellation
- stable `ForEach` identity
- modern SwiftUI modifiers where a local edit can adopt them cleanly
- compact, testable view models or pure helpers for UI logic

Do not perform broad architecture rewrites just to satisfy a skill checklist. Keep improvements narrow and compatible with the current `AppStateManager`/`ObservableObject` structure unless a task explicitly calls for a migration.

For UI/design tooling outside native SwiftUI, use Bun. Any JavaScript/TypeScript support scripts, prototypes, visual experiments, or design asset tooling should use `bun`/`bunx` and `bun.lock`; do not introduce npm, Yarn, or pnpm lockfiles unless the existing toolchain already requires them.

## UX Improvement Direction

The current product priority is Hex-inspired interaction hardening without replacing Kotaeba's server/runtime architecture.

Prefer these local improvements:

- Extract a pure hotkey processor with tests, then adapt `HotkeyManager` to use it.
- Add configurable shortcut persistence after the processor is stable.
- Make long dictation easier with double-tap lock or equivalent lock mode.
- Harden text insertion fallbacks inside `TextInserter`.
- Add selected microphone persistence and device-change handling inside `AudioCaptureManager`.
- Expand model metadata and model management UI without moving model execution into Swift.
- Store useful transcription history, not just aggregate statistics.

## Implementation Rules

- Keep `ServerManager` process tracking, stale cleanup, startup validation, and health monitoring intact unless the task is specifically about that subsystem.
- Do not bypass permission checks for Accessibility or microphone access.
- Keep sensitive values in Keychain via existing secure settings helpers.
- Avoid adding hard-coded user-specific paths outside documented support/runtime locations.
- Prefer pure helpers for logic that can be tested without Accessibility, microphone, or pasteboard access.

## Verification

The user expects tests after every implemented feature. Use focused Xcode tests for pure logic:

```bash
xcodebuild test -project KotaebaApp/KotaebaApp.xcodeproj -scheme KotaebaApp -destination 'platform=macOS'
```

For permission, pasteboard, active-app insertion, recording bar, and microphone behavior, include manual verification notes because these depend on macOS state outside XCTest.

For user testing of the installed app, prefer:

```bash
scripts/install_local_app.sh --clean
```

Use `scripts/install_local_app.sh --clean --reset-accessibility` when macOS Accessibility should forget the existing permission grant. This installs to `/Applications/KotaebaApp.app`, which keeps permission testing aligned with the app path the user actually runs.
