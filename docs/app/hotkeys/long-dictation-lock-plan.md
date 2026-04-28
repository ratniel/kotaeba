# Long-Dictation Lock Plan

## Implementation Status

Implemented on April 25, 2026 in `codex/long-dictation-lock`.

The final design keeps lock behavior inside `HotkeyProcessor`: a short first tap cancels and opens a double-tap window, a second valid non-repeat tap inside that window starts a locked hold-mode session, and the next valid hotkey press/release stops it. ESC, tap-disabled recovery, reset, mode changes, and shortcut changes all return the processor to idle or a release-waiting cleanup state without leaving lock state behind.

## PR Goal

Add double-tap lock behavior for long dictation without adding hotkey special cases to `AppStateManager`.

## Current Baseline

PR #12 includes the pure `HotkeyProcessor`, configurable hotkey persistence, Settings capture UI, and processor tests. This plan should start after PR #12 merges.

## Primary Files

- `KotaebaApp/KotaebaApp/Hotkey/HotkeyProcessor.swift`
- `KotaebaApp/KotaebaApp/Hotkey/HotkeyManager.swift`
- `KotaebaApp/KotaebaApp/Core/AppStateManager.swift`
- `KotaebaApp/KotaebaApp/Views/SettingsView.swift`
- `KotaebaApp/KotaebaAppTests/HotkeyProcessorTests.swift`

## Implementation Notes

- Add a double-tap timing window to `HotkeyProcessor`.
- Emit explicit start, stop, and cancel actions; keep `HotkeyManager` as the CGEvent bridge.
- Make locked recording stop on the next valid hotkey press/release sequence.
- Make ESC cancel locked recording and return processor state to idle.
- Add minimal Settings/status UI only after processor behavior is covered by tests.

## Edge Cases

- Key repeat must not count as a second tap.
- Extra modifiers pass through.
- Short accidental taps should cancel rather than lock.
- Event tap disabled during tap sequence or locked recording should recover safely.
- Recording mode or hotkey changes during recording should stop or cancel first, then reset processor state.

## Resource Checklist

- Every processor path that starts recording has a matching stop or cancel path.
- No lock state survives `HotkeyManager.stop()`, mode changes, shortcut changes, or tap-disabled recovery.
- No duplicate start action is emitted for one logical recording session.

## Verification

- Add processor tests for double-tap timing, timing expiry, key repeat, ESC cancel, tap-disabled recovery, mode changes, and lock-to-stop.
- Run the Xcode test suite.
- Manual checks: hold mode short tap, normal hold, double-tap lock, ESC cancel, and changing Settings while recording.
