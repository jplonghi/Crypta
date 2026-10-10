# Crypta independent security review brief

## Objective and revision

Assess whether Crypta's file-plus-passphrase design safely protects a locked vault, authenticates untrusted input before exposing contents, and preserves confirmed saves under its stated local-filesystem assumptions. Review the complete path from container bytes to UI and back; reviewing libsodium alone is insufficient.

Repository: [jplonghi/Crypta](https://github.com/jplonghi/Crypta). Before starting, record an agreed full commit SHA (`git rev-parse HEAD`), dependency resolutions, OS/toolchain and artifact hashes. Review the Phase 6 branch after its fixes are frozen. Report the reviewed SHA and the separate remediation/retest SHA. This brief is ready for handoff; no external assessor has yet been commissioned.

## Scope

| Area | Sources and questions |
| --- | --- |
| Key hierarchy and AEAD | `Security/Crypto.swift`, `Services/VaultEngine.swift`, `Format/VaultFormat.swift`, `VAULT_FORMAT.md`; validate Argon2id parameters, randomness, wrap/payload AAD, key disposal, cross-vault substitution and mutable-component replay |
| Untrusted parsing | `Format/JSONValidator.swift`, `Format/VaultCodec.swift`, domain decoders/validation; investigate checked sizes, nesting, UTF-8, duplicate/escaped keys, integer handling, unknown fields/types, legacy category migration and expansion limits |
| Persistence and concurrency | `Persistence/EncryptedFileStore.swift`; assess no-follow checks, hard links, directory binding, lock aliases, short writes, flush/rename boundaries, noncooperating writers, post-rename uncertainty and orphan recovery |
| Sensitive state and errors | `CryptaApp/Presentation`; create/unlock/read failure cleanup, cancellation, late callbacks, drafts, snapshots, passphrase change and stable errors without secret-bearing decoder messages |
| macOS lifecycle and UI | `CryptaApp/Platform` and `Features`; actual sleep/session events, idle expiry, core-dump startup policy, page-lock diagnostics, text-service/undo suppression, clipboard ownership races, termination and state restoration |
| Dependencies and distribution | Resolved pins, vendored XCFramework, native provenance/advisories/licenses, actual built entitlements, runtime linking, hardened runtime, signing/notarization and minimum-OS execution |
| Confidentiality outside the vault | Inspect logs, preferences, diagnostics, staging, restoration, clipboard and filesystem writes with synthetic markers; account for framework/OS memory copies |

Core source paths above are relative to `Packages/CryptaCore/Sources/CryptaCore`. Existing controls and assumptions are described in [SECURITY.md](../SECURITY.md), [THREAT_MODEL.md](../THREAT_MODEL.md), [ARCHITECTURE.md](../ARCHITECTURE.md), and [Phase 6 evidence](PHASE_6_RESULTS.md). Confirm claims independently rather than treating those documents as evidence by themselves.

## Reproduction material

Build with the committed package resolutions. Run the engine/desktop suites, sanitizer checks, deterministic parser mutations and Release build using the commands in the Phase 6 report. Tests contain synthetic corruption, truncation, migration, cancellation, short writes/disk-full injection, cross-process locking, interrupted commits, real-engine passphrase changes and clipboard ownership cases.

The public immutable reference fixture and its manifest are in `Packages/CryptaCore/Tests/CryptaCoreTests/Fixtures`. `Scripts/reference_fixture.py` supplies a separate test implementation with pinned development-only Python dependencies. The reference vectors establish compatibility; they are not an independent assessment of Crypta. `CryptaTestDriver` uses fixed public credentials and must never process real user data.

Use a dedicated macOS test user/device and synthetic passphrases, recognizable entry markers, copied backups and fresh folders. Include actual release-app behavior on macOS 14 and Apple Silicon, sleep/user-switch, memory pressure, forced termination, unavailable storage and external changes. Signing/notarization requires a future release candidate; the current ad-hoc build cannot satisfy that check.

## Required deliverables

1. Private report with scope, exact revisions, methods, severity/impact, affected code, synthetic reproductions, recommended fixes and explicit exclusions.
2. Separate conclusions on primitive integration, format composition, parser bounds, durability/conflict assumptions, and lifecycle/memory confidentiality. Identify claims the product/docs must narrow.
3. Remediation review and retest of agreed findings, recording outstanding issues and limitations. Do not mark a finding fixed solely because a developer added a test.
4. A publishable summary agreed with the maintainer after remediation, stating what was assessed and what was not. Avoid unsupported certification or blanket “secure” claims.

Use the repository's [private vulnerability reporting form](https://github.com/jplonghi/Crypta/security/advisories/new) for suspected exploitable findings. Do not place live vaults, credentials or unresolved exploit details in public issues/PRs. The review does not require access to real secrets.

Known limits that still need assessment include Swift/framework copies, uninstrumented bundled native code, noncooperating-writer races, clipboard capture/races, old-backup/replay behavior and incomplete native-binary provenance. A compensated independent specialist or qualified external team can provide this review; development-agent testing does not replace it.
