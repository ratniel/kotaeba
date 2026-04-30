# Kotaeba

Kotaeba is a local-first speech-to-text app for macOS. It combines a native Swift/SwiftUI menu bar client with a bundled local speech runtime so you can start dictation from a global hotkey and insert text into other apps.

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

## Local Workflows

Common commands:

```bash
uv sync
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

## Known Limitations

- Long-dictation lock currently follows a tap-based lock flow. If you expect a pure `hold Ctrl + double-tap X` gesture without the first tap acting like a normal start, the current behavior may feel different.
- Text insertion depends on macOS Accessibility APIs and target-app behavior. Most common apps work, but insertion and fallback paste behavior can still vary between apps.

## More Info

- [KotaebaApp/README.md](KotaebaApp/README.md)

## License

MIT
