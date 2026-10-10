# Threat model

Status: core controls, UI, clipboard and injected sleep/session handling now have implementation/test evidence. [Phase 6 results](Documentation/PHASE_6_RESULTS.md) record internal hardening and the outstanding independent review, real platform tests, native provenance and distribution signing gates. This table states defenses and their limitations; it is not an independent audit.

## Security goals and assets

Protect stored secrets and all entry metadata against disclosure from a stolen or copied locked vault. Detect unauthenticated modification before displaying plaintext. Preserve a previously committed vault after interrupted saves where the filesystem supports the required guarantees. Recover from a compatible vault file plus its exact master passphrase without any device state.

Assets include master passphrase bytes, KEK, vault key, decrypted model, editor drafts, clipboard contents, encrypted backups, and committed user changes. Availability and recovery matter alongside confidentiality. Losing the only file or its passphrase is unrecoverable.

## Trust boundaries

Trust the running application, reviewed dependency artifacts, random source, and uncompromised OS while secrets are in use. Treat vault bytes, file paths, synchronization providers, clipboard readers, and external modifications as untrusted. Filesystem durability and locking are explicit platform assumptions. SwiftUI/AppKit sit outside the portable cryptographic engine.

| Threat | Defense | Residual limitation |
| --- | --- | --- |
| Stolen file or cloud backup | Argon2id, strong passphrase, encrypted metadata | Unlimited offline guessing remains possible; no rate limiter can stop copies. |
| Header/ciphertext edits | Two AEAD domains with explicit shared identity | Structural checks precede authentication; all bounded work remains attacker-triggerable. |
| Cross-vault substitution | Independent random keys and ID-bound AAD | Replacing an entire valid vault cannot be distinguished from opening that vault without trusted external identity. |
| Replay of an older valid file/key slot | Detect in-session changes via ciphertext fingerprint | No portable, stateless way to establish newest version; valid old components can authenticate. |
| Malformed/huge file | Fixed layout, checked arithmetic, strict length/schema/KDF limits | Parsers and dependencies still need fuzzing and review. |
| Crash during save | Ciphertext-only staging, atomic durable commit | Unsubmitted edits may be lost; storage failure and remote semantics are not eliminated. |
| Two Crypta processes | Coordinated lock plus digest comparison | Locks must share a domain; software ignoring the lock can race between the final comparison and rename. |
| Cloud/SMB simultaneous edits | Single-writer workflow and conflict refusal | No distributed locking or synchronization is implemented. |
| Clipboard reader/history | Explicit copy, ownership-safe expiration | Another process can copy a secret immediately and retain it indefinitely. |
| Unattended unlocked app | Inactivity/sleep locking; hidden fields | No protection against use before lock or a failed OS notification. |
| Memory/log disclosure | Short lifetimes, owned key buffers, no secret logs | Swift strings, UI frameworks, registers, swap, or diagnostics may retain copies. |
| Malicious dependency/update | Version pinning, artifact review, signed distribution | Pins alone do not prove binary provenance or eliminate supply-chain compromise. |
| Old passphrase is compromised | Verify and rewrap on ordinary passphrase change | Old backup plus old passphrase reveals unchanged key; actual compromise requires new vault key and credential rotation. |

## Outside the protection boundary

An active memory attacker, compromised kernel, debugger with access, malicious keyboard/input method, screen recorder, clipboard history manager, or malicious Crypta build can capture secrets while unlocked. No memory API makes such a machine trustworthy. Shoulder surfing, coercion, denial of service, secure deletion from SSD/snapshots, and revocation of already copied data are outside the MVP's guarantees.

The format reveals that a file is a Crypta vault, its format/algorithm choices, KDF parameters, stable random vault ID, encrypted size, and normal filesystem name/timestamps. It does not hide existence, approximate content size, or relationships between copied revisions. Padding is deferred.

## Highest-priority design risks

1. A single AAD blob covering mutable key and payload metadata would defeat either efficient passphrase changes or KEK disposal. The split domains in [VAULT_FORMAT.md](VAULT_FORMAT.md) need explicit tampering and replay tests and independent review.
2. Swift canonical-equivalence string comparison can hide passphrase byte differences. Confirmation must compare encoded bytes, and normalization is forbidden.
3. A header is untrusted before authentication. Bound Argon2 cost and allocation before derivation; do not use arbitrary library-maximum parameters from disk.
4. Atomic writes alone do not prevent lost updates. Lock plus compare is required for cooperating local instances, with narrower documented guarantees elsewhere.
5. Locking while work is in flight can expose stale plaintext or lose acknowledged changes. The session state machine must invalidate old completions and separate drafts from durable transactions.
6. Library reputation does not validate the wrapper, binary, format composition, or application. Record exact artifacts and review the complete system before release.

These risks remain review obligations even where Phase 2 tests now exercise the relevant boundary. Reassess the model before attachments, synchronization, biometric unlock, import/export, or multiple key slots.
