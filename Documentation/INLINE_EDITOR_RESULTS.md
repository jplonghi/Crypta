# Inline editing and wrapping tags

Implemented October 9, 2026.

Item creation and editing now occupy the browser's detail pane. The existing draft model, secure inputs, explicit encrypted saves, failure retention, automatic-lock clearing, and quit/lock draft prompts are reused. The item list, search, and navigation pause until Save or Cancel; the footer identifies the unsaved draft. The editor scrolls within the pane while its Save/Cancel controls remain visible. Escape cancels; Command-S saves through the existing command.

Tag chips use their measured widths with a six-point gap and wrap when the available width is exceeded. This layout is shared by detail tags, editable tags, and suggestions. Long labels can wrap within the available width. No grid-column spacing is retained.

Verification:

- Debug and Release builds succeed; Release signature verification passes; 19 desktop tests pass, including two layout tests and existing draft, encrypted save, organization, lock, and clipboard checks.
- Native checks used an isolated app copy with synthetic vault data: Command-E edits inline, Cancel restores committed data, Save returns to the selected detail view, New Item opens inline, and Escape cancels the new draft.
- Widening the window from 880 to roughly 1195 points kept tag chips adjacent. Wrapping and exact-width row boundaries are covered by layout tests.

Core encryption and persistence code did not change. macOS 14 runtime testing and a full VoiceOver audit were not performed.
