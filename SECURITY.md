# Security design and status

**Crypta has an experimental Phase 5 native app, vault engine, and domain models. No implementation has been independently audited or released. Do not entrust it with real secrets.** This document distinguishes planned safeguards from verified software behavior.

## Protection status

| Area | Status |
| --- | --- |
| Portable key hierarchy, bounded v1 format, threat model | Implemented experimental binary format and strict schema-2 models with validated schema-1 migration |
| Argon2id / XChaCha20 adapter and secure buffers | Implemented; upstream vectors pass |
| Authentication, malformed-file rejection, atomic persistence | Implemented and tested; see Phase 2 evidence |
| Native UI, explicit encrypted save, manual lock | Implemented; presentation tests and sandboxed UI smoke checks |
| Clipboard expiration, inactivity/sleep/session lock, passphrase-change UI | Implemented; injected-clock/state tests, private pasteboard integration, real-engine rewrap tests |
| Dependency artifact verification and minimum-OS runtime test | Pinned hash/runtime/arm64 metadata verified; provenance and macOS 14 runtime test pending |
| Independent security review, signed/notarized release | Pending |

Detailed test outcomes and limitations: [Phase 2 results](Documentation/PHASE_2_RESULTS.md), [Phase 3 results](Documentation/PHASE_3_RESULTS.md), [Phase 4 results](Documentation/PHASE_4_RESULTS.md), and [Phase 5 results](Documentation/PHASE_5_RESULTS.md).

The public engine rejects unsupported schemas/types/fields before unlocking. All entry values, including plain-display custom fields, remain inside the authenticated ciphertext. Returned model snapshots contain plaintext and must not be logged or retained after lock. Revision checks prevent stale in-session edits; they do not establish freshness against replay of an older valid vault file.

## Memory and diagnostics

Keep keys in explicitly owned guarded buffers; check allocations and memory-locking outcomes, and use libsodium wiping/free functions at the end of ownership. Treat failed page locking as a visible diagnostic capability limitation without logging sensitive data; it does not change the encryption algorithm. Do not retain master passphrase or KEK after the operation that needs them. See [libsodium secure memory documentation](https://libsodium.gitbook.io/doc/memory_management).

Swift `String`, `Data`, copy-on-write storage, text controls, decoding, undo stacks, task captures, and framework internals can create copies that cannot be reliably erased. Wiping a C buffer does not wipe those copies. Clear bindings, cancel secret-bearing tasks, remove undo state and decrypted references on lock, but do not describe that as complete memory erasure. Whole-payload JSON decoding increases exposure; the size cap bounds cost, not confidentiality against a live attacker.

Never log passphrases, keys, entries, clipboard values, plaintext buffers, or full vault URLs. Use stable error codes and public algorithm/version information only. Do not attach model descriptions or raw errors containing user data to diagnostics. No analytics or crash-reporting service. Disable application core dumps where supported for release builds; this cannot prevent all OS diagnostics or privileged capture. FileVault and a supported, updated OS are useful additional protections, not decryption dependencies.

## Clipboard and UI policy

The app hides secrets until an explicit reveal action and disables text-control undo and automatic writing services. Lock clears presentation state, draft bindings, search, and revealed views immediately, cancels pending work, and invalidates its results. It waits for the in-flight operation before releasing the engine session and folder grants. An already-started commit can finish; the lock notice asks users to reopen to inspect an interrupted operation.

Copy buttons use pasteboard change-count ownership without retaining a second secret for comparison. Expiration, lock, and orderly quit clear only the observed owned write. Tests include another writer replacing the clipboard with identical text. The OS comparison and clear are separate calls: a narrow cross-process race remains. Clipboard clearing cannot revoke data captured by a history manager, another app, or a cross-device clipboard service. Concealed and transient types are [community interoperability hints](https://nspasteboard.org/), not enforcement. Ordinary copy actions from editors are not managed by this timer.

App-local input resets a monotonic inactivity deadline; background operations do not. Expiry is checked before an arriving event can renew the session, and before managed copying. A main-run-loop timer checks every half second. Sleep and macOS-session deactivation lock even when inactivity is disabled. Unsubmitted drafts are discarded, as explained in the editor and settings. Tests simulate sleep during delayed unlock, save, and passphrase changes, including services that ignore cancellation. Actual hardware sleep and fast-user-switch testing remain release checks.

Defaults are five minutes for inactivity and thirty seconds for managed clipboard expiration. Only these two non-secret timeout preferences persist in UserDefaults; they are not decryption dependencies. Swift and framework memory copies remain subject to the limitations above.

## Backups and recovery

Back up only closed, committed `.crypta` files. Copying to external disks, SMB, or a cloud folder preserves container encryption but exposes file metadata and may retain many historical ciphertext revisions. Work on one local copy at a time; close it before transfer. Never merge by last-writer-wins. Keep independently verified backups and periodically test opening a copy in a new session.

No reset, recovery account, server key, or hidden backdoor exists in the design. Losing the passphrase or all good file copies loses the vault. Older backups require the passphrase valid for their key slot. Changing a passphrase does not revoke old copies or rotate the vault key. If the old passphrase and an old file may have leaked, create a new vault key, re-encrypt the data, and rotate exposed service credentials. Deleting old revisions from a cloud provider or SSD does not prove secure erasure.

Without an external trusted freshness record, an older valid vault may be replayed undetectably. The core must never require a local counter or Keychain record to recover a valid file.

## Release gates

- Complete the [test matrix](Documentation/MILESTONES.md), parser fuzzing, failure injection, and clean-machine portability checks.
- Validate exact dependency source/binary provenance, runtime version, architecture, licenses, deployment target, and advisory status. Archive hashes and resolved revisions with releases.
- Review AEAD coverage, KDF limits, byte-level passphrase handling, cancellation, file races, and lock/clipboard lifecycle.
- Exercise the oldest supported macOS and Apple Silicon hardware, including sleep, low memory, forced termination, and inaccessible files.
- Audit all disk writes and logs using synthetic recognizable secrets; inspect staging/recovery files and application state. This cannot prove that the OS never writes memory to disk.
- Ship with App Sandbox, only user-selected file access, no network entitlement, hardened runtime, appropriate signing, and notarization. Keep platform bookmark access outside the core. Verify actual entitlements on the built app.
- Obtain independent review before presenting the app as suitable for sensitive production use. Passing tests is necessary, not certification.

## Reporting vulnerabilities

Private vulnerability reporting is enabled for [jplonghi/Crypta](https://github.com/jplonghi/Crypta). Use **Security → Advisories → Report a vulnerability**, or open the [private reporting form](https://github.com/jplonghi/Crypta/security/advisories/new). No response-time promise is established yet.

Use that private form for suspected vulnerabilities. Include the affected revision, platform, reproduction steps, impact, and a synthetic proof of concept. Do not disclose exploitable details in public issues or pull requests. Never submit live passphrases, real vault files, or service credentials, even in a private report. There is currently no supported production release; fixes will target the development version until a release support policy is published.
