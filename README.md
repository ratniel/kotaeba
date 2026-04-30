# Kotaeba

Kotaeba is a local-first speech-to-text app for macOS. It combines a native Swift/SwiftUI menu bar client with a Python transcription runtime so you can start dictation from a global hotkey and insert text into other apps.

## What Is On `main`

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

## Architecture

Kotaeba has two cooperating parts:

- `KotaebaApp/`: native macOS app for permissions, hotkeys, audio capture, UI, model controls, history, statistics, and text insertion
- repo root Python runtime: MLX Audio server/client tooling, config, WebSocket models, setup scripts, and release helpers

High-level flow:

```text
Global Hotkey
  -> Swift audio capture
  -> local WebSocket stream
  -> Python MLX Audio runtime
  -> final transcript
  -> text insertion / history / statistics
```

## Local Workflows

Common commands:

```bash
uv sync
uv run main.py
scripts/run_app.sh
scripts/install_local_app.sh --clean
xcodebuild test -project KotaebaApp/KotaebaApp.xcodeproj -scheme KotaebaApp -destination 'platform=macOS'
```

Use `scripts/install_local_app.sh --clean` when you want to test the installed app at `/Applications/KotaebaApp.app`.

## Release Candidate Verification

These items have been manually exercised during the current release pass:

- [x] Configurable hotkey settings
- [x] Basic recording start/stop flow
- [x] Text insertion reliability across common apps
- [x] Microphone selection
- [x] Model catalog and selection flow
- [x] Permissions flow
- [x] Statistics updates look sane against recent usage

## Automated Validation

The merged release candidate on `main` passed:

- `xcodebuild test -project KotaebaApp/KotaebaApp.xcodeproj -scheme KotaebaApp -destination 'platform=macOS'`
- Result: `98 tests, 0 failures`

## Docs

- [KotaebaApp/README.md](KotaebaApp/README.md)
- [AGENTS.md](AGENTS.md)
- [docs/app](docs/app)
- [docs/backend](docs/backend)
- [docs/testing](docs/testing)

## License

MIT
