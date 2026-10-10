# Phase 2 implementation and verification

Historical milestone report, 2026-10-07. The opaque JSON API described here has since been replaced by the typed API in [Phase 3](PHASE_3_RESULTS.md). The core engine milestone is implemented; deployment and independent security-review gates remain open. No UI or domain entry types are implemented.

## Delivered

`Packages/CryptaCore` is a Swift 6 package targeting macOS 14. It imports Foundation, Darwin for macOS persistence, and Clibsodium. It has no SwiftUI, AppKit, Keychain, Secure Enclave, account, or network dependency at runtime. The on-disk format is portable; the current persistence implementation is macOS-specific.

`VaultEngine` is an actor with synchronous, non-suspending transactions. Await its public operations from the caller. Native KDF work runs on its executor, with a process-wide lock limiting derivation concurrency. Cancellation is checked before expensive work and before commits/session installation; native Argon2 is not interruptible. There are no detached tasks holding keys and no suspension points that can publish a stale in-flight result after a completed lock. The app must cancel pending unlock tasks, obscure the UI immediately, and then await lock; actors do not promise FIFO ordering among independently submitted tasks.

The engine holds the encrypted container and a guarded vault-key buffer, not a decrypted payload cache. It reports whether key memory locking succeeded. Passphrase-derived keys and temporary decrypt buffers are wiped; retained vault-key storage is wiped on lock/free. Swift strings, validator arrays, temporary Data and caller-owned plaintext copies cannot be comprehensively erased. No plaintext or secret is logged by the library.

Typed schema enforcement is explicitly deferred to Phase 3. The Phase 2 parser requires a UTF-8 JSON object and checks syntax, duplicate keys, finite numbers, strings, nesting, and global collection bounds. It does not yet enforce schemaVersion, entry types, per-domain-field limits, or matching payload vaultID. Do not treat its opaque JSON API as the final app model.

## Evidence

| Check | Result |
| --- | --- |
| Swift 6 debug test suite | 18 tests in five suites passed, including every fixed-header byte mutation and every truncation of a generated sample |
| Release build and optimized tests | Passed; 17 tests passed (the debug-only forced-crash test is excluded) |
| Upstream known-answer vectors | Argon2id and XChaCha matched pinned libsodium published outputs |
| Independent implementation | argon2-cffi/reference Argon2 + PyCryptodome fixture opens in Swift; Python also decrypts a Swift-created file |
| Fresh process | A separate test-driver process opens the reference fixture with only file and public passphrase |
| Local contention | Python process holding the advisory lock blocks a writer; a separate Swift stale writer cannot overwrite a newer save |
| Crash simulation | `_exit(77)` before rename leaves old primary and recoverable encrypted staging; after rename leaves valid new primary |
| I/O failure injection | Pre/post-rename failures, short writes, EINTR retry, simulated ENOSPC, permission denial, and missing files covered |
| Path handling | Symlink, hard-link, FIFO rejection; exclusive creation refuses existing files |
| Parser mutation harness | 20,000 deterministic mutations, in addition to 5,000 random malformed inputs in unit tests; no reported failure |
| AddressSanitizer | NOT passed: installed runtime deadlocks in ASan initialization before `main`; sampled and stopped |
| Runtime environment | Apple Swift 6.2.3; macOS 26.6.2; arm64; deployment target macOS 14 |
| Default KDF timing | One debug measurement: create 0.415 s, unlock 0.396 s, 256 MiB / 3 passes / 1 lane |
| Oldest OS / M1 / other physical Mac | Not available for this verification; still required before release |

Timing includes full engine operations and file I/O, not just Argon2. It is not a statistical benchmark, M1 claim, peak-memory measurement, or measurement under memory pressure. The KDF profile remains provisional for release.

The mutation harness is reproducible smoke fuzzing, not coverage-guided exhaustive fuzzing. Apple's compiler rejected `-sanitize=fuzzer` on this target. The optional ASan mode remains available for a compatible toolchain/runtime; the current uninstrumented result must not be described as sanitizer evidence.

## Persistence semantics

Staging files and stable sidecar locks use mode 0600. A lock does not contain keys and is not needed for decryption or transfer. Do not delete a lock sidecar while cooperating instances may still be using it. File reads require a regular, singly linked file and reject a final symlink; parent directories are canonicalized and held by directory descriptor during each operation.

The writer compares inode/device and SHA-256 ciphertext digest under an advisory lock, writes a unique sibling staging file, handles interrupted/short writes, calls file `fsync` and `F_FULLFSYNC`, closes it, and atomically renames. Initial creation uses `RENAME_EXCL`. It then syncs the directory and rereads the committed file. Failure after rename yields `durabilityUncertain` and locks the session, requiring explicit reconciliation by reopening. No silent retry or claim of rollback is made.

The tests validate process interruption and injected errors on this local filesystem. They cannot simulate physical power loss or prove every filesystem's durability. Noncooperating writers retain a race window; network/cloud storage is not a distributed lock domain. Use one writer on a local copy and close before copying it elsewhere.

An orphan staging container can be opened explicitly via the same authenticated `open` API; it is never auto-promoted. Discovery/recovery UI remains future app work.

## Format and dependency evidence

- Format fixture SHA-256: `5a5c6c4f691f27a33e866195164988c72d623b2f95bca909192063aabd2a8845`.
- swift-sodium: 0.11.0, revision `cfd195c76882aa9b997560ca7cb95d72fbf5db00`.
- Native runtime and header version: libsodium 1.0.22.
- macOS universal archive SHA-256: `9e00d236b5fc294f48825edbc1ca8971dc418363dae8cc7787004d63454ed563`.
- Inspected arm64 archive object deployment metadata: macOS 11.0 minimum.
- Test-driver dynamic load paths use system libraries/frameworks; no Homebrew libsodium dependency.
- Published upstream vector source revision: `77e1ce5d6dee871c49ef211222ba18ef0c486bda`.

An archive hash identifies the inspected bytes; it is not proof that the binary was reproducibly built from its claimed source. GitHub's release information is not a locally verified signing chain. Reproducible artifact provenance, broader advisory review and independent audit remain release gates.

## Reproduction

Use the README's `swift test`, release build, and fuzz commands. Tests use temporary directories and public synthetic secrets only. Python fixture dependencies are pinned separately in `Scripts/reference-requirements.txt` and do not enter the app dependency graph. `Scripts/reference_fixture.py --generate` regenerates the immutable public reference fixture deterministically; review any fixture diff before accepting a format change.

The core source was inspected for logging and prohibited platform dependencies. No library print/log calls or UI/device-key imports are present. That inspection and plaintext staging checks do not prove that an OS, debugger, crash reporter, or framework never retains plaintext.
