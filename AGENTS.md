# Kotaeba Agent Guide

## Project Shape

Kotaeba is a macOS speech-to-text system with two cooperating surfaces:

- `KotaebaApp/`: native Swift/SwiftUI menu bar app for permissions, hotkeys, recording UI, audio capture, WebSocket streaming, model controls, statistics, and text insertion.
- Repo root Python runtime: MLX Audio server/client tooling, Pydantic settings, WebSocket message models, setup scripts, release scripts, and local development utilities.

Keep changes aligned with those boundaries. Swift app behavior belongs under `KotaebaApp/KotaebaApp/*`; backend runtime behavior belongs in `main.py`, `stt/`, `models/`, `config.py`, and related scripts.

## Current Architecture

- The macOS app is orchestrated by `KotaebaApp/KotaebaApp/Core/AppStateManager.swift`.
- The app launches and supervises `mlx_audio.server` through `KotaebaApp/KotaebaApp/Server/ServerManager.swift`.
- The release app uses a bundled locked Python runtime from `KotaebaApp/KotaebaApp/Resources/PythonRuntime`; development fallback syncs into `~/Library/Application Support/Kotaeba/.venv`.
- Audio capture is local Swift `AVAudioEngine` code in `KotaebaApp/KotaebaApp/Audio/AudioCaptureManager.swift`, then streamed over WebSocket.
- Text insertion is centralized in `KotaebaApp/KotaebaApp/TextInsertion/TextInserter.swift`.
- Global hotkey listening is centralized in `KotaebaApp/KotaebaApp/Hotkey/HotkeyManager.swift`.
- Model metadata is currently defined in `KotaebaApp/KotaebaApp/Core/Constants.swift`.

## Commands

Prefer these entrypoints when working locally:

- Backend dev runtime: `uv sync`
- Console STT client/server: `uv run main.py`
- Build/run app helper: `scripts/run_app.sh`
- Install local app helper: `scripts/install_local_app.sh`
- Xcode tests:
  `xcodebuild test -project KotaebaApp/KotaebaApp.xcodeproj -scheme KotaebaApp -destination 'platform=macOS'`
- Release DMG:
  `scripts/release/build_dmg.sh <version>`

Do not run release packaging unless the user asks for it. Release scripts may create signed/notarized artifacts depending on environment variables.

For UI and design tooling, use Bun. If a task introduces JavaScript/TypeScript design prototypes, asset tooling, UI experiments, screenshot helpers, or frontend-like scripts, use `bun`, `bunx`, and `bun.lock` instead of adding npm, Yarn, or pnpm workflows. This does not replace the native SwiftUI/Xcode workflow for the macOS app.

When the user needs to test the installed local app, use:

```bash
scripts/install_local_app.sh --clean
```

Use `scripts/install_local_app.sh --clean --reset-accessibility` when the app identity, signing context, or Accessibility permission state needs a fresh macOS permission grant. Use `scripts/run_app.sh` for quick Debug builds, but prefer the install script for user-facing testing because it installs into `/Applications/KotaebaApp.app` and launches the same path the user grants permissions to.

## Safety And Privacy

- Keep Hugging Face tokens and other secrets in Keychain through Settings; do not add secrets to `.env`, docs, tests, or logs.
- Treat text insertion as a high-risk UX path. Preserve clipboard contents where possible, avoid newline surprises in terminals, and keep failure states visible to the user.
- Do not weaken Accessibility or microphone permission checks. Prompting belongs in permission/onboarding flows, not deep utility code by default.
- Be careful with process cleanup. `ServerManager` tracks app-owned server metadata and process groups; do not replace that with broad process killing.

## Swift And macOS UX Work

Use the `macos-design-guidelines` skill for menu bar, Settings, keyboard shortcut, hotkey, window, toolbar, sidebar, permission, and native Mac interaction decisions.

Use the `swiftui-expert-skill` skill when changing SwiftUI views, state flow, settings screens, onboarding, model controls, recording UI, or history UI. Keep existing `ObservableObject`/`@Published` patterns unless the task explicitly includes a contained migration; do not refactor the whole app to `@Observable` opportunistically.

For UX improvements inspired by Hex, prefer narrow, testable additions:

- Add pure state machines before changing event taps.
- Improve `TextInserter` fallback behavior before introducing new insertion surfaces.
- Add model metadata and settings affordances without replacing the MLX server architecture.
- Keep server/runtime hardening intact; Kotaeba's process supervision is a strength.

## Testing Expectations

- The user expects tests to run after every implemented feature. Run the relevant automated tests before handoff whenever code changes are made.
- Add focused tests for pure logic such as hotkey state transitions, settings migrations, model metadata parsing, text sanitization, and insertion utilities.
- For app-level changes, use existing `KotaebaApp/KotaebaAppTests/*` patterns.
- For backend protocol changes, keep Swift `Messages.swift` and Python `models/websocket.py` in sync.
- If a behavior depends on Accessibility, microphone permissions, focused apps, or the system pasteboard, run what can be automated, then document manual verification steps when XCTest cannot cover it. If tests cannot be run, say exactly why in the final handoff.

## Code Review Pass

After implementing any feature, do a focused self-review before handoff:

- Review the changed diff and adjacent lifecycle code for resource leaks, retained delegates, uncancelled tasks, stale callbacks, unnecessary object reuse, and paths that fail to close sockets, event taps, audio taps, subprocesses, files, or pasteboard state.
- Check edge cases that tests may miss: rapid repeated input, cancellation races, permission revocation, app shutdown while work is in flight, stale WebSocket/audio callbacks, server crashes, model changes during active work, and macOS-dependent global event behavior.
- Revisit security and privacy boundaries. Do not log secrets or transcript text unexpectedly, do not weaken Accessibility or microphone checks, and keep user clipboard/text insertion failure states visible.
- Add or update focused tests for pure logic and deterministic regressions. For behavior that depends on Accessibility, microphone devices, active apps, secure input, or pasteboard timing, document concrete manual verification steps.
- If review finds issues, report findings first with file and line references, ordered by severity. Fix only what is clearly in scope for the requested work, and call out any remaining risks separately.

## Harness Maintenance

Update harness documents in the same workstream as meaningful decisions:

- `AGENTS.md`: repo-wide architecture, workflow, commands, and recurring rules.
- `KotaebaApp/AGENTS.md`: Swift/macOS app-specific implementation guidance.
- `TODO.md`: open work, grouped by milestone or priority.
- `completed_tasks.md`: completed milestones and shipped decisions with dates.
- `docs/*`: supporting rationale or detailed design notes.

Keep these files current and concrete. Replace stale instructions instead of layering contradictory old and new guidance.

## Docs Layout

Use feature-wise directories under `docs/` so future agents can follow the project's direction:

- `docs/app/`: native macOS app architecture, implementation guides, and setup notes.
- `docs/app/hotkeys/`: global hotkey behavior and fixes.
- `docs/app/text-insertion/`: insertion architecture and app compatibility notes.
- `docs/app/instant-transcription/`: instant server/model startup decisions.
- `docs/backend/`: MLX Audio, streaming, and backend runtime notes.
- `docs/testing/`: manual and automated test guides.
- `docs/release/`: release, packaging, and distribution notes.
- `docs/archive/`: historical fix summaries that should not drive new architecture.
- `docs/research/`: research notes that are useful but not active product docs.

Keep root markdown limited to active harness and entrypoint files: `README.md`, `AGENTS.md`, `TODO.md`, `completed_tasks.md`, and tool-specific root files such as `WARP.md` when a tool expects them there.
