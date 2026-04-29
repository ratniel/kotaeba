# Transcription History Plan

## PR Goal

Persist useful transcription history without storing raw audio by default.

## Implementation Status

Implemented on April 25, 2026:

- `TranscriptionSession` stores optional model, insertion method/error, source app, and transcript metadata.
- `AppStateManager` accumulates multiple final transcript chunks and saves one session after the final-transcript grace window on stop.
- Cancel/discard resets pending transcript text without persisting it.
- Recent sessions are shown in the main window History sidebar, with a clear-history action.
- Automated coverage includes metadata persistence, insertion error persistence, multiple final chunks, cancel discard, and clear-all-data behavior.

## Primary Files

- `KotaebaApp/KotaebaApp/Data/Models.swift`
- `KotaebaApp/KotaebaApp/Data/StatisticsManager.swift`
- `KotaebaApp/KotaebaApp/Core/AppStateManager.swift`
- `KotaebaApp/KotaebaApp/Views/MainWindow/StatisticsView.swift`
- New or updated history UI under `KotaebaApp/KotaebaApp/Views/`
- `KotaebaApp/KotaebaAppTests/StatisticsManagerTests.swift`

## Implementation Notes

- Extend `TranscriptionSession` or add a related history model with migration-friendly optional fields.
- Persist final transcript text, model identifier, duration, word count, timestamp, insertion result, and source app name when available.
- Accumulate multiple final transcript chunks during one recording session and save once on successful stop.
- Do not persist transcript text for cancel/discard.
- Keep insertion method/error separate from transcript text so failed insertion is visible.
- Add History UI after persistence behavior is stable; UI can be a follow-up if the persistence PR grows too large.

## Edge Cases

- Multiple final transcripts in one session.
- Stop without a final transcript.
- Cancel/discard after partial or final text.
- Insertion failure after successful transcription.
- App quit, server exit, WebSocket disconnect, or model change while processing final text.
- Very long or Unicode-heavy transcripts.

## Resource Checklist

- Avoid retaining unnecessary transcript copies after save or cancel.
- Do not store raw audio unless a separate opt-in feature is designed.
- Release logs do not include transcript text.
- Keep SwiftData context access on the main actor or behind an isolated store boundary.

## Verification

- Add tests for save, cancel, multiple finals, insertion metadata, clear-all-data, and migration/default behavior.
- Run the Xcode test suite.
- Manual checks: successful insertion history, failed insertion history, cancelled recording, app restart, and clear data.
