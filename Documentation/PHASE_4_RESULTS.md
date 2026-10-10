# Phase 4 — native macOS app

Implemented and verified on 2026-10-07–08, using Xcode 26.2 / Swift 6.2.3 on the arm64 development host running macOS 26.6.2. Deployment target remains macOS 14; that minimum OS and M1 hardware have not been runtime-tested.

## Delivered

- `Crypta.xcodeproj`, shared Crypta scheme, app bundle metadata, `.crypta` document association, sandbox entitlements, and native SwiftUI screens.
- Root `CryptaDesktop` Swift package for presentation/UI/platform code, depending on the existing local `CryptaCore` package. No new third-party dependency.
- Welcome, create, folder selection, open, unlock, three-column browser, title/tag/category/username/URL/service search, category creation, and credential/token/note/custom-field editors.
- Hidden-by-default secret details; secret custom fields preserve their display flag. Plain-display fields remain encrypted on disk.
- Explicit encrypted Save, cancellation without mutation, delete confirmation, manual lock, and safe switching through Close Vault.
- Save/Discard/Cancel on Quit with an editor open. Native text controls disable undo, automatic correction/completion/substitution, and writing tools where supported. No plaintext autosave or app state restoration.
- Finder events are queued until the main window is attached, then request the containing folder. Existing windows prefer incoming events; the app holds one vault model.

The app requests the vault's containing directory explicitly because the engine creates encrypted sibling staging files and a stable writer-lock file. Scope grants remain alive until outstanding engine work and locking finish. No persistent bookmarks or recent-vault database are stored by Crypta; macOS file dialogs can independently remember navigation locations.

## Verification

| Check | Result |
| --- | --- |
| Debug Xcode app build | Passed |
| Release Xcode app build | Passed |
| Desktop presentation suite | 5 XCTest tests passed |
| Existing core regression suite | 26 tests passed |
| Bundle/plist validation and code-signature verification | Passed |
| Built app sandbox entitlement | Enabled |
| Built app user-selected read/write entitlement | Enabled |
| Network entitlements | None |
| Debug signing | Local ad-hoc, debugger entitlement present |
| Release signing | Local ad-hoc with hardened-runtime flag; no debugger entitlement |

Presentation tests exercise all four entry types, category/tag preservation, default-profile real encrypted writes and fresh-session reopening, wrong-passphrase rejection, delete persistence, nonsecret search, draft cancellation, UTF-8-exact confirmation, enclosing-folder validation, ordinary save-error retention and retry, ambiguous-storage locking, immediate draft clearing, and suppression of a delayed unlock result after lock. The delayed operation intentionally ignores cancellation to test the presentation generation check.

The synthetic directory byte scan checks known passphrase/title/secret markers against every file in that test directory, including lock/staging artifacts if present. This is a bounded check, not a claim that framework or OS memory can never reach storage.

## Interactive evidence

Exercised the actual ad-hoc-signed, sandboxed Debug app using native controls and disposable synthetic files:

1. Created a vault through the filename, folder, passphrase, exact confirmation, and no-recovery acknowledgement flow.
2. Added and edited a credential, including multiline notes and a pending tag; saved and reopened it in a fresh process. Password and notes were absent from the accessibility detail tree until Reveal was selected.
3. Verified a wrong-passphrase error and successful subsequent unlock.
4. Created a secure-note draft; Quit offered Save/Discard/Cancel. Cancel retained the draft. Save and Quit wrote the encrypted note and terminated the app.
5. Opened the saved `.crypta` through Finder from a stopped app. The containing-folder grant led to the unlock screen; unlocking restored the saved note, hidden by default. Explicit reveal showed the expected synthetic marker.
6. Locked the vault and verified the browser, selection, search, and secret details were removed.
7. Inspected the native browser visually and scanned the disposable vault directory: test passphrase, title, and secret marker were absent from file bytes.

During verification, fixed canonical path comparison (`/tmp` aliases and directory URL spelling), explicit Quit routing while an editor sheet is active, and ordering of document events against main-window creation. The core implementation and format were unchanged.

## Reproduce

```sh
xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Debug -derivedDataPath DerivedData build
xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Release -derivedDataPath DerivedData build
swift test
swift test --package-path Packages/CryptaCore
codesign --verify --deep --strict DerivedData/Build/Products/Release/Crypta.app
codesign -d --entitlements - DerivedData/Build/Products/Release/Crypta.app
```

The Xcode project's test action is not a hosted UI-test target. Run the two package suites above; interactive smoke checks are recorded evidence, not an automated XCUITest suite. First dependency resolution needs network access; the runtime uses no network service.

## Remaining work

Phase 5 adds inactivity and sleep locking, clipboard ownership/expiration, passphrase-change UI, and broader lifecycle, keyboard, and accessibility testing. Search, basic shortcuts, and orderly Quit were implemented early because they support this phase's workflow. Ordinary text-editor copy operations can still place text on the system clipboard; no expiration is claimed yet.

Phase 6 still requires independent security review, minimum-OS/M1 testing, working sanitizer evidence, dependency provenance/release checks, distribution signing, hardened-runtime verification, and notarization. The local Release signature includes the hardened-runtime flag. The ad-hoc Debug build permits debugger attachment and does not enable hardened runtime; neither configuration is a Developer ID distribution or notarization test. The app is not a reviewed production password manager.

Swift and framework-owned plaintext copies cannot be reliably wiped. No screen-capture protection, persistent draft recovery, disk-wide plaintext audit, full VoiceOver audit, or system-log confidentiality proof is claimed. A forced termination loses unsaved drafts; committed data retains the core's existing atomic-save guarantees.
