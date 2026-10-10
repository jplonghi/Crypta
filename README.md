# Crypta

A native macOS vault project whose encrypted `.crypta` file and master passphrase are sufficient to recover its contents on any compatible computer. No account, server, Keychain entry, or device-bound key is required.

## Current status

**Phase 5 adds automatic locking, managed secret copying, security settings, and master-passphrase changes to the native app.** Use synthetic data during development: independent security review, release hardening, and macOS 14/M1 testing remain pending.

Implemented in [CryptaCore](Packages/CryptaCore/Package.swift):

- Argon2id v1.3 and XChaCha20-Poly1305 through pinned libsodium 1.0.22.
- Random vault keys, authenticated key wrapping, exact UTF-8 passphrases, and owned secret buffers.
- Create, open, read, save, lock, and passphrase changes without re-encrypting the payload.
- Credentials, API tokens, secure notes, custom secrets, flat tags, and Favorites.
- Bounded binary/JSON parsing, strict schema validation, stable IDs, and revision checks.
- Ciphertext-only staging, atomic commits, local writer locking, conflict checks, and ambiguous-commit handling.
- Security, interruption, portability, and independent cryptographic fixtures/tests.

The engine reads schema-1 vaults through a category-to-tag migration and writes validated schema-2 snapshots. Unsupported schemas, unknown fields/types, invalid legacy references, and mismatched vault identities are rejected before a session opens or a save commits. The format is experimental until compatibility and security review are complete.

The app supports create/open/unlock, a three-column vault browser, search, multiple-tag AND filtering, Favorites, tag autocomplete and bulk rename/removal, all four entry editors in the detail pane, explicit encrypted saves, delete confirmation, and manual lock. Drafts remain open after ordinary save failures. No plaintext document autosave, recent-vault list, network access, or device-bound keys are used.

## Run the macOS app

Open `Crypta.xcodeproj`, select the **Crypta** scheme and **My Mac**, then Run. The project defaults to local ad-hoc signing with App Sandbox and user-selected folder access. Distribution signing and notarization belong to Phase 6.

Or build locally:

```sh
xcodebuild -project Crypta.xcodeproj -scheme Crypta -configuration Debug -derivedDataPath DerivedData build
open DerivedData/Build/Products/Debug/Crypta.app
```

Create a vault by choosing a folder, file name, and exact matching passphrases. Opening an existing vault also asks for its containing folder: encrypted atomic saves and writer locks need sibling-file access. The app does not retain persistent folder bookmarks. Use **File → Close Vault** before switching files. Entry changes save only when **Save Entry** succeeds; Cancel discards the draft. Quit offers Save, Discard, or Cancel for an open draft. Locking with an open draft asks before discarding it.

Crypta locks after five minutes of app inactivity by default, and on sleep or macOS session deactivation. Automatic lock discards unsaved drafts immediately. Security Settings (⌘,) offers inactivity choices of 1/5/15/30 minutes or Never; sleep/session locking remains active. Copy buttons clear their own clipboard write after 30 seconds by default, configurable to 15/30/60/120 seconds or only on lock. Intervening clipboard writes are preserved; manually copied editor text is outside this feature.

Use **Vault → Change Master Passphrase** (⇧⌘P) to verify the current passphrase and set an exact matching replacement. Older backups retain their previous passphrase. Find entries with ⌘F, edit the selection with ⌘E, save drafts with ⌘S, and lock with ⇧⌘L. Only the two timeout preferences are saved locally; vault recovery still needs only the file and passphrase.

## Build and test

Use an Apple Silicon Mac and Xcode with a Swift 6 compiler. The app and packages target macOS 14+. Run both presentation and core suites:

```sh
swift test # Desktop presentation tests
swift build --package-path Packages/CryptaCore
swift test --package-path Packages/CryptaCore
swift build -c release --package-path Packages/CryptaCore
```

Initial dependency resolution requires GitHub access. The resolved dependency is pinned in `Package.resolved`; after resolution the core works offline. No Homebrew crypto library is needed. The root package supplies the testable desktop presentation library; `Crypta.xcodeproj` supplies the app bundle.

Minimal API example (use synthetic data during development):

```swift
import CryptaCore
import Foundation

let engine = VaultEngine()
let location = URL(fileURLWithPath: "/path/to/Test.crypta")
var vault = try await engine.create(
    at: location,
    passphrase: "public example passphrase — replace in actual UI",
    name: "Synthetic example"
)
vault.entries.append(VaultEntry(
    title: "Example note",
    createdAt: vault.createdAt,
    tags: ["example"],
    fields: .secureNote(SecureNote(content: "Synthetic text"))
))
vault = try await engine.save(vault: vault) // Keep the returned revision for the next edit.
await engine.lock()
```

`create` refuses an existing destination. Open with `open(at:passphrase:)`, retrieve a caller-owned model snapshot with `readVault()`, and rewrap with `changePassphrase(current:new:)`. Callers must discard model snapshots and editor state when locking. Saving a stale snapshot throws `conflict`; a failed save does not advance its revision. After `durabilityUncertain`, the engine is locked: inspect/reopen the file instead of blindly retrying. See [Phase 3 API and verification notes](Documentation/PHASE_3_RESULTS.md).

## Additional verification

```sh
bash Scripts/fuzz.sh 20000
```

This runs reproducible parser mutations. Set `CRYPTA_FUZZ_ASAN=1` to request AddressSanitizer on a working sanitizer runtime. On the development host, that runtime deadlocked before application startup; no sanitizer pass is claimed.

The test-only Python reference implementation uses separate Argon2 and XChaCha libraries:

```sh
python3 -m venv /tmp/crypta-reference
/tmp/crypta-reference/bin/pip install -r Scripts/reference-requirements.txt
/tmp/crypta-reference/bin/python Scripts/reference_fixture.py --verify Packages/CryptaCore/Tests/CryptaCoreTests/Fixtures/reference-v1.crypta
```

`CryptaTestDriver` is a test harness with fixed public fixture credentials, not a user-facing vault CLI. Never use it for sensitive data.

## Development workspace

The same checkout can be used in Xcode and agent chats. Keep personal notes, chat exports, screenshots, and working prompts in `.local/`, which is excluded from Git along with local agent configuration and the original build prompt. Coordinate edits when several chats use the same checkout; use separate Git worktrees for concurrent changes to the same files.

Build output, local editor state, credentials, signing material, and vault files are excluded from Git. The only allowed `.crypta` file is the documented public compatibility fixture. Ignore rules do not encrypt files or prevent a forced add: use synthetic data for development and inspect the staged changes before committing. Keep real vaults outside the project folder.

## Design and evidence

- [Architecture](ARCHITECTURE.md)
- [Threat model](THREAT_MODEL.md)
- [Vault format](VAULT_FORMAT.md)
- [Security status and limitations](SECURITY.md)
- [Phase 5 lifecycle and usability results](Documentation/PHASE_5_RESULTS.md)
- [Phase 4 app and verification results](Documentation/PHASE_4_RESULTS.md)
- [Phase 3 models and verification results](Documentation/PHASE_3_RESULTS.md)
- [Phase 2 verification results](Documentation/PHASE_2_RESULTS.md)
- [Milestones](Documentation/MILESTONES.md)
- [Dependency assessment](Documentation/DEPENDENCIES.md)
- [Third-party notices](Documentation/THIRD_PARTY_NOTICES.md)

Next: Phase 6 covers security review, dependency provenance, minimum-OS/hardware verification, and release signing/notarization. Passing the current tests is necessary evidence, not a security certification.

Organization and compatibility details: [Tags, Favorites, and schema migration](Documentation/ORGANIZATION_MIGRATION.md).

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for development checks and reporting guidance. The [GitHub workflow](.github/workflows/ci.yml) runs the core and desktop tests, parser mutations, and a locally signed Release build on macOS 15. Hosted results remain pending until the repository is published and the workflow runs.

Crypta is licensed under the [MIT license](LICENSE). Dependencies retain their own licenses; preserve the [third-party notices](Documentation/THIRD_PARTY_NOTICES.md) when distributing the app.
