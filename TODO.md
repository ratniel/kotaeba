# TODO

## Hex-Inspired UX Hardening

These tasks come from the April 24, 2026 comparison with Hex. The goal is to borrow the interaction maturity without refactoring Kotaeba away from its Swift app plus MLX Python server architecture.

- [x] Add a pure hotkey state machine.
  - Scope: introduce a small processor for idle, hold recording, locked recording, cancel/discard, and dirty states; keep the existing event tap in `KotaebaApp/KotaebaApp/Hotkey/HotkeyManager.swift`.
  - Tests: cover key down/up, key repeat, extra modifiers, control release, ESC cancel, short accidental taps, and tap-disabled recovery expectations where pure logic applies.

- [x] Add configurable hotkey persistence.
  - Scope: persist key code and modifiers in `UserDefaults`, expose a Settings control, and keep `Ctrl+X` as the migration/default until a user changes it.
  - Constraint: avoid standard editing shortcuts such as `Cmd+X`, `Cmd+C`, and `Cmd+V`; show the resolved display string consistently in menu bar and Settings.

- [ ] Add double-tap lock or long-dictation lock mode.
  - Scope: allow quick double-tap to keep recording active until the user presses the hotkey again or cancels with ESC.
  - Constraint: implement through the hotkey processor rather than special cases in `AppStateManager`.

- [ ] Harden text insertion fallbacks.
  - Scope: add a menu-item paste fallback, wait for pasteboard commit before `Cmd+V`, improve clipboard restore semantics, and leave text in clipboard when paste fails.
  - Tests: keep pure text/range/pasteboard snapshot utilities covered; document manual checks for TextEdit, Notes, terminals, browsers, and secure input fields.

- [ ] Add microphone selection and device-change handling.
  - Scope: persist selected microphone, refresh devices on connect/disconnect, invalidate prepared capture state when the default device changes, and keep "system default" as an explicit option.
  - Constraint: keep the audio stream format at 16kHz mono PCM unless the backend protocol changes.

- [ ] Move model metadata out of hard-coded constants.
  - Scope: load curated model metadata from a bundled JSON resource with display name, identifier, description, language coverage, size, and speed/quality labels.
  - UI: add open cache location/delete model affordances only after download/status state is reliable.

- [ ] Store useful transcription history.
  - Scope: persist final transcript text, model identifier, duration, word count, timestamp, insertion result, and source app name when available.
  - Constraint: do not store raw audio by default unless the user opts in or a separate history/audio decision is made.

## Harness

- [ ] Keep `AGENTS.md`, `KotaebaApp/AGENTS.md`, `TODO.md`, and `completed_tasks.md` updated whenever these tasks change scope or land in code.
- [ ] Keep feature documentation under `docs/` in the current feature-wise structure; add new docs near the feature they describe instead of placing project docs at repo root.
