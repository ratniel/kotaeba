# Lifecycle Hardening Plan

## PR Goal

Create a safety baseline before adding more UX features. This PR should tighten recording shutdown and stale callback behavior across hotkey, audio, WebSocket, server, and app lifecycle paths.

## Primary Files

- `KotaebaApp/KotaebaApp/Core/AppStateManager.swift`
- `KotaebaApp/KotaebaApp/Audio/AudioCaptureManager.swift`
- `KotaebaApp/KotaebaApp/Network/WebSocketClient.swift`
- `KotaebaApp/KotaebaApp/Server/ServerManager.swift`
- `KotaebaApp/KotaebaApp/Hotkey/HotkeyManager.swift`
- `KotaebaApp/KotaebaAppTests/AppStateManagerTests.swift`

## Implementation Notes

- Audit `startRecording`, `stopRecording`, `cancelRecording`, `stopServer`, unexpected server exit, model switch, recording-mode switch, permission revocation, and app quit.
- Make active WebSocket ownership explicit so stale clients cannot mutate current app state.
- Cancel pending disconnect/final-transcript grace tasks when recording is cancelled, restarted, server is stopped, or the server exits unexpectedly.
- Keep audio shutdown ahead of WebSocket disconnect grace so no new buffers are sent after stop.
- Ensure `HotkeyManager.stop()` removes run-loop sources and resets processor state.
- Preserve `ServerManager` process-group and owned-process cleanup. Do not replace it with broad process killing.

## Edge Cases

- Rapid start/stop/start.
- Stop while still connecting.
- Server crash during recording or final transcript grace.
- App quit while audio/WebSocket/server work is in flight.
- Model or recording-mode change during recording.
- Accessibility or microphone permission revoked while active.

## Resource Checklist

- Audio tap removed before engine stop/replacement.
- `AVAudioEngine` released on stop/cancel/error.
- Pending tasks cancelled or guarded by identity checks.
- URL sessions invalidated after intentional disconnect.
- Event taps disabled and run-loop sources removed.
- Server subprocesses stopped through existing owned-process tracking.

## Verification

- Add focused tests for pure state transitions and stale callback handling.
- Run:

```bash
xcodebuild test -project KotaebaApp/KotaebaApp.xcodeproj -scheme KotaebaApp -destination 'platform=macOS'
```

- Manual checks: rapid hotkey use, server crash during recording, app quit during recording, model switch during recording, and permission revocation.
