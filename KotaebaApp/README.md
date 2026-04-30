# KotaebaApp

This directory contains the native macOS client for Kotaeba. The app is a Swift/SwiftUI menu bar application that manages permissions, hotkeys, recording state, audio capture, model controls, history, statistics, and text insertion.

## Current App Surface

Merged on `main`:

- Configurable global hotkey capture
- Hold and toggle recording modes
- Long-dictation lock mode
- Menu bar control surface plus settings tabs
- Instant local server startup path
- Microphone selection and persisted audio input preference
- Model catalog with bundled models and custom Hugging Face validation
- Text insertion with safer fallback behavior
- Transcription history and statistics

## Project Shape

```text
KotaebaApp/
├── KotaebaApp/
│   ├── App/
│   ├── Audio/
│   ├── Core/
│   ├── Data/
│   ├── Hotkey/
│   ├── Network/
│   ├── Resources/
│   ├── Server/
│   ├── TextInsertion/
│   ├── Utilities/
│   └── Views/
└── KotaebaAppTests/
```

Key implementation areas:

- `Core/AppStateManager.swift`: app orchestration and lifecycle
- `Audio/AudioCaptureManager.swift`: microphone capture and audio pipeline
- `Hotkey/HotkeyManager.swift`: global shortcut handling
- `Hotkey/HotkeyProcessor.swift`: pure hotkey state machine
- `TextInsertion/TextInserter.swift`: insertion strategies and clipboard safety
- `Core/ModelCatalog.swift`: bundled/custom model metadata
- `Data/StatisticsManager.swift`: statistics and session persistence
- `Views/MainWindow/TranscriptionHistoryView.swift`: recent session history UI

## Local Development

Build/test/install entry points:

```bash
scripts/run_app.sh
scripts/install_local_app.sh --clean
xcodebuild test -project KotaebaApp/KotaebaApp.xcodeproj -scheme KotaebaApp -destination 'platform=macOS'
```

Use the install script for user-facing manual testing because it installs the same app path that macOS permissions attach to.

## Implemented Capabilities

- Global hotkey configuration from Settings
- Recording mode changes with stop-and-prompt behavior
- Locked dictation state machine for longer sessions
- Accessibility-aware text insertion with fallback paste behavior
- Microphone device list, persisted selection, and migration support
- Model preflight state, download status, and custom model validation
- Persisted transcription sessions, insertion metadata, and aggregate statistics

## Release Verification Snapshot

Manually exercised during the current release pass:

- [x] Hotkey settings
- [x] Basic recording cycle
- [x] Text insertion reliability
- [x] Microphone selection
- [x] Model catalog flow
- [x] Permissions flow
- [x] Stats sanity check

## Automated Coverage

Current merged `main` release candidate:

- Full XCTest suite passed
- Result: `98 tests, 0 failures`

Relevant focused coverage now exists for:

- Hotkey state transitions
- Audio input selection logic
- Model catalog validation
- History/statistics persistence
- Text insertion helpers
- Settings migrations
- Shell command diagnostic buffering

## Follow-Ups

These are not release blockers by themselves, but they are still worth polishing:

- Long-dictation lock UX semantics
- Fresh manual confirmation of the new cancel-to-history behavior
- Swift concurrency warning cleanup in `Utilities/ShellCommandRunner.swift`
