# Microphone Selection Plan

## PR Goal

Add selected microphone persistence and device-change handling while keeping the backend audio contract at 16kHz mono PCM.

## Primary Files

- `KotaebaApp/KotaebaApp/Audio/AudioCaptureManager.swift`
- `KotaebaApp/KotaebaApp/Core/AppStateManager.swift`
- `KotaebaApp/KotaebaApp/Core/Constants.swift`
- `KotaebaApp/KotaebaApp/Views/SettingsView.swift`
- New focused tests under `KotaebaApp/KotaebaAppTests/`

## Implementation Notes

- Add a small audio device model with stable ID, display name, and availability state.
- Keep "System Default" as an explicit persisted option.
- Move enumeration and selection fallback behind `AudioCaptureManager` APIs that can be tested without starting `AVAudioEngine`.
- Refresh devices when Settings opens and on system device-change notifications.
- Use the selected input when available; fall back only when the user selected System Default or the selected device is unavailable.
- Invalidate prepared capture state when default or selected device changes.

## Edge Cases

- Selected device disconnects while idle, connecting, recording, or stopping.
- Default input changes while an engine is prepared or running.
- Permission denied, revoked, or granted while Settings is open.
- Devices with unusual sample rates, channel counts, no input channels, Bluetooth latency, or transient availability.
- Rapid recording starts while device refresh notifications arrive.

## Resource Checklist

- Remove audio taps before stopping or replacing an engine.
- Release `AVAudioEngine` and `AVAudioConverter` on stop/cancel/error.
- Avoid retaining `self` from audio tap closures after capture stops.
- Remove notification observers on deinit.
- Keep outbound stream format at 16kHz mono PCM unless the protocol changes.

## Verification

- Add pure tests for device selection fallback, unavailable selected device handling, and persisted setting migration.
- Run the Xcode test suite.
- Manual checks: built-in mic, USB mic, Bluetooth mic, disconnect during recording, sleep/wake, and permission revocation.
