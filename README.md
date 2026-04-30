# Kotaeba

Kotaeba is a local-first speech-to-text app for macOS. It combines a native Swift/SwiftUI menu bar client with a bundled local speech runtime so you can start dictation from a global hotkey and insert text into other apps.

## Features

The current `main` branch includes these merged features:

- Configurable global hotkey settings
- Hold mode and toggle mode recording
- Long-dictation lock mode
- Improved text insertion with Accessibility-first behavior and safer clipboard fallback
- Microphone selection with persisted preference and device-change handling
- Recording lifecycle hardening for stop/cancel/shutdown flows
- Bundled model catalog with custom Hugging Face model validation
- Transcription history with persisted session metadata
- Usage statistics and recent-session views

## Install

### For Most People

Download the latest `.dmg` from the GitHub Releases page, open it, and move `KotaebaApp.app` into `/Applications`.

### For Developers

```bash
uv sync
scripts/install_local_app.sh --clean
```

This builds and installs the app locally to `/Applications/KotaebaApp.app`.

If macOS permission prompts appear on first launch, allow:

- Microphone access
- Accessibility access

## Using The App

Kotaeba lives in the macOS menu bar.

### First Run

1. Launch `KotaebaApp`
2. Complete the onboarding and permission flow
3. Wait for the local server to become ready
4. Press the configured hotkey to start dictation

### Main Areas

- Menu bar item: open the app, check status, and quit
- Main window: server status, recording mode, model selection, statistics, and recent history
- Settings: general options, hotkey, audio input, and transcription/model controls
- Recording bar: appears while recording and shows live activity

### Basic Flow

1. Choose your preferred recording mode
2. Pick the microphone you want to use
3. Select a bundled model or validate a custom Hugging Face model
4. Place the cursor in the target app
5. Press the hotkey and speak
6. Let Kotaeba insert the final text at the cursor

### Where To Look In The App

- `Settings > Hotkey`: configure the global shortcut
- `Settings > Audio`: choose the microphone
- `Settings > Transcription`: choose bundled or custom models
- Main window History area: review recent transcription sessions
- Main window Statistics area: see usage totals and recent activity

## Architecture

Kotaeba has two cooperating parts:

- `KotaebaApp/`: native macOS app for permissions, hotkeys, audio capture, UI, model controls, history, statistics, and text insertion
- repo root support files: dependency management, runtime setup helpers, and release scripts

High-level flow:

```text
Global Hotkey
  -> Swift audio capture
  -> local WebSocket stream
  -> Python MLX Audio runtime
  -> final transcript
  -> text insertion / history / statistics
```

## Development

Common commands:

```bash
uv sync
scripts/run_app.sh
scripts/install_local_app.sh --clean
xcodebuild test -project KotaebaApp/KotaebaApp.xcodeproj -scheme KotaebaApp -destination 'platform=macOS'
```

## Automated Validation

The merged release candidate on `main` passed:

- `xcodebuild test -project KotaebaApp/KotaebaApp.xcodeproj -scheme KotaebaApp -destination 'platform=macOS'`
- Result: `98 tests, 0 failures`

## Known Limitations

- Long-dictation lock currently follows a tap-based lock flow. If you expect a pure `hold Ctrl + double-tap X` gesture without the first tap acting like a normal start, the current behavior may feel different.
- Text insertion depends on macOS Accessibility APIs and target-app behavior. Most common apps work, but insertion and fallback paste behavior can still vary between apps.

## More Info

- [KotaebaApp/README.md](KotaebaApp/README.md)

## License

MIT
