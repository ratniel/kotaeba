# Completed Tasks

## 2026-04-30

- Added recoverable port-conflict handling for the local MLX server: when `localhost:9999` is occupied by a Kotaeba-owned `mlx_audio.server`, the app now detects the listener, offers a one-click "stop existing server and restart" action in both the main window and menu bar, and retries startup with the currently selected model.
- Hardened server diagnostics to inspect live listener processes even when `server-process.json` is missing, including PID/PPID/PGID-based stale detection for orphaned Kotaeba runtimes.
- Added focused `AppStateManager` tests covering recoverable port-conflict detection and the terminate-and-restart recovery path.

## 2026-04-24

- Reviewed Hex's DeepWiki architecture and captured the practical product comparison for Kotaeba: Hex is stronger in hotkey semantics, insertion fallback polish, model UI, audio-device UX, and history; Kotaeba is stronger in locked Python runtime distribution, MLX server supervision, startup model validation, port/stale-process handling, and backend replaceability.
- Added harness guidance for Kotaeba agents, including repo-wide architecture, local Swift app ownership, commands, safety rules, and when to use the `macos-design-guidelines` and `swiftui-expert-skill` skills for UX improvements.
- Logged the seven Hex-inspired UX hardening tasks in `TODO.md` so future implementation can proceed incrementally without a broad refactor.
- Reorganized existing project markdown into feature-wise `docs/` directories and updated active references to the new locations.
- Recorded workflow decisions that feature work should run tests before handoff, local installed-app testing should use `scripts/install_local_app.sh`, and UI/design support tooling should use Bun.
- Added a pure hotkey processor for hold/toggle recording semantics, cancel/discard, dirty recovery, short accidental taps, and tap-disabled recovery while keeping `HotkeyManager` responsible for the macOS event tap.
- Added configurable hotkey persistence with Settings capture, warning-only shortcut guidance, menu bar display sync, active-recording stop-before-save behavior, and focused tests.
