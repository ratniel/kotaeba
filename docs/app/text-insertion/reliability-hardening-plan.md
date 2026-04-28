# Text Insertion Reliability Plan

## PR Goal

Build on the merged text insertion fallback fixes and make insertion behavior more reliable across target apps while preserving clipboard safety and user-visible failure states.

## Current Baseline

PR #9, `Fix text insertion fallbacks`, is merged. Future work should extend the current `TextInserter` behavior rather than replacing the insertion architecture.

## Primary Files

- `KotaebaApp/KotaebaApp/TextInsertion/TextInserter.swift`
- `KotaebaApp/KotaebaApp/Core/AppStateManager.swift`
- `KotaebaApp/KotaebaApp/Views/SettingsView.swift`
- `KotaebaApp/KotaebaAppTests/TextInsertionUtilsTests.swift`

## Implementation Notes

- Extract pasteboard restore decision logic into testable helpers.
- Add menu-item paste fallback before synthetic `Cmd+V` when the frontmost app exposes a usable paste command.
- Wait for pasteboard `changeCount` or equivalent commit visibility before paste.
- Leave dictated text in the clipboard when paste likely failed.
- Restore previous clipboard contents only after success or when the user did not change the clipboard.
- Preserve safe-mode newline sanitization unless a later terminal-specific decision changes it.

## Edge Cases

- Missing focused element.
- AX-readable but read-only focused element.
- Stale selected ranges.
- Secure Input enabled.
- Frontmost app changes between transcription and paste.
- User changes clipboard during delayed restore.
- Clipboard contains rich text, files, images, or multiple items.
- Emoji, combined Unicode scalars, tabs, newlines, leading/trailing spaces, and very long transcripts.
- Terminals should not receive unexpected newlines when safe mode is enabled.

## Resource Checklist

- Delayed restore work is cancellable or guarded by pasteboard identity/change count.
- Clipboard restore never overwrites a user change.
- Failed paste leaves the dictated text available to the user.
- Release logs do not include transcript text.

## Verification

- Extend pure tests for UTF-16 replacement, invalid ranges, pasteboard snapshot cloning, restore decisions, and sanitization.
- Run the Xcode test suite.
- Manual checks: TextEdit, Notes, Terminal, Safari/Chrome fields, Cursor/VS Code, Slack or Messages, secure password fields, and clipboard preservation.
