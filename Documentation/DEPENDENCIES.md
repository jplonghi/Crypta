# Dependency assessment

Research date: 2026-10-07. Findings below distinguish source inspection from a compiled compatibility test. Phase 2 now resolves the exact package revision below. Release artifact approval and independent audit remain pending.

## Recommended technology

Use libsodium through a minimal internal Swift adapter. `jedisct1/swift-sodium` is the preferred packaging candidate; its `Clibsodium` product allows direct calls needed for explicit parameters, authenticated associated data, guarded buffers, and deterministic errors. Avoid spreading raw C calls through the domain or UI. The higher-level `Sodium` wrapper is useful but must not force extra key copies or hide necessary options.

The [swift-sodium releases page](https://github.com/jedisct1/swift-sodium/releases) identifies 0.11.0 as its latest release at inspection and reports updated bundled libsodium and Apple/non-Apple packaging work. The [0.11.0 manifest](https://raw.githubusercontent.com/jedisct1/swift-sodium/0.11.0/Package.swift) uses Swift tools 5.8 and exposes `Clibsodium` and `Sodium`; on Apple it selects a bundled XCFramework. Its [XCFramework manifest](https://raw.githubusercontent.com/jedisct1/swift-sodium/0.11.0/Clibsodium.xcframework/Info.plist) explicitly lists a macOS arm64 slice. This is evidence of SwiftPM and Apple Silicon packaging, not proof that the binary runs on macOS 14.

The [libsodium release list](https://github.com/jedisct1/libsodium/releases) identifies 1.0.22 as latest at inspection. Its [release notes](https://github.com/jedisct1/libsodium/releases/tag/1.0.22-RELEASE) include ARM Argon2 and packaging changes. Release activity supports using libsodium as a maintained candidate. It does not establish that swift-sodium bundles that exact native release. Phase 2 subsequently verified native headers/runtime as 1.0.22 and arm64 archive metadata as macOS 11.0 minimum; the macOS 14 runtime test is still pending.

The candidate is mature and its primitives have public specifications and extensive existing implementations/tests. This assessment has not established an independent audit covering the exact current Swift wrapper and binary. Do not claim it is an audited Crypta dependency without verifying the audit's scope and version.

## Dependency integration and remaining release checks

Pinned swift-sodium 0.11.0 at `cfd195c76882aa9b997560ca7cb95d72fbf5db00` in Package.resolved. The package builds under Swift 6 in debug/release. The native archive hash, runtime version, load-path check and fixture provenance are recorded in [Phase 2 results](PHASE_2_RESULTS.md). The swift-sodium GitHub advisory page showed no published advisories when checked; the libsodium advisory page could not be retrieved in that check. This is not a complete advisory audit or a claim of no vulnerabilities.

The original integration gates below remain the release checklist; only the recorded evidence should be treated as complete.

1. Inspect the exact tagged source, distribution license, native version headers, macOS library build metadata, and upstream security advisories. Verify tag/revision and downloaded artifact hashes. Do not infer binary contents from a release title.
2. Resolve an exact reviewed tag/commit, commit `Package.resolved`, and record the XCFramework hash and runtime `sodium_version_string()` in development evidence. Avoid floating branches or automatic upgrades.
3. Build and link a minimal `Clibsodium` consumer using Swift 6 strict concurrency, targeting macOS 14 arm64. Run it on the oldest supported system and inspect dependency load paths. Confirm no Homebrew library is required by the distributed app.
4. Exercise `sodium_init`, random generation, Argon2id, XChaCha AEAD/AAD, constant-time equality, and guarded buffer cleanup. Check native error paths as well as happy paths.
5. If the binary lacks acceptable provenance or platform support, build the same reviewed libsodium release from source into a project-controlled artifact with documented reproducible steps. Do not substitute a homegrown KDF or cipher.

## Primitive references

- [libsodium KDF API](https://doc.libsodium.org/password_hashing/default_phf): exact salt/parameter storage and explicit algorithm selection.
- [Argon2id implementation](https://raw.githubusercontent.com/jedisct1/libsodium/1.0.22-RELEASE/src/libsodium/crypto_pwhash/argon2/pwhash_argon2id.c): API maps memory bytes to KiB and uses one lane.
- [RFC 9106](https://www.rfc-editor.org/rfc/rfc9106.html): Argon2 specification and published vectors. Its recommended multi-lane profile is not identical to the proposed libsodium profile.
- [XChaCha20-Poly1305 API](https://doc.libsodium.org/secret-key_cryptography/aead/chacha20-poly1305/xchacha20-poly1305_construction): nonce/tag sizes, AAD and authentication behavior.
- [libsodium secure memory](https://libsodium.gitbook.io/doc/memory_management): explicit clearing and the limits of page locking.
- [Apple CryptoKit](https://developer.apple.com/documentation/cryptokit) and [AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm): alternative Apple-native AEAD surface. The web reader could not render the full API pages; recheck the target SDK interface during integration.

No additional database, network, telemetry, account, or synchronization dependency is proposed.
