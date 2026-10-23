# Security policy

**Crypta is experimental and has not been independently audited. No supported production release is available. Use synthetic data while evaluating it.**

## Reporting vulnerabilities

Use [GitHub's private vulnerability reporting form](https://github.com/jplonghi/Crypta/security/advisories/new). Include the affected revision, platform, reproduction steps, impact, and a synthetic example. Do not publish unresolved exploit details in public issues or pull requests, and never submit real vaults, passphrases, or service credentials. No response-time commitment is established; fixes target the development version.

## Security model

Crypta protects the contents and metadata of a locked vault against disclosure from a copied file and authenticates modified data before exposing it. Decryption requires the vault file and exact master-passphrase bytes, with no account, server key, Keychain record, or device state.

- Argon2id derives a temporary key that wraps a random vault key. XChaCha20-Poly1305 authenticates the key envelope and complete payload.
- Public structure and resource limits are checked before expensive key derivation. Authenticated payloads undergo strict schema validation.
- Saves use ciphertext-only staging, atomic replacement, writer locks, and file fingerprints. Ambiguous post-rename failures require locking and reopening.
- The app uses App Sandbox with user-selected read/write access and no network entitlement. It has no telemetry or crash-reporting service.

The [vault format](VAULT_FORMAT.md) defines the cryptographic composition, limits, payload structure, and persistence contract. The pinned Swift package vendors a native libsodium archive: version pins and hashes identify that artifact but do not prove reproducible source-to-binary provenance.

## Threats and limits

| Threat | Protection and remaining limit |
| --- | --- |
| Stolen vault or backup | Memory-hard derivation and encrypted metadata; an attacker can still guess passphrases offline without a rate limit. |
| Malformed or modified file | Bounded parsing and authenticated encryption; parsing and resource use remain attacker-triggerable within those limits. |
| Replaced or older valid vault | In-session fingerprints detect changes, but there is no trusted external identity or freshness record to prevent complete substitution or rollback. |
| Interrupted save or concurrent writer | Encrypted staging and local locking protect confirmed saves under supported filesystem semantics. A writer ignoring the lock can race between comparison and rename. Remote/cloud filesystems have no distributed conflict guarantee. |
| Unattended app | Inactivity, sleep, and session locking reduce exposure; they cannot protect access before locking or compensate for missing OS notifications. |
| Live memory, screen, keyboard, or clipboard access | An unlocked vault can be captured by a compromised OS, privileged process, debugger, input method, screen recorder, or clipboard reader. These are outside Crypta's protection boundary. |
| Dependency or build compromise | Pinned dependencies and review reduce risk; they do not establish that the running binary is trustworthy. |

The format reveals its identifiers, KDF parameters, random vault ID, encrypted size, and normal filesystem name/timestamps. It does not hide the existence of a vault or relationships between copied revisions. Availability, coercion, secure deletion from SSDs/snapshots, and revocation of captured data are not guaranteed.

## Memory, UI, and clipboard

Owned native key buffers use guarded allocation and explicit wiping. Swift strings, data buffers, decoded models, task captures, and UI/framework internals can retain copies that cannot be reliably erased. Page locking, where available, does not protect every plaintext copy or prevent all OS diagnostics and privileged capture.

Lock clears displayed snapshots, drafts, search and revealed state, invalidates late completions, and waits for in-flight work before releasing the engine session. A commit already underway can finish while locking. Automatic lock discards unsaved drafts. Text controls disable undo and automatic writing services where supported.

Managed copy buttons track pasteboard ownership and clear only Crypta's observed write at expiry, lock, or orderly quit. The ownership comparison and clear are separate calls, leaving a narrow cross-process race. Clearing cannot revoke data captured by another app or clipboard history service. Manual copy from editors is outside the managed timer.

Only the two timeout preferences persist in UserDefaults. Never log passphrases, keys, entries, clipboard values, plaintext buffers, or full vault paths. Returned model snapshots are plaintext and must not be logged or retained after lock.

## Backups and compatibility

Work on one local copy at a time and close it before transfer. Keep encrypted backups and test opening a copy in a fresh session. File names and metadata remain visible, and storage or cloud providers may retain historical revisions.

There is no reset or recovery backdoor. Losing the passphrase or every good file copy loses the vault. Passphrase changes rewrap the existing vault key; old backups keep their old passphrase. An old file and old passphrase can therefore reveal the unchanged key. Compromise recovery requires a new vault key and rotation of exposed service credentials. Deleting old copies does not prove secure erasure.

Crypta is an unshipped personal POC with one current payload structure and no schema versions or migrations. Compatibility with earlier development vaults is not maintained; recreate synthetic vaults when the payload structure changes. See the [current payload contract](VAULT_FORMAT.md#encrypted-payload).

## Before a production release

Independent review and remediation, native-library build provenance, macOS 14 and low-memory/hardware testing, actual sleep/session and accessibility checks, and Developer ID signing/notarization remain required. Automated tests, sanitizer runs, and locally ad-hoc signed builds do not replace those checks or certify security.
