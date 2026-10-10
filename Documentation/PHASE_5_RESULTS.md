# Phase 5 — lifecycle and usability

Implemented and verified on 2026-10-08 with Xcode 26.2 / Swift 6.2.3 on the arm64 development host, macOS 26.6.2. Deployment target remains macOS 14. Core cryptography, persistence, and the file format are unchanged.

## Delivered

- Automatic lock after app inactivity, system sleep, and macOS-session deactivation. Five-minute inactivity default; 1/5/15/30-minute and Never choices. Sleep/session locking remains active with Never selected.
- A monotonic-clock state machine, half-second common-mode timer, and app-local input monitoring. Expired sessions reject arriving activity before it can renew the deadline. Background operation completion does not extend a session.
- Immediate removal of visible vault state and drafts on lock; cancellation and generation checks suppress late results. Engine cleanup waits for outstanding work while keeping folder access alive. An interrupted commit may finish, and the UI explains that reopening is needed to inspect the result.
- Secret Copy buttons with pasteboard ownership and expiration. Thirty-second default; 15/30/60/120-second or lock-only choices. Lock and orderly quit clear the owned write, even with expiration disabled. Ownership metadata replaces retained plaintext comparisons.
- Master-passphrase change sheet with current-passphrase verification, exact UTF-8 confirmation, no-recovery acknowledgement, and old-backup warning. Bindings clear before the asynchronous operation; failed attempts require re-entry. Successful rewrap preserves payload ciphertext.
- Security Settings, non-secret local timeout preferences, keyboard commands, accessible control labels, initial secure-field focus, and Command-F search focus. Editor and category forms explain draft loss on automatic lock.

## Automated verification

| Check | Result |
| --- | --- |
| Desktop package | 15 XCTest tests passed (5 existing + 10 new) |
| Core package | 26 tests passed |
| Debug and Release Xcode builds | Passed |
| Release signature verification | Passed; local ad-hoc signature |
| Release entitlements | App Sandbox and user-selected read/write only; no network or debugger entitlement |
| Release hardened runtime | Enabled |

The new tests cover activity/deadline boundaries, a late input event, replacement copy deadlines, intervening clipboard writes including identical values, lock-only clearing, and preference validation. A real private named NSPasteboard verifies change-count behavior and concealed/transient hints without modifying the user's general clipboard. That integration test requires access to macOS pasteboard services; the restricted shell sandbox cannot provide it, so the successful suite ran with the necessary host access.

Lifecycle tests simulate sleep during delayed unlock, save, and passphrase change, using a service that intentionally ignores cancellation. They verify cleared retained drafts, no revived session, eventual engine lock, and sleep locking with inactivity disabled. Another test proves that a background save completion does not reset inactivity.

The real-engine passphrase-change test creates a synthetic vault and note, saves an old encrypted backup, changes the passphrase, compares payload bytes starting at byte 192, and checks fresh sessions: the new passphrase opens the updated vault, the old passphrase fails there, and the old backup still opens with its old passphrase. Confirmation tests distinguish canonically equivalent Unicode sequences by their UTF-8 bytes; error tests verify cleared fields and a retryable form.

## Interactive verification

Used the sandboxed Debug app and the existing disposable synthetic vault in `/private/tmp/crypta-phase4-smoke`:

1. Opened the vault through native file/folder panels and verified initial keyboard focus in the secure unlock field.
2. Unlocked using the public test passphrase, selected a secure note, and verified accessible Copy/Reveal labels with the content hidden.
3. Used Command-F to focus search, Command-Shift-P to open the passphrase form with current-passphrase focus, and Command-E to edit the selected note. Inspected the passphrase form visually; actual rewrap execution is covered by the real-engine automated test.
4. Left a changed, unsaved synthetic title idle with the one-minute timeout. The editor disappeared, the unlock screen returned, and the notice stated that inactivity locking discarded unsaved drafts.
5. Unlocked again and verified the original committed title remained. Restored the five-minute inactivity preference; clipboard expiration stayed at thirty seconds.
6. Verified the final lock-transition focus fix using Command-Shift-L: the secure unlock field became the focused control. Reopened Settings to confirm both restored defaults, then quit cleanly.

These are native-control smoke checks, not an automated XCUITest or complete VoiceOver audit. The general clipboard was not overwritten for this check. No real credentials were changed and no user vault was opened.

## Reproduce

```sh
swift test
swift test --package-path Packages/CryptaCore
xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Debug -derivedDataPath DerivedData build
xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Release -derivedDataPath DerivedData build
codesign --verify --deep --strict DerivedData/Build/Products/Release/Crypta.app
codesign -d --entitlements - DerivedData/Build/Products/Release/Crypta.app
```

Run desktop tests in a logged-in macOS session with pasteboard access. First-time dependency resolution needs network access; the app runtime does not.

## Limits and Phase 6 gates

Pasteboard ownership comparison and clearing are separate OS calls, leaving a narrow cross-process race. Concealed/transient types are interoperability hints, not enforcement against clipboard history or other readers. Timer clearing cannot revoke captured copies. Ordinary text copied from an editor is not managed by the Copy-button feature.

Swift/framework plaintext copies cannot be proven erased. A synchronous native KDF cannot always be interrupted immediately; its late result is discarded, and owned key material is released after the operation completes. Actual hardware sleep/fast-user-switch delivery, full accessibility behavior, macOS 14 and M1 runtime behavior, independent review, native dependency provenance, a working sanitizer run, Developer ID signing, and notarization remain Phase 6 work. The known sanitizer runtime deadlock before application startup is unresolved; no sanitizer pass is claimed.

Phase 5 is implemented, but Crypta remains an experimental vault for synthetic data until the release gates are satisfied.
