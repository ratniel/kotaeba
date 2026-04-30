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

## Navigating The App

The app is organized around a few core surfaces:

- Menu bar item: the quickest way to open the app, check whether the server is ready, or quit
- Main window: server controls, recording mode, model selection, statistics, and history
- Settings tabs:
  - General
  - Hotkey
  - Audio
  - Transcription
  - About
- Recording bar: the transient overlay shown during active dictation

## Implemented Capabilities

- Global hotkey configuration from Settings
- Recording mode changes with stop-and-prompt behavior
- Locked dictation state machine for longer sessions
- Accessibility-aware text insertion with fallback paste behavior
- Microphone device list, persisted selection, and migration support
- Model preflight state, download status, and custom model validation
- Persisted transcription sessions, insertion metadata, and aggregate statistics

## Automated Coverage

Current merged `main` release candidate:

- Full XCTest suite passed
- Result: `98 tests, 0 failures`

## Known Limitations

- Long-dictation lock currently uses the shipped tap-based lock flow; it may differ from a stricter `hold Ctrl + double-tap X` interaction model.
- Text insertion still depends on Accessibility support and focused-app behavior, so compatibility can vary across macOS apps.

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
