# Model Catalog Plan

Status: Implemented on `codex/model-catalog` on 2026-04-25. Custom model persistence and preflight validation added on 2026-04-27.

## PR Goal

Move curated model metadata out of hard-coded constants into a bundled catalog with validation and a safe fallback.

## Primary Files

- `KotaebaApp/KotaebaApp/Core/Constants.swift`
- `KotaebaApp/KotaebaApp/Core/AppStateManager.swift`
- `KotaebaApp/KotaebaApp/Views/MainWindow/ModelSelectionView.swift`
- `KotaebaApp/KotaebaApp/Server/ServerManager.swift`
- New bundled JSON resource under `KotaebaApp/KotaebaApp/Resources/`
- New focused tests under `KotaebaApp/KotaebaAppTests/`

## Implementation Notes

- Add a typed model catalog loader with display name, identifier, description, language coverage, size, and speed/quality labels.
- Validate missing default model, duplicate identifiers, and malformed metadata.
- Keep a code-level fallback default so the app still launches if the resource is missing or invalid.
- Replace UI/app-state reads of hard-coded available models with the catalog provider.
- Keep current Qwen migration and unsupported-runtime messaging until MLX support changes.
- Add cache-location and delete-model affordances only after model status checks are reliable.
- Custom Hugging Face model IDs are accepted only after local identifier validation, a Hugging Face repository lookup, and an MLX Audio `load_model` compatibility preflight. Successful custom models are saved into the user catalog and merged into the dropdown for later launches.

## Edge Cases

- Missing JSON.
- Malformed JSON.
- Duplicate identifiers.
- Default model absent.
- Stale selected model.
- Legacy Qwen identifier.
- Model change during recording, connecting, downloading, or server startup.
- Download interrupted, token missing, cache unavailable, or validation failure.
- Custom model repository missing, private without token, syntactically unsafe, or incompatible with the app's MLX Audio STT path.

## Resource Checklist

- Model switching stops recording and closes audio/WebSocket resources before server restart.
- Download progress callbacks cannot update stale model state after cancellation or model changes.
- Custom model validation locks model selection until repository and compatibility checks finish or fail.
- Delete-model actions are scoped to known model cache paths and never remove runtime directories.

## Verification

- Add catalog decoding, fallback, duplicate/default validation, and selected-model migration tests.
- Add custom model persistence and validation-state tests.
- Keep server startup validation tests for unsupported model messages.
- Run the Xcode test suite.
- Manual checks: missing catalog fallback, stale selected model migration, model switch while idle, and model switch while recording.
